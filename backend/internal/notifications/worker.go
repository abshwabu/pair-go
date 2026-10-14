package notifications

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/abshwabu/pair/backend/internal/users"
)

// WorkerOption configures Worker settings.
type WorkerOption func(*Worker)

// WithWorkerTicker sets the periodic drain ticker interval.
func WithWorkerTicker(d time.Duration) WorkerOption {
	return func(w *Worker) {
		if d > 0 {
			w.tickerDur = d
		}
	}
}

// WithBaseBackoff sets the base duration used for exponential backoff on retry.
func WithBaseBackoff(d time.Duration) WorkerOption {
	return func(w *Worker) {
		if d > 0 {
			w.baseBackoff = d
		}
	}
}

// Worker processes the notifications outbox and delivers push messages via FCM.
type Worker struct {
	repo        *Repository
	usersRepo   *users.Repository
	fcmClient   FCMClient
	notifyCh    <-chan struct{}
	tickerDur   time.Duration
	baseBackoff time.Duration

	mu        sync.Mutex
	attempts  map[string]int
	nextRetry map[string]time.Time
	running   bool
}

// NewWorker initializes a new notifications Worker.
func NewWorker(repo *Repository, usersRepo *users.Repository, fcmClient FCMClient, notifyCh <-chan struct{}, opts ...WorkerOption) *Worker {
	w := &Worker{
		repo:        repo,
		usersRepo:   usersRepo,
		fcmClient:   fcmClient,
		notifyCh:    notifyCh,
		tickerDur:   30 * time.Second,
		baseBackoff: 100 * time.Millisecond,
		attempts:    make(map[string]int),
		nextRetry:   make(map[string]time.Time),
	}
	for _, opt := range opts {
		opt(w)
	}
	return w
}

// Drain queries all currently unsent notifications and processes them.
func (w *Worker) Drain(ctx context.Context) error {
	unsent, err := w.repo.GetUnsent(ctx, 100)
	if err != nil {
		return fmt.Errorf("failed to get unsent notifications: %w", err)
	}
	if len(unsent) == 0 {
		return nil
	}

	now := time.Now().UTC()
	for _, item := range unsent {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		w.mu.Lock()
		retryAt, hasRetry := w.nextRetry[item.ID]
		if hasRetry && now.Before(retryAt) {
			w.mu.Unlock()
			continue
		}
		w.mu.Unlock()

		// If user has no FCM token registered, notification remains visible in-app; mark sent_at to avoid re-querying
		if item.FCMToken == nil || *item.FCMToken == "" {
			if err := w.repo.MarkSent(ctx, item.ID, now); err != nil {
				slog.Error("Failed to mark notification without FCM token as sent", "id", item.ID, "error", err)
			}
			continue
		}

		// Prepare push notification payload
		var payloadMap map[string]any
		_ = json.Unmarshal(item.Payload, &payloadMap)

		title := "Pair Notification"
		body := ""
		if t, ok := payloadMap["title"].(string); ok && t != "" {
			title = t
		}
		if b, ok := payloadMap["body"].(string); ok && b != "" {
			body = b
		}

		data := make(map[string]string)
		for k, v := range payloadMap {
			data[k] = fmt.Sprintf("%v", v)
		}

		push := PushPayload{
			Token: *item.FCMToken,
			Title: title,
			Body:  body,
			Data:  data,
		}

		err := w.fcmClient.SendPush(ctx, push)
		if err == nil {
			// Delivery succeeded
			if err := w.repo.MarkSent(ctx, item.ID, time.Now().UTC()); err != nil {
				slog.Error("Failed to mark delivered notification as sent", "id", item.ID, "error", err)
			}
			w.mu.Lock()
			delete(w.attempts, item.ID)
			delete(w.nextRetry, item.ID)
			w.mu.Unlock()
			continue
		}

		// Handle unregistered device token
		if IsUnregisteredToken(err) {
			slog.Warn("FCM token reported unregistered, clearing user token", "user_id", item.UserID, "token", *item.FCMToken)
			if err := w.usersRepo.UpdateFCMToken(ctx, item.UserID, nil); err != nil {
				slog.Error("Failed to clear unregistered FCM token", "user_id", item.UserID, "error", err)
			}
			if err := w.repo.MarkSent(ctx, item.ID, time.Now().UTC()); err != nil {
				slog.Error("Failed to mark unregistered notification as sent", "id", item.ID, "error", err)
			}
			w.mu.Lock()
			delete(w.attempts, item.ID)
			delete(w.nextRetry, item.ID)
			w.mu.Unlock()
			continue
		}

		// Other failures: retry with backoff up to 5 attempts
		w.mu.Lock()
		w.attempts[item.ID]++
		attempts := w.attempts[item.ID]
		if attempts >= 5 {
			slog.Error("Exhausted 5 delivery attempts for notification, marking sent to avoid poisoning outbox", "id", item.ID, "error", err)
			_ = w.repo.MarkSent(ctx, item.ID, time.Now().UTC())
			delete(w.attempts, item.ID)
			delete(w.nextRetry, item.ID)
		} else {
			backoff := w.baseBackoff * time.Duration(1<<(attempts-1))
			w.nextRetry[item.ID] = time.Now().UTC().Add(backoff)
			slog.Warn("Notification delivery failed, scheduling retry", "id", item.ID, "attempt", attempts, "backoff", backoff, "error", err)
		}
		w.mu.Unlock()
	}

	return nil
}

// Start begins processing the notifications outbox until context cancellation.
func (w *Worker) Start(ctx context.Context) {
	w.mu.Lock()
	if w.running {
		w.mu.Unlock()
		return
	}
	w.running = true
	w.mu.Unlock()

	ticker := time.NewTicker(w.tickerDur)
	defer ticker.Stop()

	// Initial drain
	_ = w.Drain(ctx)

	for {
		select {
		case <-ctx.Done():
			return
		case <-w.notifyCh:
			_ = w.Drain(ctx)
		case <-ticker.C:
			_ = w.Drain(ctx)
		}
	}
}
