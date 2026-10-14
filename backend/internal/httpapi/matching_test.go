package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/config"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/httpapi"
	"github.com/abshwabu/pair/backend/internal/matching"
)

type userContext struct {
	token  string
	userID string
	goalID string
}

func setupMatchingTestApp(t *testing.T) (http.Handler, *db.DB, *matching.Worker) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "matching_http_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	cfg := &config.Config{
		Port:   "8080",
		DBPath: dbPath,
	}

	matchingRepo := matching.NewRepository(database.Write, database.Read)
	worker := matching.NewWorker(matchingRepo)

	router := httpapi.NewRouterWithWorker(cfg, database, nil, worker)
	return router, database, worker
}

func createUserWithGoal(t *testing.T, router http.Handler, name, email, timezone, language, category, pace string) userContext {
	t.Helper()
	// 1. Register user
	regPayload := map[string]any{
		"name":     name,
		"email":    email,
		"password": "password123",
		"timezone": timezone,
	}
	body, _ := json.Marshal(regPayload)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to register user: %s", rec.Body.String())
	}

	var regResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &regResp)
	dataMap := regResp.Data.(map[string]any)
	token := dataMap["token"].(string)
	userMap := dataMap["user"].(map[string]any)
	userID := userMap["id"].(string)

	// Update language if different from 'en'
	if language != "en" {
		patchPayload := map[string]any{"language": language}
		patchBody, _ := json.Marshal(patchPayload)
		pReq := httptest.NewRequest(http.MethodPatch, "/api/v1/profile", bytes.NewReader(patchBody))
		pReq.Header.Set("Authorization", "Bearer "+token)
		pReq.Header.Set("Content-Type", "application/json")
		pRec := httptest.NewRecorder()
		router.ServeHTTP(pRec, pReq)
		if pRec.Code != http.StatusOK {
			t.Fatalf("failed to update language: %s", pRec.Body.String())
		}
	}

	// 2. Create goal
	goalPayload := map[string]any{
		"category":           category,
		"title":              "Goal for " + name,
		"target_description": "Target description",
		"pace":               pace,
	}
	goalBody, _ := json.Marshal(goalPayload)
	gReq := httptest.NewRequest(http.MethodPost, "/api/v1/goals", bytes.NewReader(goalBody))
	gReq.Header.Set("Authorization", "Bearer "+token)
	gReq.Header.Set("Content-Type", "application/json")
	gRec := httptest.NewRecorder()
	router.ServeHTTP(gRec, gReq)

	if gRec.Code != http.StatusCreated {
		t.Fatalf("failed to create goal: %s", gRec.Body.String())
	}

	var goalResp httpapi.Response
	_ = json.Unmarshal(gRec.Body.Bytes(), &goalResp)
	goalData := goalResp.Data.(map[string]any)
	goalID := goalData["id"].(string)

	return userContext{
		token:  token,
		userID: userID,
		goalID: goalID,
	}
}

