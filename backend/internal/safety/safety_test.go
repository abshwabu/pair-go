package safety_test

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/chat"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/pods"
	"github.com/abshwabu/pair/backend/internal/safety"
)

func setupTestDB(t *testing.T) *db.DB {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "safety_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test database: %v", err)
	}
	return database
}

func createTestUser(t *testing.T, database *db.DB, name, email string, isAdmin bool) string {
	t.Helper()
	now := time.Now().UTC().Format(time.RFC3339)
	userID := uuid.NewString()

	isAdminInt := 0
	if isAdmin {
		isAdminInt = 1
	}

	_, err := database.Write.Exec(`
		INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at)
		VALUES (?, ?, ?, 'hash', 'UTC', 'en', ?, ?, ?);
	`, userID, name, email, isAdminInt, now, now)
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

func TestSafety_CreateReport(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com", false)
	u2 := createTestUser(t, database, "Bob", "bob@example.com", false)
	podID := createTestPod(t, database, u1, u2)

	repo := safety.NewRepository(database.Write, database.Read)

	// Create valid report
	rep := &safety.Report{
		ID:             uuid.NewString(),
		ReporterID:     u1,
		ReportedUserID: u2,
		PodID:          &podID,
		Reason:         "Harassing messages in chat",
		Status:         safety.ReportStatusOpen,
		CreatedAt:      time.Now().UTC(),
	}

	if err := repo.CreateReport(context.Background(), rep); err != nil {
		t.Fatalf("failed to create report: %v", err)
	}

	fetched, err := repo.GetReportByID(context.Background(), rep.ID)
	if err != nil {
		t.Fatalf("failed to get report: %v", err)
	}
	if fetched.Status != safety.ReportStatusOpen {
		t.Errorf("expected status 'open', got %s", fetched.Status)
	}
	if fetched.Reason != rep.Reason {
		t.Errorf("expected reason %q, got %q", rep.Reason, fetched.Reason)
	}
}

func TestSafety_ListAndUpdateReports(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com", false)
	u2 := createTestUser(t, database, "Bob", "bob@example.com", false)

	repo := safety.NewRepository(database.Write, database.Read)

	rep := &safety.Report{
		ID:             uuid.NewString(),
		ReporterID:     u1,
		ReportedUserID: u2,
		Reason:         "Inappropriate profile picture",
		Status:         safety.ReportStatusOpen,
		CreatedAt:      time.Now().UTC(),
	}
	_ = repo.CreateReport(context.Background(), rep)

	// List reports with 'open' status filter
	status := safety.ReportStatusOpen
	list, err := repo.ListReports(context.Background(), &status)
	if err != nil {
		t.Fatalf("failed to list reports: %v", err)
	}
	if len(list) != 1 {
		t.Fatalf("expected 1 open report, got %d", len(list))
	}
	if list[0].Reporter.Name != "Alice" || list[0].ReportedUser.Name != "Bob" {
		t.Errorf("expected Alice reporting Bob, got %s reporting %s", list[0].Reporter.Name, list[0].ReportedUser.Name)
	}

	// Update report status to 'reviewed'
	updated, err := repo.UpdateReportStatus(context.Background(), rep.ID, safety.ReportStatusReviewed)
	if err != nil {
		t.Fatalf("failed to update report status: %v", err)
	}
	if updated.Status != safety.ReportStatusReviewed {
		t.Errorf("expected status 'reviewed', got %s", updated.Status)
	}

	// Invalid status update returns error
	_, err = repo.UpdateReportStatus(context.Background(), rep.ID, safety.ReportStatus("invalid"))
	if !errors.Is(err, safety.ErrInvalidStatus) {
		t.Errorf("expected ErrInvalidStatus, got %v", err)
	}
}

func TestSafety_BlockingDissolvesSharedPod(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com", false)
	u2 := createTestUser(t, database, "Bob", "bob@example.com", false)
	podID := createTestPod(t, database, u1, u2)

	safetyRepo := safety.NewRepository(database.Write, database.Read)
	podsRepo := pods.NewRepository(database.Write, database.Read)
	chatHub := chat.NewHub()

	// Alice blocks Bob
	block, dissolvedPods, err := safetyRepo.CreateBlock(context.Background(), u1, u2, podsRepo, chatHub)
	if err != nil {
		t.Fatalf("CreateBlock failed: %v", err)
	}
	if block == nil {
		t.Fatalf("expected non-nil block")
	}

	// Verify shared pod was identified and dissolved
	if len(dissolvedPods) != 1 || dissolvedPods[0] != podID {
		t.Fatalf("expected dissolved pod [%s], got %v", podID, dissolvedPods)
	}

	// Verify pod status is dissolved in database
	pod, err := podsRepo.GetByID(context.Background(), podID)
	if err != nil {
		t.Fatalf("failed to get pod: %v", err)
	}
	if pod.Status != pods.PodStatusDissolved {
		t.Fatalf("expected pod status 'dissolved', got %s", pod.Status)
	}

	// Duplicate block returns ErrDuplicateBlock (409 Conflict)
	_, _, err = safetyRepo.CreateBlock(context.Background(), u1, u2, podsRepo, chatHub)
	if !errors.Is(err, safety.ErrDuplicateBlock) {
		t.Fatalf("expected ErrDuplicateBlock on duplicate block, got %v", err)
	}

	// Cannot block yourself
	_, _, err = safetyRepo.CreateBlock(context.Background(), u1, u1, podsRepo, chatHub)
	if !errors.Is(err, safety.ErrSelfBlock) {
		t.Fatalf("expected ErrSelfBlock, got %v", err)
	}
}

func TestSafety_ListAndDeleteBlock(t *testing.T) {
	database := setupTestDB(t)
	u1 := createTestUser(t, database, "Alice", "alice@example.com", false)
	u2 := createTestUser(t, database, "Bob", "bob@example.com", false)
	u3 := createTestUser(t, database, "Charlie", "charlie@example.com", false)

	safetyRepo := safety.NewRepository(database.Write, database.Read)

	block, _, err := safetyRepo.CreateBlock(context.Background(), u1, u2, nil, nil)
	if err != nil {
		t.Fatalf("failed to create block: %v", err)
	}

	// Alice lists her blocks
	blocks, err := safetyRepo.ListBlocks(context.Background(), u1)
	if err != nil {
		t.Fatalf("failed to list blocks: %v", err)
	}
	if len(blocks) != 1 {
		t.Fatalf("expected 1 block, got %d", len(blocks))
	}
	if blocks[0].BlockedUserID != u2 || blocks[0].Name != "Bob" {
		t.Errorf("expected blocked user Bob (%s), got %s (%s)", u2, blocks[0].BlockedUserID, blocks[0].Name)
	}

	// Non-owner (Charlie) attempting to unblock Alice's block -> ErrForbidden (403)
	err = safetyRepo.DeleteBlock(context.Background(), block.ID, u3)
	if !errors.Is(err, safety.ErrForbidden) {
		t.Fatalf("expected ErrForbidden for non-owner, got %v", err)
	}

	// Owner (Alice) unblocks -> success
	err = safetyRepo.DeleteBlock(context.Background(), block.ID, u1)
	if err != nil {
		t.Fatalf("owner unblock failed: %v", err)
	}

	// Verify block was removed
	blocksAfter, err := safetyRepo.ListBlocks(context.Background(), u1)
	if err != nil || len(blocksAfter) != 0 {
		t.Fatalf("expected 0 blocks after deletion, got %d", len(blocksAfter))
	}
}
