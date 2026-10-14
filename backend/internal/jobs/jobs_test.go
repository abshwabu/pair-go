package jobs_test

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/jobs"
)

func setupTestDB(t *testing.T) *db.DB {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "jobs_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test database: %v", err)
	}
	return database
}

func createPodWithStreak(t *testing.T, database *db.DB, status string, currentStreak, bestStreak int, lastCheckInDate *string) string {
	t.Helper()
	podID := uuid.NewString()
	now := time.Now().UTC().Format(time.RFC3339)

	_, err := database.Write.Exec(`
		INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at)
		VALUES (?, 'read', ?, 2, ?, ?);
	`, podID, status, now, now)
	if err != nil {
		t.Fatalf("failed to insert pod: %v", err)
	}

	streakID := uuid.NewString()
	_, err = database.Write.Exec(`
		INSERT INTO streaks (id, pod_id, current_streak, best_streak, last_check_in_date, updated_at)
		VALUES (?, ?, ?, ?, ?, ?);
	`, streakID, podID, currentStreak, bestStreak, lastCheckInDate, now)
	if err != nil {
		t.Fatalf("failed to insert streak: %v", err)
	}

	return podID
}

func TestResetStaleStreaks(t *testing.T) {
	database := setupTestDB(t)
	notifier := jobs.NewStubNotificationService()

	// As-of date: 2026-10-16 00:05:00 UTC
	// Yesterday: 2026-10-15
	asOf := time.Date(2026, 10, 16, 0, 5, 0, 0, time.UTC)

	// Case 1: Active pod whose last check-in was yesterday (2026-10-15) -> Should NOT be reset!
	yesterday := "2026-10-15"
	podActiveYesterday := createPodWithStreak(t, database, "active", 5, 10, &yesterday)

	// Case 2: Active pod whose last check-in was today (2026-10-16) -> Should NOT be reset!
	today := "2026-10-16"
	podActiveToday := createPodWithStreak(t, database, "active", 3, 3, &today)

	// Case 3: Active pod whose last check-in was 2 days ago (2026-10-14, older than yesterday) -> MUST be reset!
	twoDaysAgo := "2026-10-14"
	podStale := createPodWithStreak(t, database, "active", 7, 12, &twoDaysAgo)

	// Case 4: Dissolved pod with stale streak -> Should NOT be reset (only active pods)
	podDissolved := createPodWithStreak(t, database, "dissolved", 4, 8, &twoDaysAgo)

	// Case 5: Active pod whose streak is already 0 -> Should NOT emit redundant reset
	podAlreadyZero := createPodWithStreak(t, database, "active", 0, 5, &twoDaysAgo)

	// Run ResetStaleStreaks
	resetPodIDs, err := jobs.ResetStaleStreaks(context.Background(), database.Write, database.Read, notifier, asOf)
	if err != nil {
		t.Fatalf("ResetStaleStreaks failed: %v", err)
	}

	// Verify that ONLY podStale was reset
	if len(resetPodIDs) != 1 || resetPodIDs[0] != podStale {
		t.Fatalf("expected only podStale (%s) to be reset, got: %v", podStale, resetPodIDs)
	}

	// Verify notification was emitted for podStale
	brokenEvents := notifier.GetBrokenPodIDs()
	if len(brokenEvents) != 1 || brokenEvents[0] != podStale {
		t.Fatalf("expected streak_broken event for %s, got: %v", podStale, brokenEvents)
	}

	// Check streak table row for podStale: current_streak should be 0, best_streak preserved at 12
	var currentStreak, bestStreak int
	err = database.Read.QueryRow(`
		SELECT current_streak, best_streak
		FROM streaks
		WHERE pod_id = ?;
	`, podStale).Scan(&currentStreak, &bestStreak)
	if err != nil {
		t.Fatalf("failed to query podStale streak: %v", err)
	}
	if currentStreak != 0 {
		t.Errorf("expected current_streak 0, got %d", currentStreak)
	}
	if bestStreak != 12 {
		t.Errorf("expected best_streak preserved at 12, got %d", bestStreak)
	}

	// Check that podActiveYesterday remained at streak 5
	err = database.Read.QueryRow(`SELECT current_streak FROM streaks WHERE pod_id = ?;`, podActiveYesterday).Scan(&currentStreak)
	if err != nil || currentStreak != 5 {
		t.Errorf("podActiveYesterday should have current_streak 5, got %d, err: %v", currentStreak, err)
	}

	// Check that podActiveToday remained at streak 3
	err = database.Read.QueryRow(`SELECT current_streak FROM streaks WHERE pod_id = ?;`, podActiveToday).Scan(&currentStreak)
	if err != nil || currentStreak != 3 {
		t.Errorf("podActiveToday should have current_streak 3, got %d, err: %v", currentStreak, err)
	}

	// Check that podDissolved remained at streak 4
	err = database.Read.QueryRow(`SELECT current_streak FROM streaks WHERE pod_id = ?;`, podDissolved).Scan(&currentStreak)
	if err != nil || currentStreak != 4 {
		t.Errorf("podDissolved should remain at streak 4, got %d, err: %v", currentStreak, err)
	}

	_ = podAlreadyZero
}

func TestScheduler_Registration(t *testing.T) {
	database := setupTestDB(t)
	notifier := jobs.NewStubNotificationService()

	scheduler := jobs.NewScheduler()
	entryID, err := scheduler.RegisterDailyStreakReset(database.Write, database.Read, notifier)
	if err != nil {
		t.Fatalf("failed to register daily streak reset: %v", err)
	}
	if entryID <= 0 {
		t.Fatalf("expected valid entryID > 0, got %d", entryID)
	}

	scheduler.Start()
	scheduler.Stop()
}