func TestMatching_PairingHappyPath(t *testing.T) {
	router, database, worker := setupMatchingTestApp(t)
	defer database.Close()

	u1 := createUserWithGoal(t, router, "Alice", "alice@pair.test", "UTC", "en", "read", "steady")
	u2 := createUserWithGoal(t, router, "Bob", "bob@pair.test", "UTC", "en", "read", "steady")

	// 1. Alice creates matching request
	reqBody1 := []byte(`{"goal_id":"` + u1.goalID + `","timezone_tolerance_hours":3}`)
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(reqBody1))
	req1.Header.Set("Authorization", "Bearer "+u1.token)
	req1.Header.Set("Content-Type", "application/json")
	rec1 := httptest.NewRecorder()
	router.ServeHTTP(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("expected 201 for Alice request, got %d: %s", rec1.Code, rec1.Body.String())
	}

	var resp1 httpapi.Response
	_ = json.Unmarshal(rec1.Body.Bytes(), &resp1)
	req1Data := resp1.Data.(map[string]any)
	req1ID := req1Data["id"].(string)

	// 2. Bob creates matching request
	reqBody2 := []byte(`{"goal_id":"` + u2.goalID + `","timezone_tolerance_hours":3}`)
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(reqBody2))
	req2.Header.Set("Authorization", "Bearer "+u2.token)
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)

	if rec2.Code != http.StatusCreated {
		t.Fatalf("expected 201 for Bob request, got %d: %s", rec2.Code, rec2.Body.String())
	}

	var resp2 httpapi.Response
	_ = json.Unmarshal(rec2.Body.Bytes(), &resp2)
	req2Data := resp2.Data.(map[string]any)
	req2ID := req2Data["id"].(string)

	// Process matching request for Bob (triggers matching with Alice)
	if err := worker.ProcessRequest(context.Background(), req2ID); err != nil {
		t.Fatalf("worker failed to process request: %v", err)
	}

	// 3. Verify Alice's request is now matched
	getReq1 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+req1ID, nil)
	getReq1.Header.Set("Authorization", "Bearer "+u1.token)
	getRec1 := httptest.NewRecorder()
	router.ServeHTTP(getRec1, getReq1)

	if getRec1.Code != http.StatusOK {
		t.Fatalf("expected 200 for Alice GET request, got %d: %s", getRec1.Code, getRec1.Body.String())
	}

	var getResp1 httpapi.Response
	_ = json.Unmarshal(getRec1.Body.Bytes(), &getResp1)
	aliceMatch := getResp1.Data.(map[string]any)
	if aliceMatch["status"] != "matched" {
		t.Fatalf("expected Alice request to be 'matched', got %v", aliceMatch["status"])
	}
	pod1ID := aliceMatch["pod_id"].(string)

	// 4. Verify Bob's request is also matched with the exact same pod_id
	getReq2 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+req2ID, nil)
	getReq2.Header.Set("Authorization", "Bearer "+u2.token)
	getRec2 := httptest.NewRecorder()
	router.ServeHTTP(getRec2, getReq2)

	if getRec2.Code != http.StatusOK {
		t.Fatalf("expected 200 for Bob GET request, got %d: %s", getRec2.Code, getRec2.Body.String())
	}

	var getResp2 httpapi.Response
	_ = json.Unmarshal(getRec2.Body.Bytes(), &getResp2)
	bobMatch := getResp2.Data.(map[string]any)
	if bobMatch["status"] != "matched" {
		t.Fatalf("expected Bob request to be 'matched', got %v", bobMatch["status"])
	}
	pod2ID := bobMatch["pod_id"].(string)

	if pod1ID != pod2ID {
		t.Errorf("expected Alice and Bob to share pod_id %s, Bob got %s", pod1ID, pod2ID)
	}

	// Verify pod exists in database
	var podStatus string
	err := database.Read.QueryRow(`SELECT status FROM pods WHERE id = ?`, pod1ID).Scan(&podStatus)
	if err != nil {
		t.Fatalf("pod not found in DB: %v", err)
	}
	if podStatus != "active" {
		t.Errorf("expected pod status 'active', got %s", podStatus)
	}
}

func TestMatching_DifferentLanguageNotPaired(t *testing.T) {
	router, database, worker := setupMatchingTestApp(t)
	defer database.Close()

	uEnglish := createUserWithGoal(t, router, "English User", "en@pair.test", "UTC", "en", "read", "steady")
	uSpanish := createUserWithGoal(t, router, "Spanish User", "es@pair.test", "UTC", "es", "read", "steady")

	// English request
	bodyEN := []byte(`{"goal_id":"` + uEnglish.goalID + `","timezone_tolerance_hours":3}`)
	reqEN := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(bodyEN))
	reqEN.Header.Set("Authorization", "Bearer "+uEnglish.token)
	reqEN.Header.Set("Content-Type", "application/json")
	recEN := httptest.NewRecorder()
	router.ServeHTTP(recEN, reqEN)
	if recEN.Code != http.StatusCreated {
		t.Fatalf("failed to create EN request: %s", recEN.Body.String())
	}

	var respEN httpapi.Response
	_ = json.Unmarshal(recEN.Body.Bytes(), &respEN)
	enID := respEN.Data.(map[string]any)["id"].(string)

	// Spanish request
	bodyES := []byte(`{"goal_id":"` + uSpanish.goalID + `","timezone_tolerance_hours":3}`)
	reqES := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(bodyES))
	reqES.Header.Set("Authorization", "Bearer "+uSpanish.token)
	reqES.Header.Set("Content-Type", "application/json")
	recES := httptest.NewRecorder()
	router.ServeHTTP(recES, reqES)
	if recES.Code != http.StatusCreated {
		t.Fatalf("failed to create ES request: %s", recES.Body.String())
	}

	var respES httpapi.Response
	_ = json.Unmarshal(recES.Body.Bytes(), &respES)
	esID := respES.Data.(map[string]any)["id"].(string)

	// Process ES request
	_ = worker.ProcessRequest(context.Background(), esID)

	// Verify both requests remain 'open'
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+enID, nil)
	getReq.Header.Set("Authorization", "Bearer "+uEnglish.token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	var getResp httpapi.Response
	_ = json.Unmarshal(getRec.Body.Bytes(), &getResp)
	enStatus := getResp.Data.(map[string]any)["status"].(string)
	if enStatus != "open" {
		t.Errorf("expected English request to remain 'open', got %s", enStatus)
	}

	getReq2 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+esID, nil)
	getReq2.Header.Set("Authorization", "Bearer "+uSpanish.token)
	getRec2 := httptest.NewRecorder()
	router.ServeHTTP(getRec2, getReq2)

	var getResp2 httpapi.Response
	_ = json.Unmarshal(getRec2.Body.Bytes(), &getResp2)
	esStatus := getResp2.Data.(map[string]any)["status"].(string)
	if esStatus != "open" {
		t.Errorf("expected Spanish request to remain 'open', got %s", esStatus)
	}
}

