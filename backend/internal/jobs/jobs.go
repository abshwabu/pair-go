package jobs

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/robfig/cron/v3"
)

// NotificationService defines methods for sending event-driven notifications.
type NotificationService interface {
	EmitStreakBroken(ctx context.Context, podID string) error
}

// StubNotificationService is a thread-safe in-memory stub for NotificationService.
type StubNotificationService struct {
	mu           sync.Mutex
	BrokenPodIDs []string
}

// NewStubNotificationService creates a new StubNotificationService.
func NewStubNotificationService() *StubNotificationService {
	return &StubNotificationService{
		BrokenPodIDs: make([]string, 0),
	}
}

// EmitStreakBroken records the streak_broken event.
func (s *StubNotificationService) EmitStreakBroken(ctx context.Context, podID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.BrokenPodIDs = append(s.BrokenPodIDs, podID)
	slog.Info("Notification: streak_broken event emitted", "pod_id", podID)
	return nil
}

// GetBrokenPodIDs returns a copy of broken pod IDs emitted.
func (s *StubNotificationService) GetBrokenPodIDs() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	copied := make([]string, len(s.BrokenPodIDs))
	copy(copied, s.BrokenPodIDs)
	return copied
}

// Scheduler manages scheduled cron jobs for streaks, check-in reminders, etc.
type Scheduler struct {
	cron *cron.Cron
}

// NewScheduler creates and configures a cron job scheduler in UTC.
// Supports both standard 5-field ("5 0 * * *") and 6-field ("0 5 0 * * *") expressions.
func NewScheduler() *Scheduler {
	c := cron.New(
		cron.WithLocation(time.UTC),
		cron.WithParser(cron.NewParser(
			cron.SecondOptional|cron.Minute|cron.Hour|cron.Dom|cron.Month|cron.Dow|cron.Descriptor,
		)),
	)
	return &Scheduler{cron: c}
}

// Start begins the cron scheduler in the background.
func (s *Scheduler) Start() {
	s.cron.Start()
	slog.Info("Cron job scheduler started")
}

// Stop stops the cron scheduler.
func (s *Scheduler) Stop() {
	ctx := s.cron.Stop()
	<-ctx.Done()
	slog.Info("Cron job scheduler stopped")
}

// ResetStaleStreaks finds all active pods whose streak is active (current_streak > 0)
// but whose last_check_in_date is older than yesterday relative to asOf (UTC).
// For each pod, it resets current_streak to 0 (preserving best_streak) and emits a streak_broken event.
func ResetStaleStreaks(ctx context.Context, writeDB, readDB *sql.DB, notifier NotificationService, asOf time.Time) ([]string, error) {
	asOfUTC := asOf.UTC()
	yesterdayStr := asOfUTC.AddDate(0, 0, -1).Format("2006-01-02")
	updatedAtStr := asOfUTC.Format(time.RFC3339)

	// Query active pods whose current_streak > 0 and last_check_in_date < yesterdayStr (or NULL)
	query := `
		SELECT s.pod_id
		FROM streaks s
		JOIN pods p ON s.pod_id = p.id
		WHERE p.status = 'active'
		  AND s.current_streak > 0
		  AND (s.last_check_in_date IS NULL OR s.last_check_in_date < ?);
	`

	rows, err := readDB.QueryContext(ctx, query, yesterdayStr)
	if err != nil {
		return nil, fmt.Errorf("failed to query stale streaks: %w", err)
	}
	defer rows.Close()

	var stalePodIDs []string
	for rows.Next() {
		var podID string
		if err := rows.Scan(&podID); err != nil {
			return nil, fmt.Errorf("failed to scan stale pod id: %w", err)
		}
		stalePodIDs = append(stalePodIDs, podID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows error while querying stale streaks: %w", err)
	}

	if len(stalePodIDs) == 0 {
		return nil, nil
	}

	tx, err := writeDB.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	updateQuery := `
		UPDATE streaks
		SET current_streak = 0, updated_at = ?
		WHERE pod_id = ?;
	`
	stmt, err := tx.PrepareContext(ctx, updateQuery)
	if err != nil {
		return nil, fmt.Errorf("failed to prepare update statement: %w", err)
	}
	defer stmt.Close()

	for _, podID := range stalePodIDs {
		if _, err := stmt.ExecContext(ctx, updatedAtStr, podID); err != nil {
			return nil, fmt.Errorf("failed to reset streak for pod %s: %w", podID, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("failed to commit streak resets: %w", err)
	}

	// Emit streak_broken event for each affected pod
	if notifier != nil {
		for _, podID := range stalePodIDs {
			if err := notifier.EmitStreakBroken(ctx, podID); err != nil {
				slog.Error("Failed to emit streak_broken event", "pod_id", podID, "error", err)
			}
		}
	}

	return stalePodIDs, nil
}

// RegisterDailyStreakReset registers a daily cron job at 00:05 UTC that resets stale streaks.
func (s *Scheduler) RegisterDailyStreakReset(writeDB, readDB *sql.DB, notifier NotificationService) (cron.EntryID, error) {
	return s.cron.AddFunc("5 0 * * *", func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		resetPods, err := ResetStaleStreaks(ctx, writeDB, readDB, notifier, time.Now().UTC())
		if err != nil {
			slog.Error("Daily streak reset job failed", "error", err)
			return
		}
		if len(resetPods) > 0 {
			slog.Info("Daily streak reset job completed", "reset_pods_count", len(resetPods), "reset_pods", resetPods)
		}
	})
}
