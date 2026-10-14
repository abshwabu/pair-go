package chat_test

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/chat"
	"github.com/abshwabu/pair/backend/internal/db"
)

func setupTestDB(t *testing.T) *db.DB {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "chat_test.db")

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
		VALUES (?, ?, 'read', 'Goal 1', 'Desc', 'steady', ?, ?);
	`, goal1ID, user1ID, now, now)

	goal2ID := uuid.NewString()
	_, _ = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, 'read', 'Goal 2', 'Desc', 'steady', ?, ?);
	`, goal2ID, user2ID, now, now)

	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, user1ID, goal1ID, now)
	if err != nil {
		t.Fatalf("failed to insert member 1: %v", err)
	}

	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, user2ID, goal2ID, now)
	if err != nil {
		t.Fatalf("failed to insert member 2: %v", err)
	}

	return podID
}

func TestHub_PresenceAndIsViewing(t *testing.T) {
	hub := chat.NewHub()
	podID := uuid.NewString()
	user1 := uuid.NewString()
	user2 := uuid.NewString()

	if hub.IsViewing(podID, user1) {
		t.Errorf("expected user1 not to be viewing before registering")
	}

	// Register fake client for user1
	client1 := chat.NewClient(hub, nil, podID, user1)
	hub.Register(client1)

	if !hub.IsViewing(podID, user1) {
		t.Errorf("expected user1 to be viewing after registering")
	}
	if hub.IsViewing(podID, user2) {
		t.Errorf("expected user2 not to be viewing")
	}

	// Second client for same user (e.g. mobile + web)
	client1b := chat.NewClient(hub, nil, podID, user1)
	hub.Register(client1b)
	if !hub.IsViewing(podID, user1) {
		t.Errorf("expected user1 to still be viewing")
	}

	// Unregister first client -> user1 still viewing because of client1b
	hub.Unregister(client1)
	if !hub.IsViewing(podID, user1) {
		t.Errorf("expected user1 to still be viewing with 1 active client remaining")
	}

	// Unregister second client -> user1 no longer viewing
	hub.Unregister(client1b)
	if hub.IsViewing(podID, user1) {
		t.Errorf("expected user1 not to be viewing after all clients unregistered")
	}
}

func TestRepository_CreateAndGetByID(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := chat.NewRepository(database.Write, database.Read)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	now := time.Now().UTC()
	bodyText := "Hello partner!"
	msg := &chat.Message{
		ID:        uuid.NewString(),
		PodID:     podID,
		SenderID:  u1,
		Body:      &bodyText,
		CreatedAt: now,
	}

	if err := repo.Create(context.Background(), msg); err != nil {
		t.Fatalf("failed to create message: %v", err)
	}

	fetched, err := repo.GetByID(context.Background(), msg.ID)
	if err != nil {
		t.Fatalf("failed to get message by id: %v", err)
	}
	if fetched.ID != msg.ID {
		t.Errorf("expected id %s, got %s", msg.ID, fetched.ID)
	}
	if fetched.Body == nil || *fetched.Body != bodyText {
		t.Errorf("expected body %s, got %v", bodyText, fetched.Body)
	}
}

func TestRepository_ListMessages_Pagination(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := chat.NewRepository(database.Write, database.Read)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	baseTime := time.Date(2026, 10, 14, 12, 0, 0, 0, time.UTC)

	// Insert 5 messages sequentially: M1, M2, M3, M4, M5
	var msgIDs []string
	for i := 1; i <= 5; i++ {
		b := string(rune('0' + i))
		mID := uuid.NewString()
		msgIDs = append(msgIDs, mID)
		_ = repo.Create(context.Background(), &chat.Message{
			ID:        mID,
			PodID:     podID,
			SenderID:  u1,
			Body:      &b,
			CreatedAt: baseTime.Add(time.Duration(i) * time.Minute),
		})
	}

	// 1. First page: limit 2 without before cursor
	// Should return newest 2 messages: M4, M5 (ordered oldest-to-newest within page)
	page1, cursor1, err := repo.ListMessages(context.Background(), podID, nil, 2)
	if err != nil {
		t.Fatalf("failed to fetch page 1: %v", err)
	}
	if len(page1) != 2 {
		t.Fatalf("expected 2 messages in page 1, got %d", len(page1))
	}
	if page1[0].ID != msgIDs[3] || page1[1].ID != msgIDs[4] {
		t.Errorf("expected [M4, M5], got [%s, %s]", page1[0].ID, page1[1].ID)
	}
	if cursor1 == nil || *cursor1 != msgIDs[3] {
		t.Fatalf("expected next_cursor to be M4 (%s), got %v", msgIDs[3], cursor1)
	}

	// 2. Second page: before = cursor1 (M4), limit 2
	// Should return next older 2 messages: M2, M3 (ordered oldest-to-newest within page)
	page2, cursor2, err := repo.ListMessages(context.Background(), podID, cursor1, 2)
	if err != nil {
		t.Fatalf("failed to fetch page 2: %v", err)
	}
	if len(page2) != 2 {
		t.Fatalf("expected 2 messages in page 2, got %d", len(page2))
	}
	if page2[0].ID != msgIDs[1] || page2[1].ID != msgIDs[2] {
		t.Errorf("expected [M2, M3], got [%s, %s]", page2[0].ID, page2[1].ID)
	}
	if cursor2 == nil || *cursor2 != msgIDs[1] {
		t.Fatalf("expected next_cursor to be M2 (%s), got %v", msgIDs[1], cursor2)
	}

	// 3. Third page: before = cursor2 (M2), limit 2
	// Only 1 message remains (M1), so next_cursor should be nil (exhausted)
	page3, cursor3, err := repo.ListMessages(context.Background(), podID, cursor2, 2)
	if err != nil {
		t.Fatalf("failed to fetch page 3: %v", err)
	}
	if len(page3) != 1 || page3[0].ID != msgIDs[0] {
		t.Fatalf("expected [M1], got %v", page3)
	}
	if cursor3 != nil {
		t.Errorf("expected nil next_cursor when exhausted, got %v", *cursor3)
	}
}
