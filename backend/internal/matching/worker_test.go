package matching_test

import (
	"context"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/matching"
)

func setupTestDB(t *testing.T) *db.DB {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "matching_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test database: %v", err)
	}
	return database
}

func createTestUserAndGoal(t *testing.T, database *db.DB, email, timezone, language, category, pace string) (string, string) {
	t.Helper()
	now := time.Now().UTC().Format(time.RFC3339)
	userID := uuid.NewString()

	_, err := database.Write.Exec(`
		INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at)
		VALUES (?, 'Test User', ?, 'hash', ?, ?, 0, ?, ?);
	`, userID, email, timezone, language, now, now)
	if err != nil {
		t.Fatalf("failed to insert user: %v", err)
	}

	goalID := uuid.NewString()
	_, err = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, ?, 'Test Goal', 'Description', ?, ?, ?);
	`, goalID, userID, category, pace, now, now)
	if err != nil {
		t.Fatalf("failed to insert goal: %v", err)
	}

	return userID, goalID
}

func TestWorker_RacingWorkersProduceExactlyOnePod(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := matching.NewRepository(database.Write, database.Read)

	// Create 2 compatible users and goals
	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@pair.test", "UTC", "en", "read", "steady")

	// Insert 2 open pod requests
	now := time.Now().UTC()
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	if err := repo.Create(context.Background(), req1); err != nil {
		t.Fatalf("failed to create req1: %v", err)
	}
	if err := repo.Create(context.Background(), req2); err != nil {
		t.Fatalf("failed to create req2: %v", err)
	}

	// Create 2 separate workers simulating distributed/concurrent processing
	worker1 := matching.NewWorker(repo)
	worker2 := matching.NewWorker(repo)

	var wg sync.WaitGroup
	ctx := context.Background()

	// Launch concurrent processing for both requests across both workers
	wg.Add(4)
	go func() {
		defer wg.Done()
		_ = worker1.ProcessRequest(ctx, req1.ID)
	}()
	go func() {
		defer wg.Done()
		_ = worker2.ProcessRequest(ctx, req1.ID)
	}()
	go func() {
		defer wg.Done()
		_ = worker1.ProcessRequest(ctx, req2.ID)
	}()
	go func() {
		defer wg.Done()
		_ = worker2.ProcessRequest(ctx, req2.ID)
	}()

	wg.Wait()

	// Verify that exactly ONE pod was created
	var podCount int
	err := database.Read.QueryRow(`SELECT COUNT(*) FROM pods`).Scan(&podCount)
	if err != nil {
		t.Fatalf("failed to count pods: %v", err)
	}
	if podCount != 1 {
		t.Fatalf("expected exactly 1 pod to be created, got %d", podCount)
	}

	// Verify pod attributes
	var podID, podStatus, goalCat string
	var capacity int
	err = database.Read.QueryRow(`SELECT id, status, capacity, goal_category FROM pods`).Scan(&podID, &podStatus, &capacity, &goalCat)
	if err != nil {
		t.Fatalf("failed to get pod: %v", err)
	}
	if podStatus != "active" {
		t.Errorf("expected pod status 'active', got %s", podStatus)
	}
	if capacity != 2 {
		t.Errorf("expected pod capacity 2, got %d", capacity)
	}
	if goalCat != "read" {
		t.Errorf("expected goal category 'read', got %s", goalCat)
	}

	// Verify exactly 2 pod_members records
	var memberCount int
	err = database.Read.QueryRow(`SELECT COUNT(*) FROM pod_members WHERE pod_id = ?`, podID).Scan(&memberCount)
	if err != nil {
		t.Fatalf("failed to count pod members: %v", err)
	}
	if memberCount != 2 {
		t.Errorf("expected exactly 2 pod members, got %d", memberCount)
	}

	// Verify streaks row initialized to 0
	var streakCount, currentStreak, bestStreak int
	err = database.Read.QueryRow(`SELECT COUNT(*), current_streak, best_streak FROM streaks WHERE pod_id = ?`, podID).
		Scan(&streakCount, &currentStreak, &bestStreak)
	if err != nil {
		t.Fatalf("failed to check streaks: %v", err)
	}
	if streakCount != 1 {
		t.Errorf("expected 1 streak record, got %d", streakCount)
	}
	if currentStreak != 0 || bestStreak != 0 {
		t.Errorf("expected zero streaks, got current=%d, best=%d", currentStreak, bestStreak)
	}

	// Verify both requests are now matched with pod_id
	pReq1, err := repo.GetByID(ctx, req1.ID)
	if err != nil {
		t.Fatalf("failed to get req1: %v", err)
	}
	if pReq1.Status != matching.PodRequestStatusMatched || pReq1.PodID == nil || *pReq1.PodID != podID {
		t.Errorf("expected req1 to be matched to pod %s, got status=%s pod_id=%v", podID, pReq1.Status, pReq1.PodID)
	}

	pReq2, err := repo.GetByID(ctx, req2.ID)
	if err != nil {
		t.Fatalf("failed to get req2: %v", err)
	}
	if pReq2.Status != matching.PodRequestStatusMatched || pReq2.PodID == nil || *pReq2.PodID != podID {
		t.Errorf("expected req2 to be matched to pod %s, got status=%s pod_id=%v", podID, pReq2.Status, pReq2.PodID)
	}
}

func TestWorker_SweepRetriesOlderRequests(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := matching.NewRepository(database.Write, database.Read)

	// Create 2 users and goals
	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@sweep.test", "UTC", "en", "fitness", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@sweep.test", "UTC", "en", "fitness", "steady")

	// Insert requests created 5 minutes ago (> 2 minutes old threshold)
	pastTime := time.Now().UTC().Add(-5 * time.Minute)
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              pastTime,
		UpdatedAt:              pastTime,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              pastTime,
		UpdatedAt:              pastTime,
	}

	if err := repo.Create(context.Background(), req1); err != nil {
		t.Fatalf("failed to create req1: %v", err)
	}
	if err := repo.Create(context.Background(), req2); err != nil {
		t.Fatalf("failed to create req2: %v", err)
	}

	// Create worker configured with 2m olderThan threshold
	worker := matching.NewWorker(repo, matching.WithOlderThan(2*time.Minute))

	// Execute sweep
	ctx := context.Background()
	if err := worker.Sweep(ctx); err != nil {
		t.Fatalf("sweep failed: %v", err)
	}

	// Verify both requests were picked up by the sweep and matched!
	pReq1, err := repo.GetByID(ctx, req1.ID)
	if err != nil {
		t.Fatalf("failed to get req1: %v", err)
	}
	if pReq1.Status != matching.PodRequestStatusMatched {
		t.Errorf("expected req1 to be matched by sweep, got %s", pReq1.Status)
	}

	pReq2, err := repo.GetByID(ctx, req2.ID)
	if err != nil {
		t.Fatalf("failed to get req2: %v", err)
	}
	if pReq2.Status != matching.PodRequestStatusMatched {
		t.Errorf("expected req2 to be matched by sweep, got %s", pReq2.Status)
	}
}

func TestWorker_BlockedPairsAreNeverMatched(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := matching.NewRepository(database.Write, database.Read)

	// Create 2 otherwise perfectly compatible users and goals
	user1ID, goal1ID := createTestUserAndGoal(t, database, "blocked1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "blocked2@pair.test", "UTC", "en", "read", "steady")

	// Insert a block: user1 blocked user2
	now := time.Now().UTC().Format(time.RFC3339)
	_, err := database.Write.Exec(`
		INSERT INTO blocks (id, user_id, blocked_user_id, created_at)
		VALUES (?, ?, ?, ?);
	`, uuid.NewString(), user1ID, user2ID, now)
	if err != nil {
		t.Fatalf("failed to insert block: %v", err)
	}

	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              time.Now().UTC(),
		UpdatedAt:              time.Now().UTC(),
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              time.Now().UTC(),
		UpdatedAt:              time.Now().UTC(),
	}

	if err := repo.Create(context.Background(), req1); err != nil {
		t.Fatalf("failed to create req1: %v", err)
	}
	if err := repo.Create(context.Background(), req2); err != nil {
		t.Fatalf("failed to create req2: %v", err)
	}

	worker := matching.NewWorker(repo)
	ctx := context.Background()

	// Attempt to process match for req1
	if err := worker.ProcessRequest(ctx, req1.ID); err != nil {
		t.Fatalf("worker.ProcessRequest failed: %v", err)
	}

	// Verify both requests remain open
	pReq1, err := repo.GetByID(ctx, req1.ID)
	if err != nil || pReq1.Status != matching.PodRequestStatusOpen {
		t.Fatalf("expected req1 to remain open, got status: %v", pReq1.Status)
	}
	pReq2, err := repo.GetByID(ctx, req2.ID)
	if err != nil || pReq2.Status != matching.PodRequestStatusOpen {
		t.Fatalf("expected req2 to remain open, got status: %v", pReq2.Status)
	}
}
