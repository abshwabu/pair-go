package httpapi_test

import (
	"bytes"
	"encoding/json"
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

func setupGoalsTestApp(t *testing.T) (http.Handler, *db.DB, string, string) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "goals_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	cfg := &config.Config{
		Port:   "8080",
		DBPath: dbPath,
	}

	router := httpapi.NewRouter(cfg, database)

	// Helper to register user and return token and user ID
	registerUser := func(name, email string) (string, string) {
		payload := map[string]any{
			"name":     name,
			"email":    email,
			"password": "password123",
			"timezone": "UTC",
		}
		body, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("failed to register user: %s", rec.Body.String())
		}

		var resp httpapi.Response
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		dataMap := resp.Data.(map[string]any)
		token := dataMap["token"].(string)
		userMap := dataMap["user"].(map[string]any)
		userID := userMap["id"].(string)
		return token, userID
	}

	token1, user1ID := registerUser("Alice", "alice@goals.test")
	return router, database, token1, user1ID
}

func registerSecondUser(t *testing.T, router http.Handler) (string, string) {
	t.Helper()
	payload := map[string]any{
		"name":     "Bob",
		"email":    "bob@goals.test",
		"password": "password123",
		"timezone": "UTC",
	}
	body, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to register user 2: %s", rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	dataMap := resp.Data.(map[string]any)
	token := dataMap["token"].(string)
	userMap := dataMap["user"].(map[string]any)
	userID := userMap["id"].(string)
	return token, userID
}