func TestMatching_BlockedUsersNotPaired(t *testing.T) {
	router, database, worker := setupMatchingTestApp(t)
	defer database.Close()

	u1 := createUserWithGoal(t, router, "User 1", "u1@pair.test", "UTC", "en", "fitness", "steady")
	u2 := createUserWithGoal(t, router, "User 2", "u2@pair.test", "UTC", "en", "fitness", "steady")

	// User 1 blocks User 2 in blocks table
	now := time.Now().UTC().Format(time.RFC3339)
	_, err := database.Write.Exec(`
		INSERT INTO blocks (id, user_id, blocked_user_id, created_at)
		VALUES (?, ?, ?, ?);
	`, uuid.NewString(), u1.userID, u2.userID, now)
	if err != nil {
		t.Fatalf("failed to insert block record: %v", err)
	}

	// User 1 creates request
	body1 := []byte(`{"goal_id":"` + u1.goalID + `","timezone_tolerance_hours":3}`)
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(body1))
	req1.Header.Set("Authorization", "Bearer "+u1.token)
	req1.Header.Set("Content-Type", "application/json")
	rec1 := httptest.NewRecorder()
	router.ServeHTTP(rec1, req1)
	var resp1 httpapi.Response
	_ = json.Unmarshal(rec1.Body.Bytes(), &resp1)
	req1ID := resp1.Data.(map[string]any)["id"].(string)

	// User 2 creates request
	body2 := []byte(`{"goal_id":"` + u2.goalID + `","timezone_tolerance_hours":3}`)
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(body2))
	req2.Header.Set("Authorization", "Bearer "+u2.token)
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)
	var resp2 httpapi.Response
	_ = json.Unmarshal(rec2.Body.Bytes(), &resp2)
	req2ID := resp2.Data.(map[string]any)["id"].(string)

	// Process
	_ = worker.ProcessRequest(context.Background(), req2ID)

	// Verify both remain open because of block
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+req1ID, nil)
	getReq.Header.Set("Authorization", "Bearer "+u1.token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	var getResp httpapi.Response
	_ = json.Unmarshal(getRec.Body.Bytes(), &getResp)
	status1 := getResp.Data.(map[string]any)["status"].(string)
	if status1 != "open" {
		t.Errorf("expected blocked user request to remain 'open', got %s", status1)
	}
}

func TestMatching_Conflict_AlreadyOpenRequest(t *testing.T) {
	router, database, _ := setupMatchingTestApp(t)
	defer database.Close()

	u := createUserWithGoal(t, router, "Charlie", "charlie@pair.test", "UTC", "en", "habit", "steady")

	// 1. Create first request
	body := []byte(`{"goal_id":"` + u.goalID + `","timezone_tolerance_hours":3}`)
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(body))
	req1.Header.Set("Authorization", "Bearer "+u.token)
	req1.Header.Set("Content-Type", "application/json")
	rec1 := httptest.NewRecorder()
	router.ServeHTTP(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("first request failed: %s", rec1.Body.String())
	}

	// 2. Attempt second request while first is still open -> 409 Conflict
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(body))
	req2.Header.Set("Authorization", "Bearer "+u.token)
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)

	if rec2.Code != http.StatusConflict {
		t.Fatalf("expected 409 for duplicate open request, got %d: %s", rec2.Code, rec2.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec2.Body.Bytes(), &resp)
	if resp.Error == nil || resp.Error.Code != "ACTIVE_REQUEST_CONFLICT" {
		t.Errorf("expected ACTIVE_REQUEST_CONFLICT error code, got %+v", resp.Error)
	}
}

