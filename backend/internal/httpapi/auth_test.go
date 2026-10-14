package httpapi_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/abshwabu/pair/backend/internal/config"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/httpapi"
)

func setupTestRouter(t *testing.T) (http.Handler, *db.DB) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "auth_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	cfg := &config.Config{
		Port:   "8080",
		DBPath: dbPath,
	}

	router := httpapi.NewRouter(cfg, database)
	return router, database
}

func parseResponse(t *testing.T, rec *httptest.ResponseRecorder) httpapi.Response {
	t.Helper()
	var resp httpapi.Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode JSON response %q: %v", rec.Body.String(), err)
	}
	return resp
}

func TestAuth_RegisterSuccess(t *testing.T) {
	router, database := setupTestRouter(t)
	defer database.Close()

	payload := map[string]any{
		"name":     "Alice Tester",
		"email":    "alice@example.com",
		"password": "supersecretpassword",
		"timezone": "America/New_York",
	}
	body, _ := json.Marshal(payload)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	resp := parseResponse(t, rec)
	if resp.Error != nil {
		t.Fatalf("expected nil error, got %+v", resp.Error)
	}

	dataMap, ok := resp.Data.(map[string]any)
	if !ok {
		t.Fatalf("expected data map, got %T", resp.Data)
	}

	token, ok := dataMap["token"].(string)
	if !ok || token == "" {
		t.Errorf("expected non-empty token string, got %v", dataMap["token"])
	}

	userMap, ok := dataMap["user"].(map[string]any)
	if !ok {
		t.Fatalf("expected user map, got %T", dataMap["user"])
	}

	if userMap["name"] != "Alice Tester" {
		t.Errorf("expected user.name Alice Tester, got %v", userMap["name"])
	}
	if userMap["email"] != "alice@example.com" {
		t.Errorf("expected user.email alice@example.com, got %v", userMap["email"])
	}
	if userMap["timezone"] != "America/New_York" {
		t.Errorf("expected user.timezone America/New_York, got %v", userMap["timezone"])
	}
	if _, exists := userMap["password_hash"]; exists {
		t.Errorf("password_hash must never be exposed in JSON response")
	}
}

func TestAuth_RegisterValidationErrors(t *testing.T) {
	router, database := setupTestRouter(t)
	defer database.Close()

	tests := []struct {
		name        string
		payload     map[string]any
		expectedErr string
	}{
		{
			name: "missing name",
			payload: map[string]any{
				"name":     "  ",
				"email":    "alice@example.com",
				"password": "password123",
				"timezone": "UTC",
			},
			expectedErr: "name is required",
		},
		{
			name: "invalid email format",
			payload: map[string]any{
				"name":     "Alice",
				"email":    "not-an-email",
				"password": "password123",
				"timezone": "UTC",
			},
			expectedErr: "invalid email address format",
		},
		{
			name: "short password",
			payload: map[string]any{
				"name":     "Alice",
				"email":    "alice@example.com",
				"password": "short",
				"timezone": "UTC",
			},
			expectedErr: "password must be at least 8 characters long",
		},
		{
			name: "invalid timezone",
			payload: map[string]any{
				"name":     "Alice",
				"email":    "alice@example.com",
				"password": "password123",
				"timezone": "Mars/Olympus_Mons",
			},
			expectedErr: "invalid IANA timezone name",
		},
		{
			name: "unknown field rejected",
			payload: map[string]any{
				"name":      "Alice",
				"email":     "alice@example.com",
				"password":  "password123",
				"timezone":  "UTC",
				"is_hacker": true,
			},
			expectedErr: "unknown field",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			body, _ := json.Marshal(tc.payload)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()

			router.ServeHTTP(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected status 400, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			resp := parseResponse(t, rec)
			if resp.Error == nil {
				t.Fatalf("expected error object, got nil")
			}
			if resp.Error.Code != "VALIDATION_ERROR" {
				t.Errorf("expected error code VALIDATION_ERROR, got %s", resp.Error.Code)
			}
			if !strings.Contains(resp.Error.Message, tc.expectedErr) {
				t.Errorf("expected error message to contain %q, got %q", tc.expectedErr, resp.Error.Message)
			}
		})
	}
}

func TestAuth_RegisterDuplicateEmailRejected(t *testing.T) {
	router, database := setupTestRouter(t)
	defer database.Close()

	payload := map[string]any{
		"name":     "Alice Original",
		"email":    "alice@example.com",
		"password": "password123",
		"timezone": "UTC",
	}
	body, _ := json.Marshal(payload)

	// First registration
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	req1.Header.Set("Content-Type", "application/json")
	rec1 := httptest.NewRecorder()
	router.ServeHTTP(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("first registration failed: %d, body: %s", rec1.Code, rec1.Body.String())
	}

	// Second registration with case variation
	dupPayload := map[string]any{
		"name":     "Alice Copy",
		"email":    "ALICE@example.com",
		"password": "password456",
		"timezone": "UTC",
	}
	dupBody, _ := json.Marshal(dupPayload)

	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(dupBody))
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)

	if rec2.Code != http.StatusConflict {
		t.Fatalf("expected status 409 for duplicate email, got %d. Body: %s", rec2.Code, rec2.Body.String())
	}

	resp2 := parseResponse(t, rec2)
	if resp2.Error == nil || resp2.Error.Code != "EMAIL_EXISTS" {
		t.Errorf("expected error code EMAIL_EXISTS, got %+v", resp2.Error)
	}
}