func TestGoals_CRUDHappyPath(t *testing.T) {
	router, database, token, _ := setupGoalsTestApp(t)
	defer database.Close()

	// 1. POST /api/v1/goals (Create Goal 1)
	createPayload1 := map[string]any{
		"category":           "read",
		"title":              "Read Dune",
		"target_description": "Finish 500 pages",
		"pace":               "steady",
	}
	body1, _ := json.Marshal(createPayload1)
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/goals", bytes.NewReader(body1))
	req1.Header.Set("Authorization", "Bearer "+token)
	req1.Header.Set("Content-Type", "application/json")
	rec1 := httptest.NewRecorder()
	router.ServeHTTP(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("expected 201 for POST /goals, got %d: %s", rec1.Code, rec1.Body.String())
	}

	var createResp1 httpapi.Response
	_ = json.Unmarshal(rec1.Body.Bytes(), &createResp1)
	goal1 := createResp1.Data.(map[string]any)
	goal1ID := goal1["id"].(string)

	if goal1["title"] != "Read Dune" {
		t.Errorf("expected title 'Read Dune', got %v", goal1["title"])
	}
	if goal1["category"] != "read" {
		t.Errorf("expected category 'read', got %v", goal1["category"])
	}
	if goal1["pace"] != "steady" {
		t.Errorf("expected pace 'steady', got %v", goal1["pace"])
	}

	// 2. POST /api/v1/goals (Create Goal 2)
	createPayload2 := map[string]any{
		"category":           "fitness",
		"title":              "Run 5k",
		"target_description": "3 times per week",
		"pace":               "intense",
	}
	body2, _ := json.Marshal(createPayload2)
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/goals", bytes.NewReader(body2))
	req2.Header.Set("Authorization", "Bearer "+token)
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)

	if rec2.Code != http.StatusCreated {
		t.Fatalf("expected 201 for POST /goals, got %d: %s", rec2.Code, rec2.Body.String())
	}

	var createResp2 httpapi.Response
	_ = json.Unmarshal(rec2.Body.Bytes(), &createResp2)
	goal2 := createResp2.Data.(map[string]any)
	goal2ID := goal2["id"].(string)

	// 3. GET /api/v1/goals (List Goals - newest first)
	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/goals", nil)
	listReq.Header.Set("Authorization", "Bearer "+token)
	listRec := httptest.NewRecorder()
	router.ServeHTTP(listRec, listReq)

	if listRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for GET /goals, got %d: %s", listRec.Code, listRec.Body.String())
	}

	var listResp httpapi.Response
	_ = json.Unmarshal(listRec.Body.Bytes(), &listResp)
	goalsList := listResp.Data.([]any)

	if len(goalsList) != 2 {
		t.Fatalf("expected 2 goals in list, got %d", len(goalsList))
	}
	// Verify newest first ordering
	firstGoal := goalsList[0].(map[string]any)
	secondGoal := goalsList[1].(map[string]any)
	if firstGoal["id"] != goal2ID {
		t.Errorf("expected newest goal2 (%s) first, got %s", goal2ID, firstGoal["id"])
	}
	if secondGoal["id"] != goal1ID {
		t.Errorf("expected older goal1 (%s) second, got %s", goal1ID, secondGoal["id"])
	}

	// 4. GET /api/v1/goals/{id}
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/goals/"+goal1ID, nil)
	getReq.Header.Set("Authorization", "Bearer "+token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	if getRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for GET /goals/%s, got %d: %s", goal1ID, getRec.Code, getRec.Body.String())
	}

	// 5. PATCH /api/v1/goals/{id}
	updatePayload := map[string]any{
		"title": "Read Dune Messiah",
		"pace":  "relaxed",
	}
	updateBody, _ := json.Marshal(updatePayload)
	patchReq := httptest.NewRequest(http.MethodPatch, "/api/v1/goals/"+goal1ID, bytes.NewReader(updateBody))
	patchReq.Header.Set("Authorization", "Bearer "+token)
	patchReq.Header.Set("Content-Type", "application/json")
	patchRec := httptest.NewRecorder()
	router.ServeHTTP(patchRec, patchReq)

	if patchRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for PATCH /goals/%s, got %d: %s", goal1ID, patchRec.Code, patchRec.Body.String())
	}

	var patchResp httpapi.Response
	_ = json.Unmarshal(patchRec.Body.Bytes(), &patchResp)
	updatedGoal := patchResp.Data.(map[string]any)
	if updatedGoal["title"] != "Read Dune Messiah" {
		t.Errorf("expected updated title 'Read Dune Messiah', got %v", updatedGoal["title"])
	}
	if updatedGoal["pace"] != "relaxed" {
		t.Errorf("expected updated pace 'relaxed', got %v", updatedGoal["pace"])
	}

	// 6. DELETE /api/v1/goals/{id}
	delReq := httptest.NewRequest(http.MethodDelete, "/api/v1/goals/"+goal1ID, nil)
	delReq.Header.Set("Authorization", "Bearer "+token)
	delRec := httptest.NewRecorder()
	router.ServeHTTP(delRec, delReq)

	if delRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for DELETE /goals/%s, got %d: %s", goal1ID, delRec.Code, delRec.Body.String())
	}

	// 7. Verify GET /api/v1/goals/{id} returns 404 after deletion
	verifyReq := httptest.NewRequest(http.MethodGet, "/api/v1/goals/"+goal1ID, nil)
	verifyReq.Header.Set("Authorization", "Bearer "+token)
	verifyRec := httptest.NewRecorder()
	router.ServeHTTP(verifyRec, verifyReq)

	if verifyRec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 after deletion, got %d: %s", verifyRec.Code, verifyRec.Body.String())
	}
}

