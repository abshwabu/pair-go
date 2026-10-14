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

func setupTodosTestApp(t *testing.T) (http.Handler, *db.DB) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "todos_http_test.db")

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

func registerUser(t *testing.T, router http.Handler, name, email string) (string, string) {
	t.Helper()
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

	return token, userID
}

func createPodWithMembers(t *testing.T, database *db.DB, u1ID, u2ID string) string {
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

	g1ID := uuid.NewString()
	_, _ = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, 'read', 'Goal 1', 'Desc', 'steady', ?, ?);
	`, g1ID, u1ID, now, now)

	g2ID := uuid.NewString()
	_, _ = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, 'read', 'Goal 2', 'Desc', 'steady', ?, ?);
	`, g2ID, u2ID, now, now)

	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, u1ID, g1ID, now)
	if err != nil {
		t.Fatalf("failed to insert member 1: %v", err)
	}

	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, u2ID, g2ID, now)
	if err != nil {
		t.Fatalf("failed to insert member 2: %v", err)
	}

	return podID
}

func TestTodosAPI_Create(t *testing.T) {
	router, database := setupTodosTestApp(t)
	defer database.Close()

	u1Token, u1ID := registerUser(t, router, "Alice", "alice@example.com")
	_, u2ID := registerUser(t, router, "Bob", "bob@example.com")
	u3Token, _ := registerUser(t, router, "Charlie", "charlie@example.com")

	podID := createPodWithMembers(t, database, u1ID, u2ID)

	// Case 1: Active member creates shared todo (no assigned_to) -> 201 Created
	todoBody := map[string]any{
		"title":    "Finish Chapter 3",
		"notes":    "Read carefully",
		"due_date": "2026-10-25",
	}
	body, _ := json.Marshal(todoBody)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/todos", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	dataMap := resp.Data.(map[string]any)
	if dataMap["title"] != "Finish Chapter 3" {
		t.Errorf("expected title 'Finish Chapter 3', got %v", dataMap["title"])
	}
	if dataMap["assigned_to"] != nil {
		t.Errorf("expected assigned_to to be null for shared todo, got %v", dataMap["assigned_to"])
	}
	if dataMap["is_done"] != false {
		t.Errorf("expected is_done false, got %v", dataMap["is_done"])
	}

	// Case 2: Member creates todo assigned to partner (Bob) -> 201 Created
	todoBody2 := map[string]any{
		"title":       "Bob's turn to read",
		"assigned_to": u2ID,
	}
	body2, _ := json.Marshal(todoBody2)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/todos", bytes.NewReader(body2))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp2 httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp2)
	dataMap2 := resp2.Data.(map[string]any)
	if dataMap2["assigned_to"] != u2ID {
		t.Errorf("expected assigned_to %s, got %v", u2ID, dataMap2["assigned_to"])
	}

	// Case 3: Assigning to non-member (Charlie) -> 400 Bad Request
	_, u3ID := registerUser(t, router, "Dave", "dave@example.com")
	badAssignBody := map[string]any{
		"title":       "Invalid Assign",
		"assigned_to": u3ID,
	}
	badBody, _ := json.Marshal(badAssignBody)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/todos", bytes.NewReader(badBody))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 Bad Request when assigning to non-member, got %d: %s", rec.Code, rec.Body.String())
	}

	// Case 4: Missing title -> 400 Bad Request
	noTitleBody := map[string]any{"title": "   "}
	ntb, _ := json.Marshal(noTitleBody)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/todos", bytes.NewReader(ntb))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for empty title, got %d", rec.Code)
	}

	// Case 5: Invalid due_date format -> 400 Bad Request
	badDateBody := map[string]any{"title": "Valid", "due_date": "2026/10/25"}
	bdb, _ := json.Marshal(badDateBody)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/todos", bytes.NewReader(bdb))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for invalid due_date, got %d", rec.Code)
	}

	// Case 6: Non-member (Charlie) attempts to create todo in pod -> 403 Forbidden
	req = httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/todos", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+u3Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden for non-member, got %d", rec.Code)
	}
}

