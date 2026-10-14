package httpapi_test

import (
	"bytes"
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
)

func setupPodsTestApp(t *testing.T) (http.Handler, *db.DB) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "pods_http_test.db")

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

func registerUserAndGoal(t *testing.T, router http.Handler, name, email string) (string, string, string) {
	t.Helper()
	// Register user
	regPayload := map[string]any{
		"name":     name,
		"email":    email,
		"password": "password123",
		"timezone": "UTC",
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

	// Create goal
	goalPayload := map[string]any{
		"category":           "read",
		"title":              "Read with " + name,
		"target_description": "Read daily",
		"pace":               "steady",
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
	gData := goalResp.Data.(map[string]any)
	goalID := gData["id"].(string)

	return token, userID, goalID
}

func createTestPodInDB(t *testing.T, database *db.DB, user1ID, goal1ID, user2ID, goal2ID string) string {
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

	_, err = database.Write.Exec(`
		INSERT INTO streaks (id, pod_id, current_streak, best_streak, last_check_in_date, updated_at)
		VALUES (?, ?, 3, 7, '2026-10-14', ?);
	`, uuid.NewString(), podID, now)
	if err != nil {
		t.Fatalf("failed to insert streak: %v", err)
	}

	return podID
}

func TestPodsAPI_List(t *testing.T) {
	router, database := setupPodsTestApp(t)
	defer database.Close()

	u1Token, u1ID, g1ID := registerUserAndGoal(t, router, "User One", "user1@example.com")
	u2Token, u2ID, g2ID := registerUserAndGoal(t, router, "User Two", "user2@example.com")
	u3Token, _, _ := registerUserAndGoal(t, router, "User Three", "user3@example.com")

	podID := createTestPodInDB(t, database, u1ID, g1ID, u2ID, g2ID)

	// Case 1: Unauthenticated request -> 401
	req := httptest.NewRequest(http.MethodGet, "/api/v1/pods", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for unauthenticated request, got %d", rec.Code)
	}

	// Case 2: Active member (User One) lists pods -> returns array with 1 pod
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse JSON response: %v", err)
	}
	podList, ok := resp.Data.([]any)
	if !ok || len(podList) != 1 {
		t.Fatalf("expected 1 pod in list, got %v", resp.Data)
	}
	podMap := podList[0].(map[string]any)
	if podMap["id"] != podID {
		t.Errorf("expected pod ID %s, got %v", podID, podMap["id"])
	}
	if podMap["status"] != "active" {
		t.Errorf("expected status active, got %v", podMap["status"])
	}

	// Case 3: User Three has no pods -> returns empty array
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods", nil)
	req.Header.Set("Authorization", "Bearer "+u3Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp3 httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp3)
	podList3, ok := resp3.Data.([]any)
	if !ok || len(podList3) != 0 {
		t.Fatalf("expected 0 pods for User Three, got %v", resp3.Data)
	}

	// Case 4: User Two also sees the pod
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods", nil)
	req.Header.Set("Authorization", "Bearer "+u2Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPodsAPI_GetByID(t *testing.T) {
	router, database := setupPodsTestApp(t)
	defer database.Close()

	u1Token, u1ID, g1ID := registerUserAndGoal(t, router, "Alice", "alice@example.com")
	_, u2ID, g2ID := registerUserAndGoal(t, router, "Bob", "bob@example.com")
	u3Token, _, _ := registerUserAndGoal(t, router, "Charlie", "charlie@example.com")

	podID := createTestPodInDB(t, database, u1ID, g1ID, u2ID, g2ID)

	// Case 1: Active member views pod -> 200 OK with members & streak
	req := httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID, nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	podData, ok := resp.Data.(map[string]any)
	if !ok {
		t.Fatalf("expected object data, got %v", resp.Data)
	}
	if podData["id"] != podID {
		t.Errorf("expected pod ID %s, got %v", podID, podData["id"])
	}
	if podData["status"] != "active" {
		t.Errorf("expected status active, got %v", podData["status"])
	}

	// Verify members
	members, ok := podData["members"].([]any)
	if !ok || len(members) != 2 {
		t.Fatalf("expected 2 members, got %v", podData["members"])
	}

	// Verify streak
	streak, ok := podData["streak"].(map[string]any)
	if !ok {
		t.Fatalf("expected streak object, got %v", podData["streak"])
	}
	if streak["current_streak"].(float64) != 3 {
		t.Errorf("expected current streak 3, got %v", streak["current_streak"])
	}
	if streak["best_streak"].(float64) != 7 {
		t.Errorf("expected best streak 7, got %v", streak["best_streak"])
	}

	// Case 2: Non-member (Charlie) views pod -> 403 Forbidden
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID, nil)
	req.Header.Set("Authorization", "Bearer "+u3Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden for non-member, got %d: %s", rec.Code, rec.Body.String())
	}

	// Case 3: Unknown pod ID -> 404 Not Found
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods/unknown-pod-id", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("expected 404 Not Found for unknown pod, got %d: %s", rec.Code, rec.Body.String())
	}

	// Case 4: Unauthenticated -> 401 Unauthorized
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID, nil)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized, got %d", rec.Code)
	}
}