func TestGoals_Validation(t *testing.T) {
	router, database, token, _ := setupGoalsTestApp(t)
	defer database.Close()

	// 1. Invalid Category
	payload := map[string]any{
		"category": "skydiving",
		"title":    "Learn to fly",
		"pace":     "steady",
	}
	body, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/goals", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for invalid category, got %d: %s", rec.Code, rec.Body.String())
	}

	// 2. Invalid Pace
	payload = map[string]any{
		"category": "read",
		"title":    "Read a book",
		"pace":     "hyperdrive",
	}
	body, _ = json.Marshal(payload)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/goals", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for invalid pace, got %d: %s", rec.Code, rec.Body.String())
	}

	// 3. Missing / Empty Title
	payload = map[string]any{
		"category": "fitness",
		"title":    "   ",
		"pace":     "steady",
	}
	body, _ = json.Marshal(payload)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/goals", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for empty title, got %d: %s", rec.Code, rec.Body.String())
	}

	// 4. Title exceeding 120 chars
	longTitle := strings.Repeat("A", 121)
	payload = map[string]any{
		"category": "fitness",
		"title":    longTitle,
		"pace":     "steady",
	}
	body, _ = json.Marshal(payload)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/goals", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for title exceeding 120 chars, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestGoals_Ownership_403(t *testing.T) {
	router, database, token1, _ := setupGoalsTestApp(t)
	defer database.Close()

	token2, _ := registerSecondUser(t, router)

	// User 1 creates Goal 1
	createPayload := map[string]any{
		"category": "habit",
		"title":    "Morning Meditation",
		"pace":     "relaxed",
	}
	body, _ := json.Marshal(createPayload)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/goals", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token1)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create goal: %s", rec.Body.String())
	}

	var createResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &createResp)
	goalData := createResp.Data.(map[string]any)
	goalID := goalData["id"].(string)

	// 1. User 2 attempts GET /api/v1/goals/{id} -> 403 Forbidden
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/goals/"+goalID, nil)
	getReq.Header.Set("Authorization", "Bearer "+token2)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	if getRec.Code != http.StatusForbidden {
		t.Errorf("expected 403 for non-owner GET, got %d: %s", getRec.Code, getRec.Body.String())
	}

	// 2. User 2 attempts PATCH /api/v1/goals/{id} -> 403 Forbidden
	patchPayload := map[string]any{"title": "Hacked Title"}
	patchBody, _ := json.Marshal(patchPayload)
	patchReq := httptest.NewRequest(http.MethodPatch, "/api/v1/goals/"+goalID, bytes.NewReader(patchBody))
	patchReq.Header.Set("Authorization", "Bearer "+token2)
	patchReq.Header.Set("Content-Type", "application/json")
	patchRec := httptest.NewRecorder()
	router.ServeHTTP(patchRec, patchReq)

	if patchRec.Code != http.StatusForbidden {
		t.Errorf("expected 403 for non-owner PATCH, got %d: %s", patchRec.Code, patchRec.Body.String())
	}

	// 3. User 2 attempts DELETE /api/v1/goals/{id} -> 403 Forbidden
	delReq := httptest.NewRequest(http.MethodDelete, "/api/v1/goals/"+goalID, nil)
	delReq.Header.Set("Authorization", "Bearer "+token2)
	delRec := httptest.NewRecorder()
	router.ServeHTTP(delRec, delReq)

	if delRec.Code != http.StatusForbidden {
		t.Errorf("expected 403 for non-owner DELETE, got %d: %s", delRec.Code, delRec.Body.String())
	}
}

