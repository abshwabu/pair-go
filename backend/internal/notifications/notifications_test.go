package notifications_test

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/notifications"
	"github.com/abshwabu/pair/backend/internal/users"
)

func setupTestDB(t *testing.T) (*db.DB, *users.Repository, *notifications.Repository) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "notifications_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to create database: %v", err)
	}

	t.Cleanup(func() {
		_ = database.Close()
	})

	usersRepo := users.NewRepository(database.Write, database.Read)
	notifRepo := notifications.NewRepository(database.Write, database.Read)

	return database, usersRepo, notifRepo
}

func createTestUser(t *testing.T, usersRepo *users.Repository, email, name string, fcmToken *string) *users.User {
	t.Helper()
	u := &users.User{
		ID:           uuid.NewString(),
		Name:         name,
		Email:        email,
		PasswordHash: "hashedpassword",
		Timezone:     "UTC",
		Language:     "en",
		FCMToken:     fcmToken,
		IsAdmin:      false,
		CreatedAt:    time.Now().UTC(),
		UpdatedAt:    time.Now().UTC(),
	}
	if err := usersRepo.Create(context.Background(), u); err != nil {
		t.Fatalf("failed to create user %s: %v", email, err)
	}
	return u
}

func TestRepository_CreateAndGet(t *testing.T) {
	_, usersRepo, notifRepo := setupTestDB(t)
	ctx := context.Background()

	u := createTestUser(t, usersRepo, "alice@example.com", "Alice", nil)

	payloadBytes, _ := json.Marshal(map[string]any{
		"type":   "new_message",
		"pod_id": "pod-123",
		"title":  "New message",
		"body":   "Hello world",
	})

	n := &notifications.Notification{
		ID:        uuid.NewString(),
		UserID:    u.ID,
		Type:      "new_message",
		Payload:   payloadBytes,
		CreatedAt: time.Now().UTC(),
	}

	if err := notifRepo.Create(ctx, n); err != nil {
		t.Fatalf("failed to create notification: %v", err)
	}

	got, err := notifRepo.GetByID(ctx, n.ID)
	if err != nil {
		t.Fatalf("failed to get notification: %v", err)
	}

	if got.ID != n.ID || got.UserID != u.ID || got.Type != "new_message" {
		t.Fatalf("unexpected notification data: %+v", got)
	}
	if got.SentAt != nil || got.ReadAt != nil {
		t.Fatalf("expected sent_at and read_at to be nil, got sent=%v, read=%v", got.SentAt, got.ReadAt)
	}
}

func TestRepository_MarkRead(t *testing.T) {
	_, usersRepo, notifRepo := setupTestDB(t)
	ctx := context.Background()

	u1 := createTestUser(t, usersRepo, "u1@example.com", "User 1", nil)
	u2 := createTestUser(t, usersRepo, "u2@example.com", "User 2", nil)

	n := &notifications.Notification{
		ID:        uuid.NewString(),
		UserID:    u1.ID,
		Type:      "checkin_nudge",
		Payload:   json.RawMessage(`{"title":"Nudge"}`),
		CreatedAt: time.Now().UTC(),
	}
	_ = notifRepo.Create(ctx, n)

	// Non-owner attempt should fail with ErrForbidden
	_, err := notifRepo.MarkRead(ctx, n.ID, u2.ID, time.Now().UTC())
	if !errors.Is(err, notifications.ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}

	// Owner attempt should succeed
	updated, err := notifRepo.MarkRead(ctx, n.ID, u1.ID, time.Now().UTC())
	if err != nil {
		t.Fatalf("failed to mark read: %v", err)
	}
	if updated.ReadAt == nil {
		t.Fatalf("expected read_at to be non-nil")
	}
}