func TestPodsAPI_Leave(t *testing.T) {
	router, database := setupPodsTestApp(t)
	defer database.Close()

	u1Token, u1ID, g1ID := registerUserAndGoal(t, router, "Alice", "alice@example.com")
	u2Token, u2ID, g2ID := registerUserAndGoal(t, router, "Bob", "bob@example.com")
	u3Token, _, _ := registerUserAndGoal(t, router, "Charlie", "charlie@example.com")

	podID := createTestPodInDB(t, database, u1ID, g1ID, u2ID, g2ID)

	// Case 1: Non-member (Charlie) attempts to leave -> 403 Forbidden
	req := httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/leave", nil)
	req.Header.Set("Authorization", "Bearer "+u3Token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden for non-member leaving, got %d: %s", rec.Code, rec.Body.String())
	}

	// Case 2: Leaving non-existent pod -> 404 Not Found
	req = httptest.NewRequest(http.MethodPost, "/api/v1/pods/unknown-pod-id/leave", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("expected 404 Not Found for non-existent pod, got %d: %s", rec.Code, rec.Body.String())
	}

	// Case 3: Active member (Alice) leaves pod -> 200 OK
	req = httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/leave", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on leaving pod, got %d: %s", rec.Code, rec.Body.String())
	}

	var leaveResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &leaveResp)
	leaveData := leaveResp.Data.(map[string]any)
	if leaveData["message"] != "left pod successfully" {
		t.Errorf("unexpected message: %v", leaveData["message"])
	}

	// Case 4: Since remaining active members < 2, pod status must now be 'dissolved' in DB
	var podStatus string
	err := database.Read.QueryRow("SELECT status FROM pods WHERE id = ?;", podID).Scan(&podStatus)
	if err != nil {
		t.Fatalf("failed to query pod status: %v", err)
	}
	if podStatus != "dissolved" {
		t.Errorf("expected pod status dissolved, got %s", podStatus)
	}

	// Case 5: Alice (who left) can NO LONGER view the pod -> 403 Forbidden
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID, nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden for user who left, got %d: %s", rec.Code, rec.Body.String())
	}

	// Case 6: Alice (who left) can NO LONGER leave again -> 403 Forbidden
	req = httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/leave", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden for user trying to leave again, got %d: %s", rec.Code, rec.Body.String())
	}

	// Case 7: The pod is no longer returned in Alice's GET /api/v1/pods list
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}
	var alicePodsResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &alicePodsResp)
	alicePods := alicePodsResp.Data.([]any)
	if len(alicePods) != 0 {
		t.Errorf("expected 0 active pods for Alice after leaving, got %d", len(alicePods))
	}

	// Case 8: Bob (the other member) can still view the pod
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID, nil)
	req.Header.Set("Authorization", "Bearer "+u2Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("expected 200 OK for remaining member, got %d: %s", rec.Code, rec.Body.String())
	}
}
