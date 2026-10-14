package checkins_test

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/checkins"
	"github.com/abshwabu/pair/backend/internal/db"
)

func setupTestDB(t *testing.T) *db.DB {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "checkins_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test database: %v", err)
	}
	return database
}

func createTestUser(t *testing.T, database *db.DB, name, email string) string {
	t.Helper()
	now := time.Now().UTC().Format(time.RFC3339)
	userID := uuid.NewString()

	_, err := database.Write.Exec(`
		INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at)
		VALUES (?, ?, ?, 'hash', 'UTC', 'en', 0, ?, ?);
	`, userID, name, email, now, now)
	if err != nil {
		t.Fatalf("failed to insert user: %v", err)
	}
	return userID
}

func createTestPod(t *testing.T, database *db.DB, user1ID, user2ID string) string {
	t.Helper()
	now := time.Now().UTC().Format(time.RFC3339)
	podID := uuid.NewString()

	_, err := database.Write.Exec(`
		INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at)
		VALUES (?, 'read', 'active', 2, ?, ?);
	`, podID, now, now)
	if err != nil {
		t.Fatalf("failed to insert pod: %v", err)
	}

	goal1ID := uuid.NewString()
	_, _ = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, 'read', 'Goal 1', 'Desc 1', 'steady', ?, ?);
	`, goal1ID, user1ID, now, now)

	goal2ID := uuid.NewString()
	_, _ = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, 'read', 'Goal 2', 'Desc 2', 'steady', ?, ?);
	`, goal2ID, user2ID, now, now)

	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?), (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, user1ID, goal1ID, now,
		uuid.NewString(), podID, user2ID, goal2ID, now)
	if err != nil {
		t.Fatalf("failed to insert pod members: %v", err)
	}

	return podID
}

