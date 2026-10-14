package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/chat"
	"github.com/abshwabu/pair/backend/internal/config"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/httpapi"
	"github.com/abshwabu/pair/backend/internal/jobs"
	"github.com/abshwabu/pair/backend/internal/matching"
	"github.com/abshwabu/pair/backend/internal/notifications"
)

func setupNotificationsTestApp(t *testing.T) (http.Handler, *db.DB, *chat.Hub, *matching.Worker) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "notif_http_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	cfg := &config.Config{
		Port:   "8080",
		DBPath: dbPath,
	}

	chatHub := chat.NewHub()
	matchingRepo := matching.NewRepository(database.Write, database.Read)
	worker := matching.NewWorker(matchingRepo)
	router := httpapi.NewRouterWithWorker(cfg, database, nil, worker, chatHub)

	t.Cleanup(func() {
		_ = database.Close()
	})

	return router, database, chatHub, worker
}

func createTestPodWithMembers(t *testing.T, database *db.DB, u1ID, u2ID string) string {
	t.Helper()
	podID := uuid.NewString()
	now := time.Now().UTC().Format(time.RFC3339)

	_, err := database.Write.Exec(`
		INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at)
		VALUES (?, 'habit', 'active', 2, ?, ?);
	`, podID, now, now)
	if err != nil {
		t.Fatalf("failed to insert pod: %v", err)
	}

	goal1ID := uuid.NewString()
	goal2ID := uuid.NewString()
	_, _ = database.Write.Exec(`INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at) VALUES (?, ?, 'habit', 'Goal 1', 'Desc', 'steady', ?, ?);`, goal1ID, u1ID, now, now)
	_, _ = database.Write.Exec(`INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at) VALUES (?, ?, 'habit', 'Goal 2', 'Desc', 'steady', ?, ?);`, goal2ID, u2ID, now, now)

	_, _ = database.Write.Exec(`INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at) VALUES (?, ?, ?, ?, ?);`, uuid.NewString(), podID, u1ID, goal1ID, now)
	_, _ = database.Write.Exec(`INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at) VALUES (?, ?, ?, ?, ?);`, uuid.NewString(), podID, u2ID, goal2ID, now)
	_, _ = database.Write.Exec(`INSERT INTO streaks (id, pod_id, current_streak, best_streak, updated_at) VALUES (?, ?, 0, 0, ?);`, uuid.NewString(), podID, now)

	return podID
}

