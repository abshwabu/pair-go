package httpapi_test

import (
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
	"github.com/abshwabu/pair/backend/internal/users"
)

func setupSafetyTestApp(t *testing.T) (http.Handler, *db.DB) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "safety_http_test.db")

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

func registerUserWithAdmin(t *testing.T, router http.Handler, database *db.DB, name, email string, isAdmin bool) (string, string) {
	t.Helper()
	token, userID := registerUser(t, router, name, email)
	if isAdmin {
		usersRepo := users.NewRepository(database.Write, database.Read)
		if err := usersRepo.SetAdmin(t.Context(), email, true); err != nil {
			t.Fatalf("failed to set admin: %v", err)
		}
	}
	return token, userID
}

func createPodForSafety(t *testing.T, database *db.DB, u1ID, u2ID string) string {
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

	return podID
}

func TestSafetyAPI_ReportFlowAndAdminAuthorization(t *testing.T) {
	router, database := setupSafetyTestApp(t)

	userToken, userID := registerUserWithAdmin(t, router, database, "Alice", "alice@example.com", false)
	otherToken, otherID := registerUserWithAdmin(t, router, database, "Bob", "bob@example.com", false)
	adminToken, _ := registerUserWithAdmin(t, router, database, "Admin", "admin@pair.test", true)

	podID := createPodForSafety(t, database, userID, otherID)

	// 1. Cannot report yourself
	selfPayload := fmt.Sprintf(`{"reported_user_id":%q,"reason":"Testing self report"}`, userID)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/reports", strings.NewReader(selfPayload))
	req.Header.Set("Authorization", "Bearer "+userToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for self-report, got %d: %s", rec.Code, rec.Body.String())
	}

	// 2. Reason length validation (too short < 10 chars)
	shortPayload := fmt.Sprintf(`{"reported_user_id":%q,"reason":"too short"}`, otherID)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/reports", strings.NewReader(shortPayload))
	req.Header.Set("Authorization", "Bearer "+userToken)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for short reason, got %d: %s", rec.Code, rec.Body.String())
	}

	// 3. Valid report creation
	validPayload := fmt.Sprintf(`{"reported_user_id":%q,"pod_id":%q,"reason":"User was sending abusive messages in the chat"}`, otherID, podID)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/reports", strings.NewReader(validPayload))
	req.Header.Set("Authorization", "Bearer "+userToken)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created for report, got %d: %s", rec.Code, rec.Body.String())
	}

	var createResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &createResp)
	repData := createResp.Data.(map[string]any)
	reportID := repData["id"].(string)
	if repData["status"] != "open" {
		t.Errorf("expected initial status 'open', got %v", repData["status"])
	}

	// 4. Non-admin (Bob) attempting to GET /api/v1/reports -> 403 Forbidden
	req = httptest.NewRequest(http.MethodGet, "/api/v1/reports", nil)
	req.Header.Set("Authorization", "Bearer "+otherToken)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for non-admin on GET /reports, got %d: %s", rec.Code, rec.Body.String())
	}

	// 5. Non-admin attempting to PATCH /api/v1/reports/{id} -> 403 Forbidden
	req = httptest.NewRequest(http.MethodPatch, "/api/v1/reports/"+reportID, strings.NewReader(`{"status":"reviewed"}`))
	req.Header.Set("Authorization", "Bearer "+otherToken)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for non-admin on PATCH /reports/{id}, got %d: %s", rec.Code, rec.Body.String())
	}

	// 6. Admin GET /api/v1/reports -> 200 OK with report in list
	req = httptest.NewRequest(http.MethodGet, "/api/v1/reports?status=open", nil)
	req.Header.Set("Authorization", "Bearer "+adminToken)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for admin on GET /reports, got %d: %s", rec.Code, rec.Body.String())
	}

	var listResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &listResp)
	reports := listResp.Data.([]any)
	if len(reports) != 1 {
		t.Fatalf("expected 1 report in admin list, got %d", len(reports))
	}

	// 7. Admin PATCH /api/v1/reports/{id} with status 'reviewed'
	req = httptest.NewRequest(http.MethodPatch, "/api/v1/reports/"+reportID, strings.NewReader(`{"status":"reviewed"}`))
	req.Header.Set("Authorization", "Bearer "+adminToken)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for admin PATCH report, got %d: %s", rec.Code, rec.Body.String())
	}

	var patchResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &patchResp)
	updatedData := patchResp.Data.(map[string]any)
	if updatedData["status"] != "reviewed" {
		t.Errorf("expected updated status 'reviewed', got %v", updatedData["status"])
	}
}

