package httpapi_test

import (
	"bytes"
	"context"
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

	// 3. Verify Alice's request is now in 'proposed' state
	getReq1 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+req1ID, nil)
	getReq1.Header.Set("Authorization", "Bearer "+u1.token)
	getRec1 := httptest.NewRecorder()
	router.ServeHTTP(getRec1, getReq1)

	if getRec1.Code != http.StatusOK {
		t.Fatalf("expected 200 for Alice GET request, got %d: %s", getRec1.Code, getRec1.Body.String())
	}

	var getResp1 httpapi.Response
	_ = json.Unmarshal(getRec1.Body.Bytes(), &getResp1)
	aliceState := getResp1.Data.(map[string]any)
	if aliceState["state"] != "proposed" {
		t.Fatalf("expected Alice state to be 'proposed', got %v", aliceState["state"])
	}

	propMap, ok := aliceState["proposal"].(map[string]any)
	if !ok || propMap == nil {
		t.Fatalf("expected proposal detail for Alice, got nil")
	}
	proposalID := propMap["id"].(string)
	if proposalID == "" {
		t.Fatalf("expected non-empty proposal ID")
	}
	if propMap["my_response"] != "pending" {
		t.Fatalf("expected Alice my_response 'pending', got %v", propMap["my_response"])
	}

	partnerMap := propMap["partner"].(map[string]any)
	if partnerMap["name"] != "Bob" {
		t.Errorf("expected partner name 'Bob', got %v", partnerMap["name"])
	}

	partnerGoal := propMap["partner_goal"].(map[string]any)
	if partnerGoal["title"] != "Goal for Bob" {
		t.Errorf("expected partner goal 'Goal for Bob', got %v", partnerGoal["title"])
	}

	// Also check Alice GET /matching/current and verify partner response NEVER leaks in JSON
	curReq1 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/current", nil)
	curReq1.Header.Set("Authorization", "Bearer "+u1.token)
	curRec1 := httptest.NewRecorder()
	router.ServeHTTP(curRec1, curReq1)
	if curRec1.Code != http.StatusOK {
		t.Fatalf("expected 200 for Alice GET current, got %d: %s", curRec1.Code, curRec1.Body.String())
	}
	rawJSON := curRec1.Body.String()
	if strings.Contains(rawJSON, "partner_response") || strings.Contains(rawJSON, "user_b_response") || strings.Contains(rawJSON, "user_a_response") {
		t.Errorf("partner response leaked in JSON: %s", rawJSON)
	}

	// 4. Verify Bob's request is also in 'proposed' state
	getReq2 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+req2ID, nil)
	getReq2.Header.Set("Authorization", "Bearer "+u2.token)
	getRec2 := httptest.NewRecorder()
	router.ServeHTTP(getRec2, getReq2)

	if getRec2.Code != http.StatusOK {
		t.Fatalf("expected 200 for Bob GET request, got %d: %s", getRec2.Code, getRec2.Body.String())
	}

	var getResp2 httpapi.Response
	_ = json.Unmarshal(getRec2.Body.Bytes(), &getResp2)
	bobState := getResp2.Data.(map[string]any)
	if bobState["state"] != "proposed" {
		t.Fatalf("expected Bob state to be 'proposed', got %v", bobState["state"])
	}

	// 5. Alice accepts proposal
	acceptReq1 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+proposalID+"/accept", nil)
	acceptReq1.Header.Set("Authorization", "Bearer "+u1.token)
	acceptRec1 := httptest.NewRecorder()
	router.ServeHTTP(acceptRec1, acceptReq1)
	if acceptRec1.Code != http.StatusOK {
		t.Fatalf("Alice accept failed: %s", acceptRec1.Body.String())
	}

	// Alice checks /matching/current: state still 'proposed', my_response is now 'accepted'
	curRec1AfterAccept := httptest.NewRecorder()
	router.ServeHTTP(curRec1AfterAccept, curReq1)
	var aliceCurResp httpapi.Response
	_ = json.Unmarshal(curRec1AfterAccept.Body.Bytes(), &aliceCurResp)
	aliceCurData := aliceCurResp.Data.(map[string]any)
	if aliceCurData["state"] != "proposed" {
		t.Errorf("expected Alice state still 'proposed' after 1st accept, got %v", aliceCurData["state"])
	}
	aliceProp := aliceCurData["proposal"].(map[string]any)
	if aliceProp["my_response"] != "accepted" {
		t.Errorf("expected Alice my_response 'accepted', got %v", aliceProp["my_response"])
	}

	// Bob checks /matching/current: state still 'proposed', my_response is 'pending' (Alice's accept is hidden!)
	curReq2 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/current", nil)
	curReq2.Header.Set("Authorization", "Bearer "+u2.token)
	curRec2 := httptest.NewRecorder()
	router.ServeHTTP(curRec2, curReq2)
	var bobCurResp httpapi.Response
	_ = json.Unmarshal(curRec2.Body.Bytes(), &bobCurResp)
	bobCurData := bobCurResp.Data.(map[string]any)
	if bobCurData["state"] != "proposed" {
		t.Errorf("expected Bob state still 'proposed', got %v", bobCurData["state"])
	}
	bobProp := bobCurData["proposal"].(map[string]any)
	if bobProp["my_response"] != "pending" {
		t.Errorf("expected Bob my_response 'pending', got %v", bobProp["my_response"])
	}

	// 6. Bob accepts proposal -> pod is created!
	acceptReq2 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+proposalID+"/accept", nil)
	acceptReq2.Header.Set("Authorization", "Bearer "+u2.token)
	acceptRec2 := httptest.NewRecorder()
	router.ServeHTTP(acceptRec2, acceptReq2)
	if acceptRec2.Code != http.StatusOK {
		t.Fatalf("Bob accept failed: %s", acceptRec2.Body.String())
	}

	// Both Alice and Bob now have state == 'matched' and non-nil pod_id
	finalAliceRec := httptest.NewRecorder()
	router.ServeHTTP(finalAliceRec, curReq1)
	var fAliceResp httpapi.Response
	_ = json.Unmarshal(finalAliceRec.Body.Bytes(), &fAliceResp)
	fAliceData := fAliceResp.Data.(map[string]any)
	if fAliceData["state"] != "matched" {
		t.Fatalf("expected Alice state 'matched', got %v", fAliceData["state"])
	}
	pod1ID := fAliceData["pod_id"].(string)

	finalBobRec := httptest.NewRecorder()
	router.ServeHTTP(finalBobRec, curReq2)
	var fBobResp httpapi.Response
	_ = json.Unmarshal(finalBobRec.Body.Bytes(), &fBobResp)
	fBobData := fBobResp.Data.(map[string]any)
	if fBobData["state"] != "matched" {
		t.Fatalf("expected Bob state 'matched', got %v", fBobData["state"])
	}
	pod2ID := fBobData["pod_id"].(string)

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

	// Verify pod members
	var memberCount int
	err = database.Read.QueryRow(`SELECT count(*) FROM pod_members WHERE pod_id = ? AND left_at IS NULL`, pod1ID).Scan(&memberCount)
	if err != nil || memberCount != 2 {
		t.Errorf("expected 2 active pod members, got %d (err: %v)", memberCount, err)
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

	// Verify both requests remain 'searching'
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+enID, nil)
	getReq.Header.Set("Authorization", "Bearer "+uEnglish.token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	var getResp httpapi.Response
	_ = json.Unmarshal(getRec.Body.Bytes(), &getResp)
	enState := getResp.Data.(map[string]any)["state"].(string)
	if enState != "searching" {
		t.Errorf("expected English request to remain 'searching', got %s", enState)
	}

	getReq2 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+esID, nil)
	getReq2.Header.Set("Authorization", "Bearer "+uSpanish.token)
	getRec2 := httptest.NewRecorder()
	router.ServeHTTP(getRec2, getReq2)

	var getResp2 httpapi.Response
	_ = json.Unmarshal(getRec2.Body.Bytes(), &getResp2)
	esState := getResp2.Data.(map[string]any)["state"].(string)
	if esState != "searching" {
		t.Errorf("expected Spanish request to remain 'searching', got %s", esState)
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

	// Verify both remain 'searching' because of block
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+req1ID, nil)
	getReq.Header.Set("Authorization", "Bearer "+u1.token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	var getResp httpapi.Response
	_ = json.Unmarshal(getRec.Body.Bytes(), &getResp)
	state1 := getResp.Data.(map[string]any)["state"].(string)
	if state1 != "searching" {
		t.Errorf("expected blocked user request to remain 'searching', got %s", state1)
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

	// 3. Verify state is 'none'
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/request/"+reqID, nil)
	getReq.Header.Set("Authorization", "Bearer "+u.token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	var getResp httpapi.Response
	_ = json.Unmarshal(getRec.Body.Bytes(), &getResp)
	state := getResp.Data.(map[string]any)["state"].(string)
	if state != "none" {
		t.Errorf("expected state 'none', got %s", state)
	}

	// GET /matching/current should also return state 'none'
	curReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/current", nil)
	curReq.Header.Set("Authorization", "Bearer "+u.token)
	curRec := httptest.NewRecorder()
	router.ServeHTTP(curRec, curReq)
	var curResp httpapi.Response
	_ = json.Unmarshal(curRec.Body.Bytes(), &curResp)
	curState := curResp.Data.(map[string]any)["state"].(string)
	if curState != "none" {
		t.Errorf("expected current state 'none', got %s", curState)
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

func TestMatching_ProposalAcceptanceEdgeCases(t *testing.T) {
	router, database, worker := setupMatchingTestApp(t)
	defer database.Close()

	u1 := createUserWithGoal(t, router, "User 1", "pa1@pair.test", "UTC", "en", "read", "steady")
	u2 := createUserWithGoal(t, router, "User 2", "pa2@pair.test", "UTC", "en", "read", "steady")
	u3 := createUserWithGoal(t, router, "User 3", "pa3@pair.test", "UTC", "en", "read", "steady")

	// Submit requests and pair
	b1 := []byte(`{"goal_id":"` + u1.goalID + `","timezone_tolerance_hours":3}`)
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(b1))
	req1.Header.Set("Authorization", "Bearer "+u1.token)
	rec1 := httptest.NewRecorder()
	router.ServeHTTP(rec1, req1)

	b2 := []byte(`{"goal_id":"` + u2.goalID + `","timezone_tolerance_hours":3}`)
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(b2))
	req2.Header.Set("Authorization", "Bearer "+u2.token)
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)

	var r2Resp httpapi.Response
	_ = json.Unmarshal(rec2.Body.Bytes(), &r2Resp)
	r2ID := r2Resp.Data.(map[string]any)["id"].(string)
	_ = worker.ProcessRequest(context.Background(), r2ID)

	// Fetch proposal ID
	curReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/current", nil)
	curReq.Header.Set("Authorization", "Bearer "+u1.token)
	curRec := httptest.NewRecorder()
	router.ServeHTTP(curRec, curReq)
	var curResp httpapi.Response
	_ = json.Unmarshal(curRec.Body.Bytes(), &curResp)
	propID := curResp.Data.(map[string]any)["proposal"].(map[string]any)["id"].(string)

	// 1. Non-participant (User 3) accepts -> 403 Forbidden
	nonPartReq := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+propID+"/accept", nil)
	nonPartReq.Header.Set("Authorization", "Bearer "+u3.token)
	nonPartRec := httptest.NewRecorder()
	router.ServeHTTP(nonPartRec, nonPartReq)
	if nonPartRec.Code != http.StatusForbidden {
		t.Errorf("expected 403 for non-participant accept, got %d: %s", nonPartRec.Code, nonPartRec.Body.String())
	}

	// 2. User 1 accepts -> 200 OK
	u1AcceptReq := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+propID+"/accept", nil)
	u1AcceptReq.Header.Set("Authorization", "Bearer "+u1.token)
	u1AcceptRec := httptest.NewRecorder()
	router.ServeHTTP(u1AcceptRec, u1AcceptReq)
	if u1AcceptRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for u1 accept, got %d: %s", u1AcceptRec.Code, u1AcceptRec.Body.String())
	}

	// 3. Idempotent accept: User 1 accepts AGAIN -> 200 OK
	u1DupAcceptReq := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+propID+"/accept", nil)
	u1DupAcceptReq.Header.Set("Authorization", "Bearer "+u1.token)
	u1DupAcceptRec := httptest.NewRecorder()
	router.ServeHTTP(u1DupAcceptRec, u1DupAcceptReq)
	if u1DupAcceptRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for duplicate accept, got %d: %s", u1DupAcceptRec.Code, u1DupAcceptRec.Body.String())
	}

	// 4. User 2 accepts -> proposal is resolved to matched
	u2AcceptReq := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+propID+"/accept", nil)
	u2AcceptReq.Header.Set("Authorization", "Bearer "+u2.token)
	u2AcceptRec := httptest.NewRecorder()
	router.ServeHTTP(u2AcceptRec, u2AcceptReq)
	if u2AcceptRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for u2 accept, got %d: %s", u2AcceptRec.Code, u2AcceptRec.Body.String())
	}

	// 5. Calling accept after proposal resolved -> 409 proposal_closed
	closedReq := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+propID+"/accept", nil)
	closedReq.Header.Set("Authorization", "Bearer "+u1.token)
	closedRec := httptest.NewRecorder()
	router.ServeHTTP(closedRec, closedReq)
	if closedRec.Code != http.StatusConflict {
		t.Errorf("expected 409 on closed proposal, got %d: %s", closedRec.Code, closedRec.Body.String())
	}
	var closedResp httpapi.Response
	_ = json.Unmarshal(closedRec.Body.Bytes(), &closedResp)
	if closedResp.Error == nil || closedResp.Error.Code != "proposal_closed" {
		t.Errorf("expected proposal_closed code, got %+v", closedResp.Error)
	}
}