func TestNotifications_FCMTokenUpdate(t *testing.T) {
	router, _, _, _ := setupNotificationsTestApp(t)

	token, _ := registerUser(t, router, "FCM Test", "fcmtest@example.com")

	// 1. Update with empty token -> 400
	emptyBody := []byte(`{"fcm_token": "   "}`)
	req, _ := http.NewRequest(http.MethodPatch, "/api/v1/profile/fcm-token", bytes.NewReader(emptyBody))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for empty fcm_token, got %d", rec.Code)
	}

	// 2. Update with valid token -> 200
	validBody := []byte(`{"fcm_token": "device-token-xyz-123"}`)
	req, _ = http.NewRequest(http.MethodPatch, "/api/v1/profile/fcm-token", bytes.NewReader(validBody))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for updating fcm_token, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Data struct {
			FCMToken *string `json:"fcm_token"`
		} `json:"data"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Data.FCMToken == nil || *resp.Data.FCMToken != "device-token-xyz-123" {
		t.Fatalf("expected updated fcm_token in response, got %v", resp.Data.FCMToken)
	}

	// 3. Confirm persistence via GET /api/v1/profile
	getReq, _ := http.NewRequest(http.MethodGet, "/api/v1/profile", nil)
	getReq.Header.Set("Authorization", "Bearer "+token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)
	if getRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for GET /profile, got %d", getRec.Code)
	}
	_ = json.Unmarshal(getRec.Body.Bytes(), &resp)
	if resp.Data.FCMToken == nil || *resp.Data.FCMToken != "device-token-xyz-123" {
		t.Fatalf("expected persisted fcm_token in profile, got %v", resp.Data.FCMToken)
	}
}

func TestNotifications_NudgeRateLimitAndTrigger(t *testing.T) {
	router, database, _, _ := setupNotificationsTestApp(t)

	token1, u1ID := registerUser(t, router, "Alice", "alice_nudge@example.com")
	_, u2ID := registerUser(t, router, "Bob", "bob_nudge@example.com")

	podID := createTestPodWithMembers(t, database, u1ID, u2ID)

	// 1. First nudge -> 200 OK
	nudgeReq, _ := http.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/nudge", podID), nil)
	nudgeReq.Header.Set("Authorization", "Bearer "+token1)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, nudgeReq)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on first nudge, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify Bob received checkin_nudge notification
	notifRepo := notifications.NewRepository(database.Write, database.Read)
	bobNotifs, _, err := notifRepo.ListByUserID(context.Background(), u2ID, nil, 10)
	if err != nil || len(bobNotifs) != 1 {
		t.Fatalf("expected 1 notification for Bob, got %d, err=%v", len(bobNotifs), err)
	}
	if bobNotifs[0].Type != "checkin_nudge" {
		t.Fatalf("expected notification type checkin_nudge, got %s", bobNotifs[0].Type)
	}

	// 2. Second nudge immediately -> 429 Too Many Requests
	nudgeReq2, _ := http.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/nudge", podID), nil)
	nudgeReq2.Header.Set("Authorization", "Bearer "+token1)
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, nudgeReq2)
	if rec2.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 on second nudge within 6h, got %d: %s", rec2.Code, rec2.Body.String())
	}
}

func TestNotifications_Trigger_NewMessage_SuppressedWhenViewing(t *testing.T) {
	router, database, chatHub, _ := setupNotificationsTestApp(t)

	token1, u1ID := registerUser(t, router, "Alice Msg", "alice_msg@example.com")
	_, u2ID := registerUser(t, router, "Bob Msg", "bob_msg@example.com")

	podID := createTestPodWithMembers(t, database, u1ID, u2ID)
	notifRepo := notifications.NewRepository(database.Write, database.Read)

	// Case A: Bob is NOT viewing the chat -> notification created
	msgBody := []byte(`{"body": "Hello Bob!"}`)
	req, _ := http.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/messages", podID), bytes.NewReader(msgBody))
	req.Header.Set("Authorization", "Bearer "+token1)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 200/201 for SendMessage, got %d: %s", rec.Code, rec.Body.String())
	}

	bobNotifs, _, _ := notifRepo.ListByUserID(context.Background(), u2ID, nil, 10)
	if len(bobNotifs) != 1 || bobNotifs[0].Type != "new_message" {
		t.Fatalf("expected Bob to receive 1 new_message notification when not viewing, got %+v", bobNotifs)
	}

	// Case B: Bob IS viewing the chat (register dummy client on chatHub)
	dummyClient := chat.NewClient(chatHub, nil, podID, u2ID)
	chatHub.Register(dummyClient)
	defer chatHub.Unregister(dummyClient)

	if !chatHub.IsViewing(podID, u2ID) {
		t.Fatalf("expected chatHub.IsViewing to be true for Bob")
	}

	// Alice sends another message while Bob is viewing
	msgBody2 := []byte(`{"body": "Are you there Bob?"}`)
	req2, _ := http.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/messages", podID), bytes.NewReader(msgBody2))
	req2.Header.Set("Authorization", "Bearer "+token1)
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusCreated {
		t.Fatalf("expected 200/201 for SendMessage, got %d", rec2.Code)
	}

	// Verify Bob's notification count DID NOT increase (suppressed!)
	bobNotifsAfter, _, _ := notifRepo.ListByUserID(context.Background(), u2ID, nil, 10)
	if len(bobNotifsAfter) != 1 {
		t.Fatalf("expected notification to be suppressed when partner is viewing, got %d notifications", len(bobNotifsAfter))
	}
}

func TestNotifications_Trigger_CheckIn(t *testing.T) {
	router, database, _, _ := setupNotificationsTestApp(t)

	token1, u1ID := registerUser(t, router, "Alice Check", "alice_chk@example.com")
	token2, u2ID := registerUser(t, router, "Bob Check", "bob_chk@example.com")

	podID := createTestPodWithMembers(t, database, u1ID, u2ID)
	notifRepo := notifications.NewRepository(database.Write, database.Read)

	// 1. Alice checks in for today. Bob has not checked in yet today -> Bob gets checkin_nudge
	checkReq, _ := http.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/check-ins", podID), strings.NewReader(`{"note": "Done for today"}`))
	checkReq.Header.Set("Authorization", "Bearer "+token1)
	checkReq.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, checkReq)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for CheckIn, got %d: %s", rec.Code, rec.Body.String())
	}

	bobNotifs, _, _ := notifRepo.ListByUserID(context.Background(), u2ID, nil, 10)
	if len(bobNotifs) != 1 || bobNotifs[0].Type != "checkin_nudge" {
		t.Fatalf("expected Bob to receive 1 checkin_nudge notification, got %+v", bobNotifs)
	}

	// 2. Bob checks in. Now both are checked in -> Alice should NOT receive a nudge
	checkReq2, _ := http.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/check-ins", podID), strings.NewReader(`{"note": "I am done too"}`))
	checkReq2.Header.Set("Authorization", "Bearer "+token2)
	checkReq2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, checkReq2)
	if rec2.Code != http.StatusCreated {
		t.Fatalf("expected 201 for Bob CheckIn, got %d: %s", rec2.Code, rec2.Body.String())
	}

	aliceNotifs, _, _ := notifRepo.ListByUserID(context.Background(), u1ID, nil, 10)
	if len(aliceNotifs) != 0 {
		t.Fatalf("expected Alice to have 0 notifications (partner completed checkin), got %d", len(aliceNotifs))
	}
}

func TestNotifications_Trigger_StreakBroken(t *testing.T) {
	_, database, _, _ := setupNotificationsTestApp(t)

	u1ID := uuid.NewString()
	u2ID := uuid.NewString()
	now := time.Now().UTC().Format(time.RFC3339)
	_, _ = database.Write.Exec(`INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at) VALUES (?, 'P1', 'p1_streak@example.com', 'h', 'UTC', 'en', 0, ?, ?);`, u1ID, now, now)
	_, _ = database.Write.Exec(`INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at) VALUES (?, 'P2', 'p2_streak@example.com', 'h', 'UTC', 'en', 0, ?, ?);`, u2ID, now, now)

	podID := createTestPodWithMembers(t, database, u1ID, u2ID)

	// Set pod with active streak but last checkin 3 days ago (stale)
	staleDate := time.Now().UTC().AddDate(0, 0, -3).Format("2006-01-02")
	_, _ = database.Write.Exec(`UPDATE streaks SET current_streak = 4, best_streak = 4, last_check_in_date = ? WHERE pod_id = ?;`, staleDate, podID)

	notifRepo := notifications.NewRepository(database.Write, database.Read)
	notifService := notifications.NewService(notifRepo, database.Read)

	// Trigger ResetStaleStreaks
	resetPods, err := jobs.ResetStaleStreaks(context.Background(), database.Write, database.Read, notifService, time.Now().UTC())
	if err != nil {
		t.Fatalf("ResetStaleStreaks failed: %v", err)
	}
	if len(resetPods) != 1 || resetPods[0] != podID {
		t.Fatalf("expected pod %s to be reset, got %v", podID, resetPods)
	}

	// Verify both users received streak_broken notification
	notifs1, _, _ := notifRepo.ListByUserID(context.Background(), u1ID, nil, 10)
	if len(notifs1) != 1 || notifs1[0].Type != "streak_broken" {
		t.Fatalf("expected streak_broken for user 1, got %+v", notifs1)
	}

	notifs2, _, _ := notifRepo.ListByUserID(context.Background(), u2ID, nil, 10)
	if len(notifs2) != 1 || notifs2[0].Type != "streak_broken" {
		t.Fatalf("expected streak_broken for user 2, got %+v", notifs2)
	}
}

func TestNotifications_Trigger_MatchFound(t *testing.T) {
	_, database, _, worker := setupNotificationsTestApp(t)

	u1ID := uuid.NewString()
	u2ID := uuid.NewString()
	now := time.Now().UTC().Format(time.RFC3339)
	_, _ = database.Write.Exec(`INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at) VALUES (?, 'Match A', 'ma@example.com', 'h', 'America/New_York', 'en', 0, ?, ?);`, u1ID, now, now)
	_, _ = database.Write.Exec(`INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at) VALUES (?, 'Match B', 'mb@example.com', 'h', 'America/New_York', 'en', 0, ?, ?);`, u2ID, now, now)

	goal1ID := uuid.NewString()
	goal2ID := uuid.NewString()
	_, _ = database.Write.Exec(`INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at) VALUES (?, ?, 'read', 'Book A', 'Desc', 'steady', ?, ?);`, goal1ID, u1ID, now, now)
	_, _ = database.Write.Exec(`INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at) VALUES (?, ?, 'read', 'Book B', 'Desc', 'steady', ?, ?);`, goal2ID, u2ID, now, now)

	req1ID := uuid.NewString()
	req2ID := uuid.NewString()
	_, _ = database.Write.Exec(`INSERT INTO pod_requests (id, user_id, goal_id, status, timezone_tolerance_hours, language, created_at, updated_at) VALUES (?, ?, ?, 'open', 3, 'en', ?, ?);`, req1ID, u1ID, goal1ID, now, now)
	_, _ = database.Write.Exec(`INSERT INTO pod_requests (id, user_id, goal_id, status, timezone_tolerance_hours, language, created_at, updated_at) VALUES (?, ?, ?, 'open', 3, 'en', ?, ?);`, req2ID, u2ID, goal2ID, now, now)

	// Process matching
	err := worker.ProcessRequest(context.Background(), req1ID)
	if err != nil {
		t.Fatalf("ProcessRequest failed: %v", err)
	}

	notifRepo := notifications.NewRepository(database.Write, database.Read)

	// Verify both users received match_found notification
	notifsA, _, _ := notifRepo.ListByUserID(context.Background(), u1ID, nil, 10)
	if len(notifsA) != 1 || notifsA[0].Type != "match_found" {
		t.Fatalf("expected match_found for user A, got %+v", notifsA)
	}

	notifsB, _, _ := notifRepo.ListByUserID(context.Background(), u2ID, nil, 10)
	if len(notifsB) != 1 || notifsB[0].Type != "match_found" {
		t.Fatalf("expected match_found for user B, got %+v", notifsB)
	}
}

func TestNotifications_ListAndMarkReadEndpoints(t *testing.T) {
	router, database, _, _ := setupNotificationsTestApp(t)

	token1, u1ID := registerUser(t, router, "Reader 1", "r1@example.com")
	token2, _ := registerUser(t, router, "Reader 2", "r2@example.com")

	notifRepo := notifications.NewRepository(database.Write, database.Read)
	notifService := notifications.NewService(notifRepo, database.Read)

	// Create 3 notifications for user 1
	ctx := context.Background()
	_ = notifService.Send(ctx, u1ID, "type1", map[string]any{"title": "Msg 1"})
	_ = notifService.Send(ctx, u1ID, "type2", map[string]any{"title": "Msg 2"})
	_ = notifService.Send(ctx, u1ID, "type3", map[string]any{"title": "Msg 3"})

	// 1. GET /api/v1/notifications
	getReq, _ := http.NewRequest(http.MethodGet, "/api/v1/notifications?limit=2", nil)
	getReq.Header.Set("Authorization", "Bearer "+token1)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, getReq)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for GET /notifications, got %d: %s", rec.Code, rec.Body.String())
	}

	var listResp struct {
		Data []struct {
			ID     string  `json:"id"`
			Type   string  `json:"type"`
			ReadAt *string `json:"read_at"`
		} `json:"data"`
		Meta struct {
			NextCursor *string `json:"next_cursor"`
		} `json:"meta"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &listResp)
	if len(listResp.Data) != 2 || listResp.Meta.NextCursor == nil {
		t.Fatalf("expected 2 items and next_cursor, got len=%d cursor=%v", len(listResp.Data), listResp.Meta.NextCursor)
	}

	firstID := listResp.Data[0].ID

	// 2. User 2 attempts to mark User 1's notification as read -> 403 Forbidden
	patchOtherReq, _ := http.NewRequest(http.MethodPatch, fmt.Sprintf("/api/v1/notifications/%s/read", firstID), nil)
	patchOtherReq.Header.Set("Authorization", "Bearer "+token2)
	recOther := httptest.NewRecorder()
	router.ServeHTTP(recOther, patchOtherReq)
	if recOther.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for non-owner mark-read, got %d", recOther.Code)
	}

	// 3. User 1 marks own notification as read -> 200 OK
	patchOwnReq, _ := http.NewRequest(http.MethodPatch, fmt.Sprintf("/api/v1/notifications/%s/read", firstID), nil)
	patchOwnReq.Header.Set("Authorization", "Bearer "+token1)
	recOwn := httptest.NewRecorder()
	router.ServeHTTP(recOwn, patchOwnReq)
	if recOwn.Code != http.StatusOK {
		t.Fatalf("expected 200 for owner mark-read, got %d: %s", recOwn.Code, recOwn.Body.String())
	}

	var readResp struct {
		Data struct {
			ID     string  `json:"id"`
			ReadAt *string `json:"read_at"`
		} `json:"data"`
	}
	_ = json.Unmarshal(recOwn.Body.Bytes(), &readResp)
	if readResp.Data.ReadAt == nil {
		t.Fatalf("expected read_at to be populated after marking read")
	}
}
