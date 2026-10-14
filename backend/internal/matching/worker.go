package matching

import (
	"context"
	"errors"
	"log/slog"
	"sort"
	"sync"
	"time"
)

// WorkerOption allows configuring matching.Worker settings.
type WorkerOption func(*Worker)

// WithSweepInterval sets the periodic sweep timer interval.
func WithSweepInterval(d time.Duration) WorkerOption {
	return func(w *Worker) {
		w.sweepInterval = d
	}
}

// WithOlderThan sets the age threshold for retrying open requests in the sweep.
func WithOlderThan(d time.Duration) WorkerOption {
	return func(w *Worker) {
		w.olderThan = d
	}
}

// WithChannelSize sets the buffer size for the requests channel.
func WithChannelSize(size int) WorkerOption {
	return func(w *Worker) {
		w.requestChan = make(chan string, size)
	}
}

// Notifier defines the interface for emitting notifications.
type Notifier interface {
	Send(ctx context.Context, userID, notificationType string, payload map[string]any) error
}

// WithNotifier configures a notifier for emitting notifications on match found.
func WithNotifier(n Notifier) WorkerOption {
	return func(w *Worker) {
		w.notifier = n
	}
}

// Worker is an in-process background worker that processes match requests.
type Worker struct {
	repo          *Repository
	notifier      Notifier
	requestChan   chan string
	sweepInterval time.Duration
	olderThan     time.Duration
	mu            sync.Mutex
	running       bool
}

// NewWorker initializes a new matching Worker.
func NewWorker(repo *Repository, opts ...WorkerOption) *Worker {
	w := &Worker{
		repo:          repo,
		requestChan:   make(chan string, 256),
		sweepInterval: 5 * time.Minute,
		olderThan:     2 * time.Minute,
	}
	for _, opt := range opts {
		opt(w)
	}
	return w
}

// SetNotifier sets the notifier on the matching Worker.
func (w *Worker) SetNotifier(n Notifier) {
	w.notifier = n
}


// Enqueue sends a request ID to the worker's buffered channel without blocking.
func (w *Worker) Enqueue(requestID string) {
	if requestID == "" {
		return
	}
	select {
	case w.requestChan <- requestID:
	default:
		slog.Warn("matching worker channel full, request will be picked up by sweep ticker", "request_id", requestID)
	}
}

// Start begins processing matching requests and the sweep ticker until context cancellation.
func (w *Worker) Start(ctx context.Context) {
	w.mu.Lock()
	if w.running {
		w.mu.Unlock()
		return
	}
	w.running = true
	w.mu.Unlock()

	defer func() {
		w.mu.Lock()
		w.running = false
		w.mu.Unlock()
	}()

	ticker := time.NewTicker(w.sweepInterval)
	defer ticker.Stop()

	slog.Info("Matching worker started", "sweep_interval", w.sweepInterval, "older_than", w.olderThan)

	for {
		select {
		case <-ctx.Done():
			slog.Info("Matching worker stopping due to context cancellation")
			return
		case reqID := <-w.requestChan:
			if err := w.ProcessRequest(ctx, reqID); err != nil && !errors.Is(err, context.Canceled) {
				slog.Debug("process request result", "request_id", reqID, "error", err)
			}
		case <-ticker.C:
			if err := w.Sweep(ctx); err != nil && !errors.Is(err, context.Canceled) {
				slog.Error("error during matching sweep", "error", err)
			}
		}
	}
}

type candidateScore struct {
	candidate *Request
	score     int
}

// ProcessRequest evaluates potential matches for a given request and pairs with the best match.
func (w *Worker) ProcessRequest(ctx context.Context, requestID string) error {
	// 1. Fetch current request details
	req, err := w.repo.GetRequestDetails(ctx, requestID)
	if err != nil {
		if errors.Is(err, ErrRequestNotFound) {
			return nil
		}
		return err
	}

	// 2. Double-check request is still open
	baseReq, err := w.repo.GetByID(ctx, requestID)
	if err != nil {
		return err
	}
	if baseReq.Status != PodRequestStatusOpen {
		return nil
	}

	// 3. Find candidates (filtered by category, language, non-blocked)
	candidates, err := w.repo.FindCandidateRequests(ctx, req)
	if err != nil {
		return err
	}
	if len(candidates) == 0 {
		return nil
	}

	// 4. Score each candidate
	var scoredCandidates []candidateScore
	for _, cand := range candidates {
		score, ok := Score(*req, *cand)
		if ok {
			scoredCandidates = append(scoredCandidates, candidateScore{
				candidate: cand,
				score:     score,
			})
		}
	}

	if len(scoredCandidates) == 0 {
		return nil
	}

	// 5. Sort candidates by score DESC, and tie-breaker older requests first
	sort.Slice(scoredCandidates, func(i, j int) bool {
		if scoredCandidates[i].score != scoredCandidates[j].score {
			return scoredCandidates[i].score > scoredCandidates[j].score
		}
		return scoredCandidates[i].candidate.CreatedAt.Before(scoredCandidates[j].candidate.CreatedAt)
	})

	// 6. Attempt pairing in descending score order
	for _, item := range scoredCandidates {
		podID, err := w.repo.PairRequests(ctx, req, item.candidate)
		if err == nil {
			slog.Info("Matched users into new pod",
				"pod_id", podID,
				"req_a", req.ID, "user_a", req.UserID,
				"req_b", item.candidate.ID, "user_b", item.candidate.UserID,
				"score", item.score,
			)
			if w.notifier != nil {
				payload := map[string]any{
					"type":   "match_found",
					"pod_id": podID,
					"title":  "Match Found!",
					"body":   "You've been paired with an accountability partner!",
				}
				_ = w.notifier.Send(ctx, req.UserID, "match_found", payload)
				_ = w.notifier.Send(ctx, item.candidate.UserID, "match_found", payload)
			}
			return nil

		}
		if errors.Is(err, ErrPairingConflict) {
			// One of the requests was no longer open or active pod conflict; continue to next candidate
			continue
		}
		return err
	}

	return nil
}

// Sweep checks for open requests older than the configured threshold and retries matching.
func (w *Worker) Sweep(ctx context.Context) error {
	cutoff := time.Now().UTC().Add(-w.olderThan)
	olderReqs, err := w.repo.GetOpenRequestsOlderThan(ctx, cutoff)
	if err != nil {
		return err
	}

	for _, req := range olderReqs {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			_ = w.ProcessRequest(ctx, req.ID)
		}
	}
	return nil
}