func TestMatching_ProposalRejection(t *testing.T) {
	router, database, worker := setupMatchingTestApp(t)
	defer database.Close()

	u1 := createUserWithGoal(t, router, "User 1", "pr1@pair.test", "UTC", "en", "read", "steady")
	u2 := createUserWithGoal(t, router, "User 2", "pr2@pair.test", "UTC", "en", "read", "steady")
	u3 := createUserWithGoal(t, router, "User 3", "pr3@pair.test", "UTC", "en", "read", "steady")

	// Submit requests and pair
	b1 := []byte(`{"goal_id":"` + u1.goalID + `","timezone_tolerance_hours":3}`)
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(b1))
	req1.Header.Set("Authorization", "Bearer "+u1.token)
	rec1 := httptest.NewRecorder()
	router.ServeHTTP(rec1, req1)

	b2 := []byte(`{"goal_id":"` + u2.goalID + `","timezone_tolerance_hours":3}`)
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(b2))
	req2.Header.Set("Authorization", "Bearer "+u2.token)
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)

	var r2Resp httpapi.Response
	_ = json.Unmarshal(rec2.Body.Bytes(), &r2Resp)
	r2ID := r2Resp.Data.(map[string]any)["id"].(string)
	_ = worker.ProcessRequest(context.Background(), r2ID)

	// Fetch proposal ID
	curReq1 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/current", nil)
	curReq1.Header.Set("Authorization", "Bearer "+u1.token)
	curRec1 := httptest.NewRecorder()
	router.ServeHTTP(curRec1, curReq1)
	var curResp1 httpapi.Response
	_ = json.Unmarshal(curRec1.Body.Bytes(), &curResp1)
	propID := curResp1.Data.(map[string]any)["proposal"].(map[string]any)["id"].(string)

	// 1. Non-participant reject -> 403 Forbidden
	nonPartReq := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+propID+"/reject", nil)
	nonPartReq.Header.Set("Authorization", "Bearer "+u3.token)
	nonPartRec := httptest.NewRecorder()
	router.ServeHTTP(nonPartRec, nonPartReq)
	if nonPartRec.Code != http.StatusForbidden {
		t.Errorf("expected 403 for non-participant reject, got %d: %s", nonPartRec.Code, nonPartRec.Body.String())
	}

	// 2. User 1 rejects proposal
	rejReq := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+propID+"/reject", nil)
	rejReq.Header.Set("Authorization", "Bearer "+u1.token)
	rejRec := httptest.NewRecorder()
	router.ServeHTTP(rejRec, rejReq)
	if rejRec.Code != http.StatusOK {
		t.Fatalf("expected 200 on reject, got %d: %s", rejRec.Code, rejRec.Body.String())
	}

	// 3. User 1 GET /current -> state: 'searching', proposal: nil
	curRec1After := httptest.NewRecorder()
	router.ServeHTTP(curRec1After, curReq1)
	var after1Resp httpapi.Response
	_ = json.Unmarshal(curRec1After.Body.Bytes(), &after1Resp)
	after1Data := after1Resp.Data.(map[string]any)
	if after1Data["state"] != "searching" {
		t.Errorf("expected User 1 state 'searching' after reject, got %v", after1Data["state"])
	}
	if after1Data["proposal"] != nil {
		t.Errorf("expected User 1 proposal nil after reject, got %v", after1Data["proposal"])
	}

	// 4. User 2 GET /current -> state: 'searching', proposal: nil
	curReq2 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/current", nil)
	curReq2.Header.Set("Authorization", "Bearer "+u2.token)
	curRec2 := httptest.NewRecorder()
	router.ServeHTTP(curRec2, curReq2)
	var after2Resp httpapi.Response
	_ = json.Unmarshal(curRec2.Body.Bytes(), &after2Resp)
	after2Data := after2Resp.Data.(map[string]any)
	if after2Data["state"] != "searching" {
		t.Errorf("expected User 2 state 'searching' after reject, got %v", after2Data["state"])
	}
	if after2Data["proposal"] != nil {
		t.Errorf("expected User 2 proposal nil after reject, got %v", after2Data["proposal"])
	}

	// 5. Subsequent reject or accept attempt -> 409 proposal_closed
	dupRejReq := httptest.NewRequest(http.MethodPost, "/api/v1/matching/proposals/"+propID+"/reject", nil)
	dupRejReq.Header.Set("Authorization", "Bearer "+u2.token)
	dupRejRec := httptest.NewRecorder()
	router.ServeHTTP(dupRejRec, dupRejReq)
	if dupRejRec.Code != http.StatusConflict {
		t.Errorf("expected 409 for duplicate reject, got %d: %s", dupRejRec.Code, dupRejRec.Body.String())
	}

	// 6. Exclusion check: Process matching worker again -> they must NOT be paired together
	_ = worker.ProcessRequest(context.Background(), r2ID)
	curRec1Excl := httptest.NewRecorder()
	router.ServeHTTP(curRec1Excl, curReq1)
	var exclResp httpapi.Response
	_ = json.Unmarshal(curRec1Excl.Body.Bytes(), &exclResp)
	if exclResp.Data.(map[string]any)["state"] != "searching" {
		t.Errorf("expected users to NOT be paired again after rejection, got %v", exclResp.Data.(map[string]any)["state"])
	}
}