func TestMatching_Conflict_ActiveMemberOfActivePod(t *testing.T) {
	router, database, _ := setupMatchingTestApp(t)
	defer database.Close()

	u := createUserWithGoal(t, router, "Daisy", "daisy@pair.test", "UTC", "en", "watch", "relaxed")

	// Manually insert user into an active pod
	now := time.Now().UTC().Format(time.RFC3339)
	podID := uuid.NewString()
	_, err := database.Write.Exec(`
		INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at)
		VALUES (?, 'watch', 'active', 2, ?, ?);
	`, podID, now, now)
	if err != nil {
		t.Fatalf("failed to insert pod: %v", err)
	}

	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at, left_at)
		VALUES (?, ?, ?, ?, ?, NULL);
	`, uuid.NewString(), podID, u.userID, u.goalID, now)
	if err != nil {
		t.Fatalf("failed to insert pod member: %v", err)
	}

	// Attempt to create match request -> 409 Conflict
	body := []byte(`{"goal_id":"` + u.goalID + `","timezone_tolerance_hours":3}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+u.token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 for active pod member, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Error == nil || resp.Error.Code != "ACTIVE_POD_CONFLICT" {
		t.Errorf("expected ACTIVE_POD_CONFLICT error code, got %+v", resp.Error)
	}
}

func TestMatching_CancelRequest(t *testing.T) {
	router, database, _ := setupMatchingTestApp(t)
	defer database.Close()

	u := createUserWithGoal(t, router, "Evan", "evan@pair.test", "UTC", "en", "custom", "steady")

	// 1. Create request
	body := []byte(`{"goal_id":"` + u.goalID + `","timezone_tolerance_hours":3}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+u.token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	var createResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &createResp)
	reqID := createResp.Data.(map[string]any)["id"].(string)

	// 2. Cancel request
	delReq := httptest.NewRequest(http.MethodDelete, "/api/v1/matching/request/"+reqID, nil)
	delReq.Header.Set("Authorization", "Bearer "+u.token)
	delRec := httptest.NewRecorder()
	router.ServeHTTP(delRec, delReq)

	if delRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for cancel request, got %d: %s", delRec.Code, delRec.Body.String())
	}

	// 3. Verify status is 'cancelled'
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+reqID, nil)
	getReq.Header.Set("Authorization", "Bearer "+u.token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	var getResp httpapi.Response
	_ = json.Unmarshal(getRec.Body.Bytes(), &getResp)
	status := getResp.Data.(map[string]any)["status"].(string)
	if status != "cancelled" {
		t.Errorf("expected status 'cancelled', got %s", status)
	}
}

func TestMatching_Ownership(t *testing.T) {
	router, database, _ := setupMatchingTestApp(t)
	defer database.Close()

	u1 := createUserWithGoal(t, router, "User1", "u1@owner.test", "UTC", "en", "read", "steady")
	u2 := createUserWithGoal(t, router, "User2", "u2@owner.test", "UTC", "en", "read", "steady")

	// User 1 creates request
	body := []byte(`{"goal_id":"` + u1.goalID + `","timezone_tolerance_hours":3}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+u1.token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	var createResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &createResp)
	reqID := createResp.Data.(map[string]any)["id"].(string)

	// User 2 attempts GET User 1's request -> 403 Forbidden
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+reqID, nil)
	getReq.Header.Set("Authorization", "Bearer "+u2.token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	if getRec.Code != http.StatusForbidden {
		t.Errorf("expected 403 for non-owner GET, got %d: %s", getRec.Code, getRec.Body.String())
	}

	// User 2 attempts DELETE User 1's request -> 403 Forbidden
	delReq := httptest.NewRequest(http.MethodDelete, "/api/v1/matching/request/"+reqID, nil)
	delReq.Header.Set("Authorization", "Bearer "+u2.token)
	delRec := httptest.NewRecorder()
	router.ServeHTTP(delRec, delReq)

	if delRec.Code != http.StatusForbidden {
		t.Errorf("expected 403 for non-owner DELETE, got %d: %s", delRec.Code, delRec.Body.String())
	}
}
