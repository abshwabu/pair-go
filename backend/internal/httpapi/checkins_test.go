package httpapi_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/config"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/httpapi"
)

func setupCheckInsTestApp(t *testing.T) (http.Handler, *db.DB) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "checkins_http_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	cfg := &config.Config{
		Port:   "8080",
		DBPath: dbPath,
	}

	router := httpapi.NewRouter(cfg, database, nil)
	return router, database
}

func createPodForCheckIns(t *testing.T, database *db.DB, u1ID, u2ID string) string {
	t.Helper()
	podID := uuid.NewString()
	now := time.Now().UTC().Format(time.RFC3339)

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
	`, goal1ID, u1ID, now, now)

	goal2ID := uuid.NewString()
	_, _ = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, 'read', 'Goal 2', 'Desc 2', 'steady', ?, ?);
	`, goal2ID, u2ID, now, now)

	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?), (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, u1ID, goal1ID, now,
		uuid.NewString(), podID, u2ID, goal2ID, now)
	if err != nil {
		t.Fatalf("failed to insert pod members: %v", err)
	}

	// Create initial zero streak row
	_, _ = database.Write.Exec(`
		INSERT INTO streaks (id, pod_id, current_streak, best_streak, last_check_in_date, updated_at)
		VALUES (?, ?, 0, 0, NULL, ?);
	`, uuid.NewString(), podID, now)

	return podID
}

func TestCheckInsAPI_PostCheckInAndStreakRecalculation(t *testing.T) {
	router, database := setupCheckInsTestApp(t)

	u1Token, u1ID := registerUser(t, router, "Alice", "alice@example.com")
	u2Token, u2ID := registerUser(t, router, "Bob", "bob@example.com")
	u3Token, _ := registerUser(t, router, "Charlie", "charlie@example.com")

	podID := createPodForCheckIns(t, database, u1ID, u2ID)

	// 1. Non-member (Charlie) attempts check-in -> 403 Forbidden
	req := httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/check-ins", podID), strings.NewReader(`{"note":"hello"}`))
	req.Header.Set("Authorization", "Bearer "+u3Token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for non-member, got %d: %s", rec.Code, rec.Body.String())
	}

	// 2. Note exceeding 500 chars -> 400 Bad Request
	longNote := strings.Repeat("A", 501)
	req = httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/check-ins", podID), strings.NewReader(fmt.Sprintf(`{"note":%q}`, longNote)))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request for long note, got %d: %s", rec.Code, rec.Body.String())
	}

	// 3. Alice checks in for today -> 201 Created
	// Since Bob hasn't checked in yet, current_streak is 0, checked_in_today_by_both is false
	req = httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/check-ins", podID), strings.NewReader(`{"note":"Read 25 pages"}`))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on Alice check-in, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp1 httpapi.Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp1); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	data1 := resp1.Data.(map[string]any)
	if data1["checked_in_today_by_both"] != false {
		t.Fatalf("expected checked_in_today_by_both false after only 1 member checked in")
	}
	if streakVal := int(data1["current_streak"].(float64)); streakVal != 0 {
		t.Fatalf("expected current_streak 0 after only 1 member checked in, got %d", streakVal)
	}

	// 4. Alice attempts duplicate check-in today -> 409 Conflict
	req = httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/check-ins", podID), strings.NewReader(`{"note":"Checking in again"}`))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict on duplicate check-in, got %d: %s", rec.Code, rec.Body.String())
	}

	// 5. Bob checks in for today -> 201 Created
	// Now both members have checked in -> streak increments to 1!
	req = httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/check-ins", podID), bytes.NewReader([]byte(`{"note":"Finished chapter 3"}`)))
	req.Header.Set("Authorization", "Bearer "+u2Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on Bob check-in, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp2 httpapi.Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp2); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	data2 := resp2.Data.(map[string]any)
	if data2["checked_in_today_by_both"] != true {
		t.Fatalf("expected checked_in_today_by_both true after both members checked in")
	}
	if streakVal := int(data2["current_streak"].(float64)); streakVal != 1 {
		t.Fatalf("expected current_streak 1 after both members checked in, got %d", streakVal)
	}
	if bestVal := int(data2["best_streak"].(float64)); bestVal != 1 {
		t.Fatalf("expected best_streak 1, got %d", bestVal)
	}
}

func TestCheckInsAPI_GetStreakAndCheckInsList(t *testing.T) {
	router, database := setupCheckInsTestApp(t)

	u1Token, u1ID := registerUser(t, router, "Alice", "alice@example.com")
	u2Token, u2ID := registerUser(t, router, "Bob", "bob@example.com")

	podID := createPodForCheckIns(t, database, u1ID, u2ID)

	// Alice checks in
	req := httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/check-ins", podID), strings.NewReader(`{}`))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("Alice check-in failed: %s", rec.Body.String())
	}

	// 1. GET /api/v1/pods/{pod}/streak from Alice's perspective
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/v1/pods/%s/streak", podID), nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("GET /streak failed: %d %s", rec.Code, rec.Body.String())
	}

	var streakResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &streakResp)
	streakData := streakResp.Data.(map[string]any)

	if streakData["me_checked_in_today"] != true {
		t.Errorf("expected me_checked_in_today true for Alice")
	}
	if streakData["partner_checked_in_today"] != false {
		t.Errorf("expected partner_checked_in_today false before Bob checks in")
	}
	if streakData["both_checked_in_today"] != false {
		t.Errorf("expected both_checked_in_today false")
	}

	// 2. GET /api/v1/pods/{pod}/streak from Bob's perspective
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/v1/pods/%s/streak", podID), nil)
	req.Header.Set("Authorization", "Bearer "+u2Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	_ = json.Unmarshal(rec.Body.Bytes(), &streakResp)
	streakData = streakResp.Data.(map[string]any)

	if streakData["me_checked_in_today"] != false {
		t.Errorf("expected me_checked_in_today false for Bob")
	}
	if streakData["partner_checked_in_today"] != true {
		t.Errorf("expected partner_checked_in_today true for Bob")
	}

	// Bob now checks in
	req = httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/pods/%s/check-ins", podID), strings.NewReader(`{}`))
	req.Header.Set("Authorization", "Bearer "+u2Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("Bob check-in failed: %s", rec.Body.String())
	}

	// Verify GET /streak now shows both checked in
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/v1/pods/%s/streak", podID), nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	_ = json.Unmarshal(rec.Body.Bytes(), &streakResp)
	streakData = streakResp.Data.(map[string]any)
	if streakData["both_checked_in_today"] != true {
		t.Errorf("expected both_checked_in_today true after both checked in")
	}
	if int(streakData["current_streak"].(float64)) != 1 {
		t.Errorf("expected current_streak 1, got %v", streakData["current_streak"])
	}

	// 3. GET /api/v1/pods/{pod}/check-ins
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/v1/pods/%s/check-ins?limit=60", podID), nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("GET /check-ins failed: %d %s", rec.Code, rec.Body.String())
	}

	var listResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &listResp)
	items := listResp.Data.([]any)

	if len(items) != 1 {
		t.Fatalf("expected 1 date group, got %d", len(items))
	}
	firstDate := items[0].(map[string]any)
	if firstDate["both_checked_in"] != true {
		t.Errorf("expected both_checked_in true on date item")
	}
	memberIDs := firstDate["member_ids"].([]any)
	if len(memberIDs) != 2 {
		t.Errorf("expected 2 member IDs, got %d", len(memberIDs))
	}
}
