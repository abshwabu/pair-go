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

// WithProposalSweepInterval sets the proposal expiry sweep interval.
func WithProposalSweepInterval(d time.Duration) WorkerOption {
	return func(w *Worker) {
		w.proposalSweepInterval = d
	}
}

// WithProposalTTL sets the time-to-live for match proposals.
func WithProposalTTL(d time.Duration) WorkerOption {
	return func(w *Worker) {
		w.proposalTTL = d
	}
}

// WithClock sets the clock used by the worker.
func WithClock(c Clock) WorkerOption {
	return func(w *Worker) {
		w.clock = c
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

// WithNotifier configures a notifier for emitting notifications.
func WithNotifier(n Notifier) WorkerOption {
	return func(w *Worker) {
		w.notifier = n
	}
}

// Worker is an in-process background worker that processes match requests.
type Worker struct {
	repo                  *Repository
	notifier              Notifier
	requestChan           chan string
	sweepInterval         time.Duration
	proposalSweepInterval time.Duration
	olderThan             time.Duration
	proposalTTL           time.Duration
	clock                 Clock
	mu                    sync.Mutex
	running               bool
}

// NewWorker initializes a new matching Worker.
func NewWorker(repo *Repository, opts ...WorkerOption) *Worker {
	w := &Worker{
		repo:                  repo,
		requestChan:           make(chan string, 256),
		sweepInterval:         5 * time.Minute,
		proposalSweepInterval: 1 * time.Minute,
		olderThan:             2 * time.Minute,
		proposalTTL:           12 * time.Hour,
		clock:                 repo.Clock(),
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

// SetProposalTTL sets the TTL for match proposals.
func (w *Worker) SetProposalTTL(ttl time.Duration) {
	w.proposalTTL = ttl
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

// Start begins processing matching requests and the sweep tickers until context cancellation.
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

	sweepTicker := time.NewTicker(w.sweepInterval)
	defer sweepTicker.Stop()

	propSweepTicker := time.NewTicker(w.proposalSweepInterval)
	defer propSweepTicker.Stop()

	slog.Info("Matching worker started",
		"sweep_interval", w.sweepInterval,
		"proposal_sweep_interval", w.proposalSweepInterval,
		"older_than", w.olderThan,
		"proposal_ttl", w.proposalTTL,
	)

	for {
		select {
		case <-ctx.Done():
			slog.Info("Matching worker stopping due to context cancellation")
			return
		case reqID := <-w.requestChan:
			if err := w.ProcessRequest(ctx, reqID); err != nil && !errors.Is(err, context.Canceled) {
				slog.Debug("process request result", "request_id", reqID, "error", err)
			}
		case <-propSweepTicker.C:
			if err := w.SweepExpiredProposals(ctx); err != nil && !errors.Is(err, context.Canceled) {
				slog.Error("error during proposal expiry sweep", "error", err)
			}
		case <-sweepTicker.C:
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

// ProcessRequest evaluates potential matches for a given request and proposes a match.
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

	// 3. Find candidates (filtered by category, language, non-blocked, non-rejected)
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

	// 6. Attempt proposing in descending score order
	for _, item := range scoredCandidates {
		proposalID, err := w.repo.Propose(ctx, req, item.candidate, w.proposalTTL)
		if err == nil {
			slog.Info("Created match proposal for users",
				"proposal_id", proposalID,
				"req_a", req.ID, "user_a", req.UserID,
				"req_b", item.candidate.ID, "user_b", item.candidate.UserID,
				"score", item.score,
			)
			if w.notifier != nil {
				payload := map[string]any{
					"type":        "match_proposed",
					"proposal_id": proposalID,
					"title":       "We found you a partner",
					"body":        "Tap to see your match",
				}
				_ = w.notifier.Send(ctx, req.UserID, "match_proposed", payload)
				_ = w.notifier.Send(ctx, item.candidate.UserID, "match_proposed", payload)
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

// SweepExpiredProposals checks for expired proposals, transitions them, and handles reopen/cancel and notifications.
func (w *Worker) SweepExpiredProposals(ctx context.Context) error {
	actions, err := w.repo.ExpirePendingProposals(ctx)
	if err != nil {
		return err
	}

	for _, act := range actions {
		for _, reqID := range act.ReopenedReqs {
			w.Enqueue(reqID)
		}
		if w.notifier != nil {
			for _, uID := range act.NotifUsers {
				payload := map[string]any{
					"type":  "match_declined",
					"title": "Still looking",
					"body":  "Your match didn't respond in time, we're finding you someone new",
				}
				_ = w.notifier.Send(ctx, uID, "match_declined", payload)
			}
		}
	}

	return nil
}

// Sweep checks for open requests older than the configured threshold and retries matching.
func (w *Worker) Sweep(ctx context.Context) error {
	// 1. Run proposal expiry first
	_ = w.SweepExpiredProposals(ctx)

	// 2. Retry open requests
	cutoff := w.clock.Now().UTC().Add(-w.olderThan)
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