func TestGoals_ActivePod_409(t *testing.T) {
	router, database, token, userID := setupGoalsTestApp(t)
	defer database.Close()

	// User 1 creates Goal
	createPayload := map[string]any{
		"category": "watch",
		"title":    "Watch The Wire",
		"pace":     "steady",
	}
	body, _ := json.Marshal(createPayload)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/goals", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create goal: %s", rec.Body.String())
	}

	var createResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &createResp)
	goalData := createResp.Data.(map[string]any)
	goalID := goalData["id"].(string)

	// Attach goal to an active pod via pod_members
	now := time.Now().UTC().Format(time.RFC3339)
	podID := uuid.NewString()
	_, err := database.Write.Exec(`
		INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at)
		VALUES (?, 'watch', 'active', 2, ?, ?);
	`, podID, now, now)
	if err != nil {
		t.Fatalf("failed to insert active pod: %v", err)
	}

	memberID := uuid.NewString()
	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at, left_at)
		VALUES (?, ?, ?, ?, ?, NULL);
	`, memberID, podID, userID, goalID, now)
	if err != nil {
		t.Fatalf("failed to insert pod member: %v", err)
	}

	// 1. PATCH /api/v1/goals/{id} should fail with 409 Conflict
	patchPayload := map[string]any{"title": "Watch The Sopranos"}
	patchBody, _ := json.Marshal(patchPayload)
	patchReq := httptest.NewRequest(http.MethodPatch, "/api/v1/goals/"+goalID, bytes.NewReader(patchBody))
	patchReq.Header.Set("Authorization", "Bearer "+token)
	patchReq.Header.Set("Content-Type", "application/json")
	patchRec := httptest.NewRecorder()
	router.ServeHTTP(patchRec, patchReq)

	if patchRec.Code != http.StatusConflict {
		t.Fatalf("expected 409 for PATCH active pod goal, got %d: %s", patchRec.Code, patchRec.Body.String())
	}

	var patchErrResp httpapi.Response
	_ = json.Unmarshal(patchRec.Body.Bytes(), &patchErrResp)
	if patchErrResp.Error == nil || patchErrResp.Error.Code != "ACTIVE_POD_CONFLICT" {
		t.Errorf("expected ACTIVE_POD_CONFLICT error code, got %+v", patchErrResp.Error)
	}

	// 2. DELETE /api/v1/goals/{id} should fail with 409 Conflict
	delReq := httptest.NewRequest(http.MethodDelete, "/api/v1/goals/"+goalID, nil)
	delReq.Header.Set("Authorization", "Bearer "+token)
	delRec := httptest.NewRecorder()
	router.ServeHTTP(delRec, delReq)

	if delRec.Code != http.StatusConflict {
		t.Fatalf("expected 409 for DELETE active pod goal, got %d: %s", delRec.Code, delRec.Body.String())
	}

	// 3. Complete the pod -> now PATCH and DELETE should succeed!
	_, err = database.Write.Exec(`UPDATE pods SET status = 'completed' WHERE id = ?;`, podID)
	if err != nil {
		t.Fatalf("failed to update pod status: %v", err)
	}

	// PATCH should now succeed
	patchReq2 := httptest.NewRequest(http.MethodPatch, "/api/v1/goals/"+goalID, bytes.NewReader(patchBody))
	patchReq2.Header.Set("Authorization", "Bearer "+token)
	patchReq2.Header.Set("Content-Type", "application/json")
	patchRec2 := httptest.NewRecorder()
	router.ServeHTTP(patchRec2, patchReq2)

	if patchRec2.Code != http.StatusOK {
		t.Fatalf("expected 200 for PATCH completed pod goal, got %d: %s", patchRec2.Code, patchRec2.Body.String())
	}

	// DELETE should now succeed
	delReq2 := httptest.NewRequest(http.MethodDelete, "/api/v1/goals/"+goalID, nil)
	delReq2.Header.Set("Authorization", "Bearer "+token)
	delRec2 := httptest.NewRecorder()
	router.ServeHTTP(delRec2, delReq2)

	if delRec2.Code != http.StatusOK {
		t.Fatalf("expected 200 for DELETE completed pod goal, got %d: %s", delRec2.Code, delRec2.Body.String())
	}
}

func TestGoals_NotFound_404(t *testing.T) {
	router, database, token, _ := setupGoalsTestApp(t)
	defer database.Close()

	randomID := uuid.NewString()

	// GET unknown ID
	req := httptest.NewRequest(http.MethodGet, "/api/v1/goals/"+randomID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("expected 404 for unknown goal ID GET, got %d: %s", rec.Code, rec.Body.String())
	}

	// PATCH unknown ID
	body := strings.NewReader(`{"title":"New Title"}`)
	req = httptest.NewRequest(http.MethodPatch, "/api/v1/goals/"+randomID, body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("expected 404 for unknown goal ID PATCH, got %d: %s", rec.Code, rec.Body.String())
	}

	// DELETE unknown ID
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/goals/"+randomID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("expected 404 for unknown goal ID DELETE, got %d: %s", rec.Code, rec.Body.String())
	}
}