func insertCheckIn(t *testing.T, database *db.DB, podID, userID, date string) {
	t.Helper()
	now := time.Now().UTC().Format(time.RFC3339)
	_, err := database.Write.Exec(`
		INSERT INTO check_ins (id, pod_id, user_id, check_in_date, created_at)
		VALUES (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, userID, date, now)
	if err != nil {
		t.Fatalf("failed to insert check-in: %v", err)
	}
}

// 1. Single check-in does not increment streak
func TestStreakService_SingleCheckInDoesNotIncrement(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	streakService := checkins.NewStreakService(database.Write, database.Read)

	// Alice checks in on 2026-10-14
	insertCheckIn(t, database, podID, u1, "2026-10-14")

	tx, err := database.Write.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatalf("failed to begin tx: %v", err)
	}
	defer tx.Rollback()

	streak, err := streakService.Recalculate(tx, podID, "2026-10-14")
	if err != nil {
		t.Fatalf("recalculate failed: %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("failed to commit: %v", err)
	}

	if streak.CurrentStreak != 0 {
		t.Fatalf("expected current_streak 0 after single member check-in, got %d", streak.CurrentStreak)
	}
	if streak.LastCheckInDate != nil {
		t.Fatalf("expected last_check_in_date nil after single check-in, got %s", *streak.LastCheckInDate)
	}
}

// 2. Both members on the same day increments streak to 1
func TestStreakService_BothMembersOnSameDayIncrementsToOne(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	streakService := checkins.NewStreakService(database.Write, database.Read)

	// Both Alice and Bob check in on 2026-10-14
	insertCheckIn(t, database, podID, u1, "2026-10-14")
	insertCheckIn(t, database, podID, u2, "2026-10-14")

	tx, err := database.Write.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatalf("failed to begin tx: %v", err)
	}
	defer tx.Rollback()

	streak, err := streakService.Recalculate(tx, podID, "2026-10-14")
	if err != nil {
		t.Fatalf("recalculate failed: %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("commit failed: %v", err)
	}

	if streak.CurrentStreak != 1 {
		t.Fatalf("expected current_streak 1, got %d", streak.CurrentStreak)
	}
	if streak.BestStreak != 1 {
		t.Fatalf("expected best_streak 1, got %d", streak.BestStreak)
	}
	if streak.LastCheckInDate == nil || *streak.LastCheckInDate != "2026-10-14" {
		t.Fatalf("expected last_check_in_date 2026-10-14, got %v", streak.LastCheckInDate)
	}
}

// 3. Consecutive days increment further (1 -> 2 -> 3)
func TestStreakService_ConsecutiveDaysIncrementFurther(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	streakService := checkins.NewStreakService(database.Write, database.Read)

	days := []string{"2026-10-14", "2026-10-15", "2026-10-16"}

	for i, day := range days {
		insertCheckIn(t, database, podID, u1, day)
		insertCheckIn(t, database, podID, u2, day)

		tx, err := database.Write.BeginTx(context.Background(), nil)
		if err != nil {
			t.Fatalf("failed to begin tx: %v", err)
		}
		streak, err := streakService.Recalculate(tx, podID, day)
		if err != nil {
			tx.Rollback()
			t.Fatalf("recalculate failed on day %s: %v", day, err)
		}
		if err := tx.Commit(); err != nil {
			t.Fatalf("commit failed on day %s: %v", day, err)
		}

		expectedStreak := i + 1
		if streak.CurrentStreak != expectedStreak {
			t.Fatalf("day %s: expected current_streak %d, got %d", day, expectedStreak, streak.CurrentStreak)
		}
		if streak.BestStreak != expectedStreak {
			t.Fatalf("day %s: expected best_streak %d, got %d", day, expectedStreak, streak.BestStreak)
		}
		if streak.LastCheckInDate == nil || *streak.LastCheckInDate != day {
			t.Fatalf("day %s: expected last_check_in_date %s, got %v", day, day, streak.LastCheckInDate)
		}
	}
}

// 4. Skipped day then both checking in restarts at 1 with best_streak preserved
func TestStreakService_SkippedDayRestartsAtOnePreservesBestStreak(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	streakService := checkins.NewStreakService(database.Write, database.Read)

	// Day 1: 2026-10-14 (both check in)
	insertCheckIn(t, database, podID, u1, "2026-10-14")
	insertCheckIn(t, database, podID, u2, "2026-10-14")
	tx1, _ := database.Write.BeginTx(context.Background(), nil)
	streakService.Recalculate(tx1, podID, "2026-10-14")
	tx1.Commit()

	// Day 2: 2026-10-15 (both check in -> streak 2)
	insertCheckIn(t, database, podID, u1, "2026-10-15")
	insertCheckIn(t, database, podID, u2, "2026-10-15")
	tx2, _ := database.Write.BeginTx(context.Background(), nil)
	s2, _ := streakService.Recalculate(tx2, podID, "2026-10-15")
	tx2.Commit()
	if s2.CurrentStreak != 2 || s2.BestStreak != 2 {
		t.Fatalf("expected current 2, best 2; got current %d, best %d", s2.CurrentStreak, s2.BestStreak)
	}

	// Day 3 (2026-10-16): SKIPPED! Neither checks in.

	// Day 4 (2026-10-17): Both check in!
	insertCheckIn(t, database, podID, u1, "2026-10-17")
	insertCheckIn(t, database, podID, u2, "2026-10-17")
	tx4, _ := database.Write.BeginTx(context.Background(), nil)
	s4, err := streakService.Recalculate(tx4, podID, "2026-10-17")
	if err != nil {
		t.Fatalf("recalculate failed: %v", err)
	}
	tx4.Commit()

	// Current streak should restart at 1, best streak should remain 2!
	if s4.CurrentStreak != 1 {
		t.Fatalf("expected current_streak to restart at 1 after skipped day, got %d", s4.CurrentStreak)
	}
	if s4.BestStreak != 2 {
		t.Fatalf("expected best_streak to be preserved at 2, got %d", s4.BestStreak)
	}
	if s4.LastCheckInDate == nil || *s4.LastCheckInDate != "2026-10-17" {
		t.Fatalf("expected last_check_in_date 2026-10-17, got %v", s4.LastCheckInDate)
	}
}

// 5. Duplicate check-in same day returns ErrAlreadyCheckedIn
func TestStreakService_DuplicateCheckInSameDayReturns409(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	repo := checkins.NewRepository(database.Write, database.Read)
	streakService := checkins.NewStreakService(database.Write, database.Read)

	note := "Feeling great!"
	checkIn1, streak1, both1, err := repo.RecordCheckIn(context.Background(), podID, u1, &note, streakService)
	if err != nil {
		t.Fatalf("first check-in failed: %v", err)
	}
	if checkIn1 == nil || streak1 == nil {
		t.Fatalf("expected non-nil check-in and streak")
	}
	if both1 {
		t.Fatalf("expected bothCheckedIn false for single member")
	}

	// Attempting a second check-in on the same day for u1 must return ErrAlreadyCheckedIn
	_, _, _, err = repo.RecordCheckIn(context.Background(), podID, u1, &note, streakService)
	if err == nil {
		t.Fatalf("expected duplicate check-in to error, got nil")
	}
	if !errors.Is(err, checkins.ErrAlreadyCheckedIn) {
		t.Fatalf("expected ErrAlreadyCheckedIn, got %v", err)
	}

	// Alice cannot check in again, but Bob CAN check in today!
	note2 := "Bob checking in"
	checkIn2, streak2, both2, err := repo.RecordCheckIn(context.Background(), podID, u2, &note2, streakService)
	if err != nil {
		t.Fatalf("partner check-in failed: %v", err)
	}
	if !both2 {
		t.Fatalf("expected bothCheckedIn true after second member checked in")
	}
	if streak2.CurrentStreak != 1 {
		t.Fatalf("expected current_streak 1, got %d", streak2.CurrentStreak)
	}
	if checkIn2.Note == nil || *checkIn2.Note != note2 {
		t.Fatalf("expected note %q, got %v", note2, checkIn2.Note)
	}
}

// 6. Idempotency on repeated recalculate calls for the same date
func TestStreakService_IdempotencySameDay(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	streakService := checkins.NewStreakService(database.Write, database.Read)

	insertCheckIn(t, database, podID, u1, "2026-10-14")
	insertCheckIn(t, database, podID, u2, "2026-10-14")

	// Call Recalculate twice for the same date
	tx1, _ := database.Write.BeginTx(context.Background(), nil)
	s1, err := streakService.Recalculate(tx1, podID, "2026-10-14")
	if err != nil {
		t.Fatalf("first recalculate failed: %v", err)
	}
	tx1.Commit()

	tx2, _ := database.Write.BeginTx(context.Background(), nil)
	s2, err := streakService.Recalculate(tx2, podID, "2026-10-14")
	if err != nil {
		t.Fatalf("second recalculate failed: %v", err)
	}
	tx2.Commit()

	if s1.CurrentStreak != 1 || s2.CurrentStreak != 1 {
		t.Fatalf("expected current_streak 1 on both calls, got s1=%d, s2=%d", s1.CurrentStreak, s2.CurrentStreak)
	}
}

// 7. Test ListPodCheckInsByDate
func TestRepository_ListPodCheckInsByDate(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	repo := checkins.NewRepository(database.Write, database.Read)

	insertCheckIn(t, database, podID, u1, "2026-10-12")
	insertCheckIn(t, database, podID, u1, "2026-10-13")
	insertCheckIn(t, database, podID, u2, "2026-10-13")

	items, err := repo.ListPodCheckInsByDate(context.Background(), podID, 60)
	if err != nil {
		t.Fatalf("failed to list check-ins: %v", err)
	}

	if len(items) != 2 {
		t.Fatalf("expected 2 distinct date items, got %d", len(items))
	}

	// Most recent first: 2026-10-13, then 2026-10-12
	if items[0].Date != "2026-10-13" {
		t.Fatalf("expected first item date 2026-10-13, got %s", items[0].Date)
	}
	if !items[0].BothCheckedIn || len(items[0].MemberIDs) != 2 {
		t.Fatalf("expected bothCheckedIn true with 2 members for 2026-10-13, got both=%v, len=%d", items[0].BothCheckedIn, len(items[0].MemberIDs))
	}

	if items[1].Date != "2026-10-12" {
		t.Fatalf("expected second item date 2026-10-12, got %s", items[1].Date)
	}
	if items[1].BothCheckedIn || len(items[1].MemberIDs) != 1 {
		t.Fatalf("expected bothCheckedIn false with 1 member for 2026-10-12, got both=%v, len=%d", items[1].BothCheckedIn, len(items[1].MemberIDs))
	}
}

// 8. Test GetPodStreakDetails
func TestRepository_GetPodStreakDetails(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	repo := checkins.NewRepository(database.Write, database.Read)
	streakService := checkins.NewStreakService(database.Write, database.Read)

	// Alice checks in today
	note := "Doing my part"
	_, _, _, err := repo.RecordCheckIn(context.Background(), podID, u1, &note, streakService)
	if err != nil {
		t.Fatalf("Alice check-in failed: %v", err)
	}

	details, err := repo.GetPodStreakDetails(context.Background(), podID, u1)
	if err != nil {
		t.Fatalf("GetPodStreakDetails failed: %v", err)
	}

	if !details.MeCheckedInToday {
		t.Fatalf("expected MeCheckedInToday true")
	}
	if details.PartnerCheckedInToday {
		t.Fatalf("expected PartnerCheckedInToday false")
	}
	if details.BothCheckedInToday {
		t.Fatalf("expected BothCheckedInToday false")
	}
	if details.CurrentStreak != 0 {
		t.Fatalf("expected CurrentStreak 0 before partner checks in, got %d", details.CurrentStreak)
	}

	// Now Bob views the streak
	bobDetails, err := repo.GetPodStreakDetails(context.Background(), podID, u2)
	if err != nil {
		t.Fatalf("Bob GetPodStreakDetails failed: %v", err)
	}
	if bobDetails.MeCheckedInToday {
		t.Fatalf("expected Bob MeCheckedInToday false")
	}
	if !bobDetails.PartnerCheckedInToday {
		t.Fatalf("expected Bob PartnerCheckedInToday true")
	}
}