func TestTodosAPI_List_FiltersAndSorting(t *testing.T) {
	router, database := setupTodosTestApp(t)
	defer database.Close()

	u1Token, u1ID := registerUser(t, router, "Alice", "alice@example.com")
	u2Token, u2ID := registerUser(t, router, "Bob", "bob@example.com")
	u3Token, _ := registerUser(t, router, "Charlie", "charlie@example.com")

	podID := createPodWithMembers(t, database, u1ID, u2ID)

	// Helper to create todo via HTTP
	createHTTPTodo := func(title string, assignedTo *string, dueDate *string, isDone bool) string {
		payload := map[string]any{"title": title}
		if assignedTo != nil {
			payload["assigned_to"] = *assignedTo
		}
		if dueDate != nil {
			payload["due_date"] = *dueDate
		}
		b, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/todos", bytes.NewReader(b))
		req.Header.Set("Authorization", "Bearer "+u1Token)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		var resp httpapi.Response
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		tID := resp.Data.(map[string]any)["id"].(string)

		if isDone {
			patchPayload := map[string]any{"is_done": true}
			pb, _ := json.Marshal(patchPayload)
			pReq := httptest.NewRequest(http.MethodPatch, "/api/v1/pods/"+podID+"/todos/"+tID, bytes.NewReader(pb))
			pReq.Header.Set("Authorization", "Bearer "+u1Token)
			pReq.Header.Set("Content-Type", "application/json")
			pRec := httptest.NewRecorder()
			router.ServeHTTP(pRec, pReq)
		}
		return tID
	}

	d1 := "2026-10-15"
	d2 := "2026-10-25"
	dOld := "2026-10-01"

	createHTTPTodo("Task A", &u1ID, &d2, false)  // open, u1, 10-25
	createHTTPTodo("Task B", nil, &d1, false)    // open, shared, 10-15
	createHTTPTodo("Task C", &u2ID, nil, false)  // open, u2, no due date
	createHTTPTodo("Task D", &u1ID, &dOld, true) // done, u1, 10-01

	// 1. Filter: assigned_to=shared
	req := httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID+"/todos?assigned_to=shared", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var respShared httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &respShared)
	sharedItems := respShared.Data.([]any)
	if len(sharedItems) != 1 || sharedItems[0].(map[string]any)["title"] != "Task B" {
		t.Errorf("expected only Task B for shared filter, got %v", sharedItems)
	}

	// 2. Filter: assigned_to=u1ID
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID+"/todos?assigned_to="+u1ID, nil)
	req.Header.Set("Authorization", "Bearer "+u2Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	var respU1 httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &respU1)
	u1Items := respU1.Data.([]any)
	if len(u1Items) != 2 {
		t.Errorf("expected 2 items for u1, got %d", len(u1Items))
	}

	// 3. Filter: is_done=false
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID+"/todos?is_done=false", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	var respOpen httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &respOpen)
	openItems := respOpen.Data.([]any)
	if len(openItems) != 3 {
		t.Errorf("expected 3 open items, got %d", len(openItems))
	}

	// 4. Default sorting: open first, then due_date (nulls last), then created_at
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID+"/todos", nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	var respDefault httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &respDefault)
	defaultItems := respDefault.Data.([]any)
	if len(defaultItems) != 4 {
		t.Fatalf("expected 4 items, got %d", len(defaultItems))
	}
	// Task B (due 10-15), Task A (due 10-25), Task C (due null), Task D (done)
	if defaultItems[0].(map[string]any)["title"] != "Task B" {
		t.Errorf("expected 1st item to be Task B, got %v", defaultItems[0])
	}
	if defaultItems[1].(map[string]any)["title"] != "Task A" {
		t.Errorf("expected 2nd item to be Task A, got %v", defaultItems[1])
	}
	if defaultItems[2].(map[string]any)["title"] != "Task C" {
		t.Errorf("expected 3rd item to be Task C, got %v", defaultItems[2])
	}
	if defaultItems[3].(map[string]any)["title"] != "Task D" {
		t.Errorf("expected 4th item to be Task D, got %v", defaultItems[3])
	}

	// 5. Non-member (Charlie) listing todos -> 403 Forbidden
	req = httptest.NewRequest(http.MethodGet, "/api/v1/pods/"+podID+"/todos", nil)
	req.Header.Set("Authorization", "Bearer "+u3Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden for non-member, got %d", rec.Code)
	}
}