func TestRepository_ListByUserID_Pagination(t *testing.T) {
	_, usersRepo, notifRepo := setupTestDB(t)
	ctx := context.Background()

	u := createTestUser(t, usersRepo, "paginated@example.com", "Paginated User", nil)

	var ids []string
	baseTime := time.Date(2026, 10, 14, 10, 0, 0, 0, time.UTC)
	for i := 0; i < 5; i++ {
		id := uuid.NewString()
		ids = append(ids, id)
		n := &notifications.Notification{
			ID:        id,
			UserID:    u.ID,
			Type:      "type",
			Payload:   json.RawMessage(`{}`),
			CreatedAt: baseTime.Add(time.Duration(i) * time.Minute),
		}
		_ = notifRepo.Create(ctx, n)
	}

	// Page 1: limit 2 -> newest first (ids[4], ids[3])
	page1, cursor1, err := notifRepo.ListByUserID(ctx, u.ID, nil, 2)
	if err != nil {
		t.Fatalf("page 1 failed: %v", err)
	}
	if len(page1) != 2 || cursor1 == nil {
		t.Fatalf("expected 2 items and non-nil cursor, got len=%d cursor=%v", len(page1), cursor1)
	}
	if page1[0].ID != ids[4] || page1[1].ID != ids[3] {
		t.Fatalf("expected ids %s, %s; got %s, %s", ids[4], ids[3], page1[0].ID, page1[1].ID)
	}

	// Page 2: with cursor1 -> (ids[2], ids[1])
	page2, cursor2, err := notifRepo.ListByUserID(ctx, u.ID, cursor1, 2)
	if err != nil {
		t.Fatalf("page 2 failed: %v", err)
	}
	if len(page2) != 2 || cursor2 == nil {
		t.Fatalf("expected 2 items and non-nil cursor, got len=%d cursor=%v", len(page2), cursor2)
	}
	if page2[0].ID != ids[2] || page2[1].ID != ids[1] {
		t.Fatalf("expected ids %s, %s; got %s, %s", ids[2], ids[1], page2[0].ID, page2[1].ID)
	}

	// Page 3: with cursor2 -> (ids[0])
	page3, cursor3, err := notifRepo.ListByUserID(ctx, u.ID, cursor2, 2)
	if err != nil {
		t.Fatalf("page 3 failed: %v", err)
	}
	if len(page3) != 1 || cursor3 != nil {
		t.Fatalf("expected 1 item and nil cursor, got len=%d cursor=%v", len(page3), cursor3)
	}
	if page3[0].ID != ids[0] {
		t.Fatalf("expected id %s, got %s", ids[0], page3[0].ID)
	}
}

func TestService_SendAndWorkerDrain_Success(t *testing.T) {
	dbConn, usersRepo, notifRepo := setupTestDB(t)
	ctx := context.Background()

	token := "valid-device-token-123"
	u := createTestUser(t, usersRepo, "fcm@example.com", "FCM User", &token)

	service := notifications.NewService(notifRepo, dbConn.Read)
	fakeFCM := notifications.NewFakeFCMClient()
	worker := notifications.NewWorker(notifRepo, usersRepo, fakeFCM, service.NotifyChan(),
		notifications.WithBaseBackoff(10*time.Millisecond),
	)

	payload := map[string]any{
		"type":    "new_message",
		"pod_id":  "pod-abc",
		"title":   "New message from Alice",
		"body":    "Hey, how is your goal coming along?",
	}

	if err := service.Send(ctx, u.ID, "new_message", payload); err != nil {
		t.Fatalf("service.Send failed: %v", err)
	}

	// Verify worker signal received
	select {
	case <-service.NotifyChan():
	default:
		t.Fatalf("expected notification signal in notify channel")
	}

	// Drain worker
	if err := worker.Drain(ctx); err != nil {
		t.Fatalf("worker.Drain failed: %v", err)
	}

	// Verify FakeFCMClient received push
	pushes := fakeFCM.GetSentPushes()
	if len(pushes) != 1 {
		t.Fatalf("expected 1 push sent, got %d", len(pushes))
	}
	if pushes[0].Token != token || pushes[0].Title != "New message from Alice" || pushes[0].Body != "Hey, how is your goal coming along?" {
		t.Fatalf("unexpected push payload: %+v", pushes[0])
	}
	if pushes[0].Data["pod_id"] != "pod-abc" || pushes[0].Data["type"] != "new_message" {
		t.Fatalf("unexpected push data fields: %+v", pushes[0].Data)
	}

	// Verify notification row is marked sent
	items, _, _ := notifRepo.ListByUserID(ctx, u.ID, nil, 10)
	if len(items) != 1 || items[0].SentAt == nil {
		t.Fatalf("expected notification to be marked sent, got %+v", items)
	}
}

