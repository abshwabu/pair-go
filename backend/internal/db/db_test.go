package db_test

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/goals"
	"github.com/abshwabu/pair/backend/internal/pods"
	"github.com/abshwabu/pair/backend/internal/users"
)

func TestOpenAndMigrations(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "test_pair.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("db.Open failed: %v", err)
	}
	defer database.Close()

	// Verify PRAGMAs
	var journalMode string
	if err := database.Write.QueryRow("PRAGMA journal_mode;").Scan(&journalMode); err != nil {
		t.Fatalf("failed to query journal_mode: %v", err)
	}
	if journalMode != "wal" {
		t.Errorf("expected journal_mode wal, got %s", journalMode)
	}

	var foreignKeys int
	if err := database.Write.QueryRow("PRAGMA foreign_keys;").Scan(&foreignKeys); err != nil {
		t.Fatalf("failed to query foreign_keys: %v", err)
	}
	if foreignKeys != 1 {
		t.Errorf("expected foreign_keys 1, got %d", foreignKeys)
	}

	var busyTimeout int
	if err := database.Write.QueryRow("PRAGMA busy_timeout;").Scan(&busyTimeout); err != nil {
		t.Fatalf("failed to query busy_timeout: %v", err)
	}
	if busyTimeout != 5000 {
		t.Errorf("expected busy_timeout 5000, got %d", busyTimeout)
	}

	// Verify all 13 tables exist
	expectedTables := []string{
		"users",
		"auth_tokens",
		"goals",
		"pods",
		"pod_requests",
		"pod_members",
		"todos",
		"messages",
		"check_ins",
		"streaks",
		"reports",
		"blocks",
		"notifications",
		"match_proposals",
	}

	for _, tbl := range expectedTables {
		var count int
		query := "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?;"
		if err := database.Read.QueryRow(query, tbl).Scan(&count); err != nil {
			t.Fatalf("failed to check table %s: %v", tbl, err)
		}
		if count != 1 {
			t.Errorf("expected table %s to exist, got count %d", tbl, count)
		}
	}

	// Verify goose down reverses all migrations cleanly
	if err := db.RollbackAll(database.Write); err != nil {
		t.Fatalf("db.RollbackAll failed: %v", err)
	}

	// Verify tables are gone after rollback
	for _, tbl := range expectedTables {
		var count int
		query := "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?;"
		if err := database.Read.QueryRow(query, tbl).Scan(&count); err != nil {
			t.Fatalf("failed to check table %s after rollback: %v", tbl, err)
		}
		if count != 0 {
			t.Errorf("expected table %s to be dropped after rollback, got count %d", tbl, count)
		}
	}

	// Re-apply migrations for subsequent tests
	if err := db.RunMigrations(database.Write); err != nil {
		t.Fatalf("re-applying db.RunMigrations failed: %v", err)
	}
}

func TestDomainRepositoriesAndForeignKeys(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "test_pair_fk.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("db.Open failed: %v", err)
	}
	defer database.Close()

	ctx := context.Background()

	usersRepo := users.NewRepository(database.Write, database.Read)
	goalsRepo := goals.NewRepository(database.Write, database.Read)
	podsRepo := pods.NewRepository(database.Write, database.Read)

	now := time.Now().UTC().Truncate(time.Second)

	// 1. Insert a user
	userID := uuid.NewString()
	user := &users.User{
		ID:           userID,
		Name:         "Alice Tester",
		Email:        "alice@example.com",
		PasswordHash: "$2a$10$dummyhashedpasswordstring",
		Timezone:     "America/New_York",
		Language:     "en",
		IsAdmin:      false,
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	if err := usersRepo.Create(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	fetchedUser, err := usersRepo.GetByID(ctx, userID)
	if err != nil {
		t.Fatalf("failed to get user: %v", err)
	}
	if fetchedUser.Email != user.Email {
		t.Errorf("expected user email %s, got %s", user.Email, fetchedUser.Email)
	}

	// 2. Insert a goal referencing the user
	goalID := uuid.NewString()
	goal := &goals.Goal{
		ID:                goalID,
		UserID:            userID,
		Category:          goals.GoalCategoryRead,
		Title:             "Read 12 books",
		TargetDescription: "Read 1 book per month",
		Pace:              goals.GoalPaceSteady,
		CreatedAt:         now,
		UpdatedAt:         now,
	}
	if err := goalsRepo.Create(ctx, goal); err != nil {
		t.Fatalf("failed to create goal: %v", err)
	}

	fetchedGoal, err := goalsRepo.GetByID(ctx, goalID)
	if err != nil {
		t.Fatalf("failed to get goal: %v", err)
	}
	if fetchedGoal.Title != goal.Title {
		t.Errorf("expected goal title %s, got %s", goal.Title, fetchedGoal.Title)
	}

	// 3. Insert a pod
	podID := uuid.NewString()
	pod := &pods.Pod{
		ID:           podID,
		GoalCategory: "read",
		Status:       pods.PodStatusActive,
		Capacity:     2,
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	if err := podsRepo.Create(ctx, pod); err != nil {
		t.Fatalf("failed to create pod: %v", err)
	}

	fetchedPod, err := podsRepo.GetByID(ctx, podID)
	if err != nil {
		t.Fatalf("failed to get pod: %v", err)
	}
	if fetchedPod.Status != pods.PodStatusActive {
		t.Errorf("expected pod status active, got %s", fetchedPod.Status)
	}

	// 4. Insert a pod member referencing the pod, user, and goal
	memberID := uuid.NewString()
	member := &pods.PodMember{
		ID:       memberID,
		PodID:    podID,
		UserID:   userID,
		GoalID:   goalID,
		JoinedAt: now,
	}
	if err := podsRepo.CreateMember(ctx, member); err != nil {
		t.Fatalf("failed to create pod member: %v", err)
	}

	fetchedMember, err := podsRepo.GetMemberByID(ctx, memberID)
	if err != nil {
		t.Fatalf("failed to get pod member: %v", err)
	}
	if fetchedMember.UserID != userID || fetchedMember.PodID != podID {
		t.Errorf("expected member for user %s and pod %s, got %+v", userID, podID, fetchedMember)
	}

	// 5. Test foreign key enforcement: inserting pod_member with bad pod_id must fail
	badMember := &pods.PodMember{
		ID:       uuid.NewString(),
		PodID:    "non-existent-pod-uuid",
		UserID:   userID,
		GoalID:   goalID,
		JoinedAt: now,
	}
	err = podsRepo.CreateMember(ctx, badMember)
	if err == nil {
		t.Fatalf("expected foreign key constraint violation when inserting pod_member with bad pod_id, got nil")
	}
	if !strings.Contains(err.Error(), "FOREIGN KEY") && !strings.Contains(strings.ToLower(err.Error()), "foreign key") {
		t.Errorf("expected foreign key error message, got: %v", err)
	}

	// 6. Test foreign key enforcement: inserting pod_member with bad user_id must fail
	badUserMember := &pods.PodMember{
		ID:       uuid.NewString(),
		PodID:    podID,
		UserID:   "non-existent-user-uuid",
		GoalID:   goalID,
		JoinedAt: now,
	}
	err = podsRepo.CreateMember(ctx, badUserMember)
	if err == nil {
		t.Fatalf("expected foreign key constraint violation when inserting pod_member with bad user_id, got nil")
	}
}