func TestTodosAPI_Patch_CompletedAtToggleAndCrossPod(t *testing.T) {
	router, database := setupTodosTestApp(t)
	defer database.Close()

	u1Token, u1ID := registerUser(t, router, "Alice", "alice@example.com")
	_, u2ID := registerUser(t, router, "Bob", "bob@example.com")

	pod1 := createPodWithMembers(t, database, u1ID, u2ID)
	pod2 := createPodWithMembers(t, database, u1ID, u2ID)

	// Create todo in pod1
	createPayload := map[string]any{
		"title":    "Toggle Test",
		"due_date": "2026-10-30",
	}
	cb, _ := json.Marshal(createPayload)
	cReq := httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+pod1+"/todos", bytes.NewReader(cb))
	cReq.Header.Set("Authorization", "Bearer "+u1Token)
	cReq.Header.Set("Content-Type", "application/json")
	cRec := httptest.NewRecorder()
	router.ServeHTTP(cRec, cReq)
	var cResp httpapi.Response
	_ = json.Unmarshal(cRec.Body.Bytes(), &cResp)
	todoID := cResp.Data.(map[string]any)["id"].(string)

	// 1. Toggle is_done to true -> completed_at must be populated
	patch1 := map[string]any{"is_done": true}
	p1b, _ := json.Marshal(patch1)
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/pods/"+pod1+"/todos/"+todoID, bytes.NewReader(p1b))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp1 httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp1)
	data1 := resp1.Data.(map[string]any)
	if data1["is_done"] != true {
		t.Errorf("expected is_done true")
	}
	if data1["completed_at"] == nil {
		t.Errorf("expected completed_at non-null when is_done is toggled true")
	}

	// 2. Toggle is_done to false -> completed_at must be null
	patch2 := map[string]any{"is_done": false}
	p2b, _ := json.Marshal(patch2)
	req = httptest.NewRequest(http.MethodPatch, "/api/v1/pods/"+pod1+"/todos/"+todoID, bytes.NewReader(p2b))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp2 httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp2)
	data2 := resp2.Data.(map[string]any)
	if data2["is_done"] != false {
		t.Errorf("expected is_done false")
	}
	if data2["completed_at"] != nil {
		t.Errorf("expected completed_at null when is_done is toggled false")
	}

	// 3. Partial update fields (title, assigned_to, clear due_date)
	patch3 := map[string]any{
		"title":       "Updated Title",
		"assigned_to": u2ID,
		"due_date":    nil,
	}
	p3b, _ := json.Marshal(patch3)
	req = httptest.NewRequest(http.MethodPatch, "/api/v1/pods/"+pod1+"/todos/"+todoID, bytes.NewReader(p3b))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp3 httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp3)
	data3 := resp3.Data.(map[string]any)
	if data3["title"] != "Updated Title" {
		t.Errorf("expected updated title, got %v", data3["title"])
	}
	if data3["assigned_to"] != u2ID {
		t.Errorf("expected assigned_to %s, got %v", u2ID, data3["assigned_to"])
	}
	if data3["due_date"] != nil {
		t.Errorf("expected due_date null, got %v", data3["due_date"])
	}

	// 4. Cross-pod access: attempting to patch pod1's todo under pod2 URL -> 404 Not Found
	req = httptest.NewRequest(http.MethodPatch, "/api/v1/pods/"+pod2+"/todos/"+todoID, bytes.NewReader(p1b))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("expected 404 Not Found for cross-pod todo update, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestTodosAPI_Delete_Authorization(t *testing.T) {
	router, database := setupTodosTestApp(t)
	defer database.Close()

	u1Token, u1ID := registerUser(t, router, "Alice", "alice@example.com")
	u2Token, u2ID := registerUser(t, router, "Bob", "bob@example.com")

	podID := createPodWithMembers(t, database, u1ID, u2ID)

	// Helper to create todo
	createTodo := func(title string, assignedTo *string) string {
		p := map[string]any{"title": title}
		if assignedTo != nil {
			p["assigned_to"] = *assignedTo
		}
		b, _ := json.Marshal(p)
		req := httptest.NewRequest(http.MethodPost, "/api/v1/pods/"+podID+"/todos", bytes.NewReader(b))
		req.Header.Set("Authorization", "Bearer "+u1Token)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		var resp httpapi.Response
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		return resp.Data.(map[string]any)["id"].(string)
	}

	// 1. Todo created by Alice, assigned to Alice
	aliceAssignedTodoID := createTodo("Alice Only", &u1ID)

	// Bob attempts to delete Alice's assigned todo -> 403 Forbidden
	req := httptest.NewRequest(http.MethodDelete, "/api/v1/pods/"+podID+"/todos/"+aliceAssignedTodoID, nil)
	req.Header.Set("Authorization", "Bearer "+u2Token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden when Bob deletes Alice's assigned todo, got %d", rec.Code)
	}

	// 2. Shared todo created by Alice (assigned_to: null)
	sharedTodoID := createTodo("Shared Book", nil)

	// Bob attempts to delete shared todo -> 200 OK!
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/pods/"+podID+"/todos/"+sharedTodoID, nil)
	req.Header.Set("Authorization", "Bearer "+u2Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK when Bob deletes shared todo, got %d: %s", rec.Code, rec.Body.String())
	}

	// 3. Creator Alice deletes her assigned todo -> 200 OK!
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/pods/"+podID+"/todos/"+aliceAssignedTodoID, nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK when creator Alice deletes her todo, got %d: %s", rec.Code, rec.Body.String())
	}

	// 4. Deleting already deleted todo -> 404 Not Found
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/pods/"+podID+"/todos/"+aliceAssignedTodoID, nil)
	req.Header.Set("Authorization", "Bearer "+u1Token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("expected 404 Not Found for already deleted todo, got %d", rec.Code)
	}
}