func TestWorker_Drain_UnregisteredTokenClearsToken(t *testing.T) {
	dbConn, usersRepo, notifRepo := setupTestDB(t)
	ctx := context.Background()

	badToken := "unregistered-device-token"
	u := createTestUser(t, usersRepo, "badtoken@example.com", "Bad Token User", &badToken)

	service := notifications.NewService(notifRepo, dbConn.Read)
	fakeFCM := notifications.NewFakeFCMClient()
	fakeFCM.SetUnregistered(badToken)

	worker := notifications.NewWorker(notifRepo, usersRepo, fakeFCM, service.NotifyChan(),
		notifications.WithBaseBackoff(10*time.Millisecond),
	)

	_ = service.Send(ctx, u.ID, "checkin_nudge", map[string]any{
		"type":   "checkin_nudge",
		"pod_id": "pod-1",
		"title":  "Check-in",
		"body":   "Please check in",
	})

	// Drain
	if err := worker.Drain(ctx); err != nil {
		t.Fatalf("worker drain failed: %v", err)
	}

	// Verify user's FCM token was cleared
	freshUser, err := usersRepo.GetByID(ctx, u.ID)
	if err != nil {
		t.Fatalf("failed to get user: %v", err)
	}
	if freshUser.FCMToken != nil {
		t.Fatalf("expected fcm_token to be cleared (nil), got %s", *freshUser.FCMToken)
	}

	// Verify notification marked sent (does not remain unsent)
	items, _, _ := notifRepo.ListByUserID(ctx, u.ID, nil, 10)
	if len(items) != 1 || items[0].SentAt == nil {
		t.Fatalf("expected notification to be marked sent after unregistered token handling")
	}
}

func TestWorker_Drain_RetryWithBackoff(t *testing.T) {
	dbConn, usersRepo, notifRepo := setupTestDB(t)
	ctx := context.Background()

	token := "retry-token"
	u := createTestUser(t, usersRepo, "retry@example.com", "Retry User", &token)

	service := notifications.NewService(notifRepo, dbConn.Read)
	fakeFCM := notifications.NewFakeFCMClient()
	fakeFCM.SetFailWithError(errors.New("transient network timeout"))

	worker := notifications.NewWorker(notifRepo, usersRepo, fakeFCM, service.NotifyChan(),
		notifications.WithBaseBackoff(2*time.Millisecond),
	)

	_ = service.Send(ctx, u.ID, "streak_broken", map[string]any{
		"type":   "streak_broken",
		"pod_id": "pod-1",
		"title":  "Streak Broken",
		"body":   "Your streak was reset",
	})

	// First drain: fails, not marked sent yet
	_ = worker.Drain(ctx)
	items, _, _ := notifRepo.ListByUserID(ctx, u.ID, nil, 10)
	if len(items) != 1 || items[0].SentAt != nil {
		t.Fatalf("notification should still be unsent after 1 failed attempt")
	}

	// Wait for backoff and drain 4 more times (total 5 attempts)
	for i := 0; i < 4; i++ {
		time.Sleep(30 * time.Millisecond)
		_ = worker.Drain(ctx)
	}

	// After 5 attempts, notification should be marked sent/abandoned to avoid poison pill
	items, _, _ = notifRepo.ListByUserID(ctx, u.ID, nil, 10)
	if len(items) != 1 || items[0].SentAt == nil {
		t.Fatalf("expected notification to be marked sent after max retries")
	}
}

func TestService_EmitStreakBroken(t *testing.T) {
	dbConn, usersRepo, notifRepo := setupTestDB(t)
	ctx := context.Background()

	u1 := createTestUser(t, usersRepo, "p1@example.com", "Partner 1", nil)
	u2 := createTestUser(t, usersRepo, "p2@example.com", "Partner 2", nil)

	podID := uuid.NewString()
	now := time.Now().UTC().Format(time.RFC3339)

	// Create goal
	goalID := uuid.NewString()
	_, _ = dbConn.Write.Exec(`INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at) VALUES (?, ?, 'habit', 'Read', 'Daily', 'steady', ?, ?);`, goalID, u1.ID, now, now)

	// Create pod & members
	_, _ = dbConn.Write.Exec(`INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at) VALUES (?, 'habit', 'active', 2, ?, ?);`, podID, now, now)
	_, _ = dbConn.Write.Exec(`INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at) VALUES (?, ?, ?, ?, ?);`, uuid.NewString(), podID, u1.ID, goalID, now)
	_, _ = dbConn.Write.Exec(`INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at) VALUES (?, ?, ?, ?, ?);`, uuid.NewString(), podID, u2.ID, goalID, now)

	service := notifications.NewService(notifRepo, dbConn.Read)
	if err := service.EmitStreakBroken(ctx, podID); err != nil {
		t.Fatalf("EmitStreakBroken failed: %v", err)
	}

	// Verify both users received a streak_broken notification
	items1, _, _ := notifRepo.ListByUserID(ctx, u1.ID, nil, 10)
	if len(items1) != 1 || items1[0].Type != "streak_broken" {
		t.Fatalf("expected streak_broken notification for user 1, got %+v", items1)
	}

	items2, _, _ := notifRepo.ListByUserID(ctx, u2.ID, nil, 10)
	if len(items2) != 1 || items2[0].Type != "streak_broken" {
		t.Fatalf("expected streak_broken notification for user 2, got %+v", items2)
	}
}