func TestMatching_CancelDuringProposed(t *testing.T) {
	router, _, worker := setupMatchingTestApp(t)

	u1 := createUserWithGoal(t, router, "User 1", "cdp1@pair.test", "UTC", "en", "read", "steady")
	u2 := createUserWithGoal(t, router, "User 2", "cdp2@pair.test", "UTC", "en", "read", "steady")

	// Submit requests and pair
	b1 := []byte(`{"goal_id":"` + u1.goalID + `","timezone_tolerance_hours":3}`)
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(b1))
	req1.Header.Set("Authorization", "Bearer "+u1.token)
	rec1 := httptest.NewRecorder()
	router.ServeHTTP(rec1, req1)
	var r1Resp httpapi.Response
	_ = json.Unmarshal(rec1.Body.Bytes(), &r1Resp)
	r1ID := r1Resp.Data.(map[string]any)["id"].(string)

	b2 := []byte(`{"goal_id":"` + u2.goalID + `","timezone_tolerance_hours":3}`)
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(b2))
	req2.Header.Set("Authorization", "Bearer "+u2.token)
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)
	var r2Resp httpapi.Response
	_ = json.Unmarshal(rec2.Body.Bytes(), &r2Resp)
	r2ID := r2Resp.Data.(map[string]any)["id"].(string)

	_ = worker.ProcessRequest(context.Background(), r2ID)

	// User 1 cancels their request while in proposed state
	delReq := httptest.NewRequest(http.MethodDelete, "/api/v1/matching/request/"+r1ID, nil)
	delReq.Header.Set("Authorization", "Bearer "+u1.token)
	delRec := httptest.NewRecorder()
	router.ServeHTTP(delRec, delReq)
	if delRec.Code != http.StatusOK {
		t.Fatalf("expected 200 on cancel request, got %d: %s", delRec.Code, delRec.Body.String())
	}

	// User 1's state is now 'none'
	curReq1 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/current", nil)
	curReq1.Header.Set("Authorization", "Bearer "+u1.token)
	curRec1 := httptest.NewRecorder()
	router.ServeHTTP(curRec1, curReq1)
	var curResp1 httpapi.Response
	_ = json.Unmarshal(curRec1.Body.Bytes(), &curResp1)
	if curResp1.Data.(map[string]any)["state"] != "none" {
		t.Errorf("expected User 1 state 'none', got %v", curResp1.Data.(map[string]any)["state"])
	}

	// User 2's state returns to 'searching'
	curReq2 := httptest.NewRequest(http.MethodGet, "/api/v1/matching/current", nil)
	curReq2.Header.Set("Authorization", "Bearer "+u2.token)
	curRec2 := httptest.NewRecorder()
	router.ServeHTTP(curRec2, curReq2)
	var curResp2 httpapi.Response
	_ = json.Unmarshal(curRec2.Body.Bytes(), &curResp2)
	if curResp2.Data.(map[string]any)["state"] != "searching" {
		t.Errorf("expected User 2 state 'searching', got %v", curResp2.Data.(map[string]any)["state"])
	}
}