func TestSafetyAPI_BlocksAndSharedPodDissolution(t *testing.T) {
	router, database := setupSafetyTestApp(t)

	u1Token, u1ID := registerUser(t, router, "Alice", "alice@example.com")
	_, u2ID := registerUser(t, router, "Bob", "bob@example.com")
	u3Token, _ := registerUser(t, router, "Charlie", "charlie@example.com")

	podID := createPodForSafety(t, database, u1ID, u2ID)

	// 1. Cannot block yourself
	req := httptest.NewRequest(http.MethodPost, "/api/v1/blocks", strings.NewReader(fmt.Sprintf(`{"blocked_user_id":%q}`, u1ID)))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request when blocking oneself, got %d: %s", rec.Code, rec.Body.String())
	}

	// 2. Alice blocks Bob -> dissolves shared pod in same transaction
	req = httptest.NewRequest(http.MethodPost, "/api/v1/blocks", strings.NewReader(fmt.Sprintf(`{"blocked_user_id":%q}`, u2ID)))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on block, got %d: %s", rec.Code, rec.Body.String())
	}

	var blockResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &blockResp)
	blockData := blockResp.Data.(map[string]any)
	blockID := blockData["id"].(string)

	// Verify shared pod was dissolved in database
	var podStatus string
	err := database.Read.QueryRow(`SELECT status FROM pods WHERE id = ?;`, podID).Scan(&podStatus)
	if err != nil {
		t.Fatalf("failed to query pod status: %v", err)
	}
	if podStatus != "dissolved" {
		t.Fatalf("expected pod status 'dissolved', got %q", podStatus)
	}

	// 3. Duplicate block returns 409 Conflict
	req = httptest.NewRequest(http.MethodPost, "/api/v1/blocks", strings.NewReader(fmt.Sprintf(`{"blocked_user_id":%q}`, u2ID)))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict on duplicate block, got %d: %s", rec.Code, rec.Body.String())
	}

	// 4. GET /api/v1/blocks lists Alice's blocks with Bob's details
	req = httptest.NewRequest(http.MethodGet, "/api/v1/blocks", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on GET /blocks, got %d: %s", rec.Code, rec.Body.String())
	}

	var listBlocksResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &listBlocksResp)
	blockList := listBlocksResp.Data.([]any)
	if len(blockList) != 1 {
		t.Fatalf("expected 1 block in list, got %d", len(blockList))
	}
	bDetail := blockList[0].(map[string]any)
	if bDetail["blocked_user_id"] != u2ID || bDetail["name"] != "Bob" {
		t.Errorf("expected Bob in block detail, got %v", bDetail)
	}

	// 5. Non-owner (Charlie) attempting DELETE /api/v1/blocks/{id} -> 403 Forbidden
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/blocks/"+blockID, nil)
	req.Header.Set("Authorization", "Bearer "+u3Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for non-owner unblock, got %d: %s", rec.Code, rec.Body.String())
	}

	// 6. Owner (Alice) unblocks -> 200 OK
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/blocks/"+blockID, nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for owner unblock, got %d: %s", rec.Code, rec.Body.String())
	}

	// 7. Verify block is gone
	req = httptest.NewRequest(http.MethodGet, "/api/v1/blocks", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	_ = json.Unmarshal(rec.Body.Bytes(), &listBlocksResp)
	blockList = listBlocksResp.Data.([]any)
	if len(blockList) != 0 {
		t.Fatalf("expected 0 blocks after deletion, got %d", len(blockList))
	}
}