func TestAuth_LoginSuccessAndWrongPassword(t *testing.T) {
	router, database := setupTestRouter(t)
	defer database.Close()

	// Register user first
	regPayload := map[string]any{
		"name":     "Bob",
		"email":    "bob@example.com",
		"password": "correctpassword",
		"timezone": "Europe/London",
	}
	regBody, _ := json.Marshal(regPayload)
	regReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(regBody))
	regReq.Header.Set("Content-Type", "application/json")
	regRec := httptest.NewRecorder()
	router.ServeHTTP(regRec, regReq)

	if regRec.Code != http.StatusCreated {
		t.Fatalf("registration failed: %s", regRec.Body.String())
	}

	// 1. Wrong password rejected
	wrongPayload := map[string]any{
		"email":    "bob@example.com",
		"password": "wrongpassword123",
	}
	wrongBody, _ := json.Marshal(wrongPayload)
	wrongReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(wrongBody))
	wrongReq.Header.Set("Content-Type", "application/json")
	wrongRec := httptest.NewRecorder()
	router.ServeHTTP(wrongRec, wrongReq)

	if wrongRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401 for wrong password, got %d", wrongRec.Code)
	}
	wrongResp := parseResponse(t, wrongRec)
	if wrongResp.Error == nil || wrongResp.Error.Code != "INVALID_CREDENTIALS" {
		t.Errorf("expected error code INVALID_CREDENTIALS, got %+v", wrongResp.Error)
	}

	// 2. Successful login
	correctPayload := map[string]any{
		"email":    "bob@example.com",
		"password": "correctpassword",
	}
	correctBody, _ := json.Marshal(correctPayload)
	loginReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(correctBody))
	loginReq.Header.Set("Content-Type", "application/json")
	loginRec := httptest.NewRecorder()
	router.ServeHTTP(loginRec, loginReq)

	if loginRec.Code != http.StatusOK {
		t.Fatalf("expected status 200 for valid login, got %d. Body: %s", loginRec.Code, loginRec.Body.String())
	}
	loginResp := parseResponse(t, loginRec)
	loginData := loginResp.Data.(map[string]any)
	token, ok := loginData["token"].(string)
	if !ok || token == "" {
		t.Errorf("expected valid token returned from login")
	}
	user := loginData["user"].(map[string]any)
	if user["email"] != "bob@example.com" {
		t.Errorf("expected email bob@example.com, got %v", user["email"])
	}
	if _, exists := user["password_hash"]; exists {
		t.Errorf("password_hash must never be exposed")
	}
}

func TestAuth_MeAndLogoutFlow(t *testing.T) {
	router, database := setupTestRouter(t)
	defer database.Close()

	// 1. Register a user to obtain a token
	regPayload := map[string]any{
		"name":     "Charlie",
		"email":    "charlie@example.com",
		"password": "mypassword123",
		"timezone": "Asia/Tokyo",
	}
	regBody, _ := json.Marshal(regPayload)
	regReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(regBody))
	regReq.Header.Set("Content-Type", "application/json")
	regRec := httptest.NewRecorder()
	router.ServeHTTP(regRec, regReq)

	if regRec.Code != http.StatusCreated {
		t.Fatalf("registration failed: %s", regRec.Body.String())
	}

	regResp := parseResponse(t, regRec)
	dataMap := regResp.Data.(map[string]any)
	token := dataMap["token"].(string)

	// 2. Access /me without auth -> 401
	unauthReq := httptest.NewRequest(http.MethodGet, "/api/v1/auth/me", nil)
	unauthRec := httptest.NewRecorder()
	router.ServeHTTP(unauthRec, unauthReq)

	if unauthRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for unauthenticated /me, got %d", unauthRec.Code)
	}

	// 3. Access /me with valid token -> 200
	meReq := httptest.NewRequest(http.MethodGet, "/api/v1/auth/me", nil)
	meReq.Header.Set("Authorization", "Bearer "+token)
	meRec := httptest.NewRecorder()
	router.ServeHTTP(meRec, meReq)

	if meRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for authenticated /me, got %d. Body: %s", meRec.Code, meRec.Body.String())
	}

	meResp := parseResponse(t, meRec)
	userData := meResp.Data.(map[string]any)
	if userData["name"] != "Charlie" || userData["email"] != "charlie@example.com" {
		t.Errorf("expected Charlie's profile, got %+v", userData)
	}
	if _, exists := userData["password_hash"]; exists {
		t.Errorf("password_hash must never be exposed")
	}

	// 4. Logout invalidates the token -> 200
	logoutReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout", nil)
	logoutReq.Header.Set("Authorization", "Bearer "+token)
	logoutRec := httptest.NewRecorder()
	router.ServeHTTP(logoutRec, logoutReq)

	if logoutRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for logout, got %d. Body: %s", logoutRec.Code, logoutRec.Body.String())
	}

	// 5. Following /me returns 401
	afterLogoutReq := httptest.NewRequest(http.MethodGet, "/api/v1/auth/me", nil)
	afterLogoutReq.Header.Set("Authorization", "Bearer "+token)
	afterLogoutRec := httptest.NewRecorder()
	router.ServeHTTP(afterLogoutRec, afterLogoutReq)

	if afterLogoutRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for /me after logout, got %d. Body: %s", afterLogoutRec.Code, afterLogoutRec.Body.String())
	}
}