func TestMatching_GetCurrent_States(t *testing.T) {
	router, _, _ := setupMatchingTestApp(t)

	u := createUserWithGoal(t, router, "Solo User", "solo@pair.test", "UTC", "en", "read", "steady")

	// 1. Initial state without any request -> 'none'
	curReq := httptest.NewRequest(http.MethodGet, "/api/v1/matching/current", nil)
	curReq.Header.Set("Authorization", "Bearer "+u.token)
	curRec := httptest.NewRecorder()
	router.ServeHTTP(curRec, curReq)

	if curRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for current state, got %d: %s", curRec.Code, curRec.Body.String())
	}
	var curResp httpapi.Response
	_ = json.Unmarshal(curRec.Body.Bytes(), &curResp)
	curData := curResp.Data.(map[string]any)
	if curData["state"] != "none" {
		t.Errorf("expected state 'none', got %v", curData["state"])
	}
	if curData["request_id"] != nil {
		t.Errorf("expected request_id nil, got %v", curData["request_id"])
	}

	// 2. Submit request -> state is 'searching'
	body := []byte(`{"goal_id":"` + u.goalID + `","timezone_tolerance_hours":3}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/matching/request", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+u.token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create request: %s", rec.Body.String())
	}

	curRec2 := httptest.NewRecorder()
	router.ServeHTTP(curRec2, curReq)
	var curResp2 httpapi.Response
	_ = json.Unmarshal(curRec2.Body.Bytes(), &curResp2)
	curData2 := curResp2.Data.(map[string]any)
	if curData2["state"] != "searching" {
		t.Errorf("expected state 'searching', got %v", curData2["state"])
	}
	if curData2["request_id"] == nil {
		t.Errorf("expected non-nil request_id")
	}
}
