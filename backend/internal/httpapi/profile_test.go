package httpapi_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"path/filepath"
	"strings"
	"testing"

	"github.com/abshwabu/pair/backend/internal/config"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/httpapi"
	"github.com/abshwabu/pair/backend/internal/storage"
)

func setupProfileTestApp(t *testing.T) (http.Handler, *storage.FakeStorage, *db.DB, string) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "profile_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	cfg := &config.Config{
		Port:            "8080",
		DBPath:          dbPath,
		S3PublicBaseURL: "http://localhost:9000/pair-media",
	}

	fakeStorage := storage.NewFakeStorage(cfg.S3PublicBaseURL)
	router := httpapi.NewRouter(cfg, database, fakeStorage)

	// Register a test user
	regPayload := map[string]any{
		"name":     "Initial User",
		"email":    "user@example.com",
		"password": "initialpassword123",
		"timezone": "UTC",
	}
	body, _ := json.Marshal(regPayload)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to register test user, got code %d: %s", rec.Code, rec.Body.String())
	}

	var regResp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &regResp)
	dataMap := regResp.Data.(map[string]any)
	token := dataMap["token"].(string)

	return router, fakeStorage, database, token
}

func makeMultipartUploadRequest(url, fieldName, filename string, data []byte, token string) (*http.Request, error) {
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	h := make(textproto.MIMEHeader)
	h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="%s"; filename="%s"`, fieldName, filename))
	part, err := writer.CreatePart(h)
	if err != nil {
		return nil, err
	}
	if _, err := part.Write(data); err != nil {
		return nil, err
	}
	if err := writer.Close(); err != nil {
		return nil, err
	}

	req := httptest.NewRequest(http.MethodPost, url, body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	return req, nil
}

func TestProfile_GetProfile(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	// 1. Unauthenticated request
	reqUnauth := httptest.NewRequest(http.MethodGet, "/api/v1/profile", nil)
	recUnauth := httptest.NewRecorder()
	router.ServeHTTP(recUnauth, reqUnauth)
	if recUnauth.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for unauthenticated GET /profile, got %d", recUnauth.Code)
	}

	// 2. Authenticated request
	req := httptest.NewRequest(http.MethodGet, "/api/v1/profile", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for authenticated GET /profile, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	dataMap, ok := resp.Data.(map[string]any)
	if !ok {
		t.Fatalf("expected data to be map[string]any, got %T", resp.Data)
	}
	if dataMap["name"] != "Initial User" {
		t.Errorf("expected name 'Initial User', got %v", dataMap["name"])
	}
	if dataMap["email"] != "user@example.com" {
		t.Errorf("expected email 'user@example.com', got %v", dataMap["email"])
	}
	if dataMap["timezone"] != "UTC" {
		t.Errorf("expected timezone 'UTC', got %v", dataMap["timezone"])
	}
}

func TestProfile_UpdateProfile_Valid(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	updatePayload := map[string]any{
		"name":     "Jane Doe Updated",
		"timezone": "Europe/London",
		"language": "es",
	}
	body, _ := json.Marshal(updatePayload)
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/profile", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for PATCH /profile, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	dataMap := resp.Data.(map[string]any)

	if dataMap["name"] != "Jane Doe Updated" {
		t.Errorf("expected name 'Jane Doe Updated', got %v", dataMap["name"])
	}
	if dataMap["timezone"] != "Europe/London" {
		t.Errorf("expected timezone 'Europe/London', got %v", dataMap["timezone"])
	}
	if dataMap["language"] != "es" {
		t.Errorf("expected language 'es', got %v", dataMap["language"])
	}

	// Verify persistence via GET /api/v1/profile
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/profile", nil)
	getReq.Header.Set("Authorization", "Bearer "+token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	var getResp httpapi.Response
	_ = json.Unmarshal(getRec.Body.Bytes(), &getResp)
	getData := getResp.Data.(map[string]any)

	if getData["name"] != "Jane Doe Updated" {
		t.Errorf("persisted name mismatch, got %v", getData["name"])
	}
	if getData["timezone"] != "Europe/London" {
		t.Errorf("persisted timezone mismatch, got %v", getData["timezone"])
	}
	if getData["language"] != "es" {
		t.Errorf("persisted language mismatch, got %v", getData["language"])
	}
}

func TestProfile_UpdateProfile_PartialUpdate(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	// Update only timezone
	updatePayload := map[string]any{
		"timezone": "Asia/Tokyo",
	}
	body, _ := json.Marshal(updatePayload)
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/profile", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for partial PATCH /profile, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	dataMap := resp.Data.(map[string]any)

	if dataMap["name"] != "Initial User" {
		t.Errorf("expected name to remain 'Initial User', got %v", dataMap["name"])
	}
	if dataMap["timezone"] != "Asia/Tokyo" {
		t.Errorf("expected timezone 'Asia/Tokyo', got %v", dataMap["timezone"])
	}
}

func TestProfile_UpdateProfile_InvalidTimezone(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	updatePayload := map[string]any{
		"timezone": "Not/A_Real_Timezone",
	}
	body, _ := json.Marshal(updatePayload)
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/profile", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid timezone, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Error == nil || !strings.Contains(strings.ToLower(resp.Error.Message), "timezone") {
		t.Errorf("expected timezone error in response, got %+v", resp.Error)
	}
}

func TestProfile_UploadAvatar_ValidPNG(t *testing.T) {
	router, fakeStorage, database, token := setupProfileTestApp(t)
	defer database.Close()

	// Valid PNG bytes (header + chunk)
	pngBytes := []byte{0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 'I', 'H', 'D', 'R'}

	req, err := makeMultipartUploadRequest("/api/v1/profile/avatar", "file", "avatar.png", pngBytes, token)
	if err != nil {
		t.Fatalf("failed to build upload request: %v", err)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for valid avatar upload, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	dataMap, ok := resp.Data.(map[string]any)
	if !ok {
		t.Fatalf("expected data map, got %T", resp.Data)
	}

	avatarURL, ok := dataMap["avatar_url"].(string)
	if !ok || avatarURL == "" {
		t.Fatalf("expected avatar_url in response data, got %v", dataMap["avatar_url"])
	}

	expectedPrefix := "http://localhost:9000/pair-media/avatars/"
	if !strings.HasPrefix(avatarURL, expectedPrefix) {
		t.Errorf("expected avatarURL to start with %q, got %q", expectedPrefix, avatarURL)
	}
	if !strings.HasSuffix(avatarURL, ".png") {
		t.Errorf("expected avatarURL to end with .png, got %q", avatarURL)
	}

	// Verify file was uploaded to FakeStorage
	key := strings.TrimPrefix(avatarURL, "http://localhost:9000/pair-media/")
	if !fakeStorage.HasFile(key) {
		t.Fatalf("fakeStorage does not contain file with key %q", key)
	}
	storedBytes, _ := fakeStorage.GetFile(key)
	if !bytes.Equal(storedBytes, pngBytes) {
		t.Errorf("stored bytes mismatch")
	}

	// Verify persistence in GET /api/v1/profile
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/profile", nil)
	getReq.Header.Set("Authorization", "Bearer "+token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)

	var getResp httpapi.Response
	_ = json.Unmarshal(getRec.Body.Bytes(), &getResp)
	getData := getResp.Data.(map[string]any)

	if getData["avatar_url"] != avatarURL {
		t.Errorf("persisted avatar_url mismatch: expected %q, got %v", avatarURL, getData["avatar_url"])
	}
}

func TestProfile_UploadAvatar_ValidJPEG(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	// Valid JPEG magic header bytes
	jpegBytes := []byte{0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 'J', 'F', 'I', 'F', 0x00, 0x01, 0x01, 0x01, 0x00, 0x48}

	req, err := makeMultipartUploadRequest("/api/v1/profile/avatar", "file", "photo.jpg", jpegBytes, token)
	if err != nil {
		t.Fatalf("failed to build upload request: %v", err)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for JPEG avatar upload, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	dataMap := resp.Data.(map[string]any)
	avatarURL := dataMap["avatar_url"].(string)

	if !strings.HasSuffix(avatarURL, ".jpg") {
		t.Errorf("expected avatarURL to end with .jpg, got %q", avatarURL)
	}
}

func TestProfile_UploadAvatar_ValidWebP(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	// Valid WebP magic header bytes: "RIFF....WEBPVP8 "
	webpBytes := append([]byte("RIFF1234WEBPVP8 "), make([]byte, 100)...)

	req, err := makeMultipartUploadRequest("/api/v1/profile/avatar", "file", "image.webp", webpBytes, token)
	if err != nil {
		t.Fatalf("failed to build upload request: %v", err)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for WebP avatar upload, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	dataMap := resp.Data.(map[string]any)
	avatarURL := dataMap["avatar_url"].(string)

	if !strings.HasSuffix(avatarURL, ".webp") {
		t.Errorf("expected avatarURL to end with .webp, got %q", avatarURL)
	}
}

func TestProfile_UploadAvatar_InvalidFileType(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	// Text content disguised as an image
	fakeImageBytes := []byte("<html><body>Not an image at all!</body></html>")

	req, err := makeMultipartUploadRequest("/api/v1/profile/avatar", "file", "avatar.png", fakeImageBytes, token)
	if err != nil {
		t.Fatalf("failed to build upload request: %v", err)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid file type, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Error == nil || !strings.Contains(strings.ToLower(resp.Error.Message), "file type") {
		t.Errorf("expected invalid file type error, got %+v", resp.Error)
	}
}

func TestProfile_UploadAvatar_OversizedFile(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	// 5MB + 2048 bytes (> 5MB limit)
	oversizedBytes := make([]byte, 5*1024*1024+2048)
	// Add valid PNG header so content-type sniffing would pass if size wasn't checked
	copy(oversizedBytes, []byte{0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a})

	req, err := makeMultipartUploadRequest("/api/v1/profile/avatar", "file", "huge.png", oversizedBytes, token)
	if err != nil {
		t.Fatalf("failed to build upload request: %v", err)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for oversized file (>5MB), got %d: %s", rec.Code, rec.Body.String())
	}

	var resp httpapi.Response
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Error == nil {
		t.Fatalf("expected error object in response")
	}
	if !strings.Contains(strings.ToLower(resp.Error.Message), "5mb") && resp.Error.Code != "FILE_TOO_LARGE" {
		t.Errorf("expected 5MB / FILE_TOO_LARGE error message, got code=%s message=%s", resp.Error.Code, resp.Error.Message)
	}
}

func TestProfile_ChangePassword(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	// 1. Unauthenticated request
	reqUnauth := httptest.NewRequest(http.MethodPatch, "/api/v1/profile/password", strings.NewReader(`{"current_password":"initialpassword123","new_password":"NewStrongPassword456!"}`))
	reqUnauth.Header.Set("Content-Type", "application/json")
	recUnauth := httptest.NewRecorder()
	router.ServeHTTP(recUnauth, reqUnauth)
	if recUnauth.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for unauthenticated request, got %d", recUnauth.Code)
	}

	// 2. Incorrect current password
	wrongReq := httptest.NewRequest(http.MethodPatch, "/api/v1/profile/password", strings.NewReader(`{"current_password":"wrongpassword","new_password":"NewStrongPassword456!"}`))
	wrongReq.Header.Set("Authorization", "Bearer "+token)
	wrongReq.Header.Set("Content-Type", "application/json")
	wrongRec := httptest.NewRecorder()
	router.ServeHTTP(wrongRec, wrongReq)
	if wrongRec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for wrong current password, got %d: %s", wrongRec.Code, wrongRec.Body.String())
	}

	// 3. Short new password (< 8 characters)
	shortReq := httptest.NewRequest(http.MethodPatch, "/api/v1/profile/password", strings.NewReader(`{"current_password":"initialpassword123","new_password":"short"}`))
	shortReq.Header.Set("Authorization", "Bearer "+token)
	shortReq.Header.Set("Content-Type", "application/json")
	shortRec := httptest.NewRecorder()
	router.ServeHTTP(shortRec, shortReq)
	if shortRec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for short new password, got %d: %s", shortRec.Code, shortRec.Body.String())
	}

	// 4. Create a second session (second token) to test token revocation
	loginReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(`{"email":"user@example.com","password":"initialpassword123"}`))
	loginReq.Header.Set("Content-Type", "application/json")
	loginRec := httptest.NewRecorder()
	router.ServeHTTP(loginRec, loginReq)
	if loginRec.Code != http.StatusOK {
		t.Fatalf("expected 200 on login, got %d", loginRec.Code)
	}
	var loginResp httpapi.Response
	_ = json.Unmarshal(loginRec.Body.Bytes(), &loginResp)
	token2 := loginResp.Data.(map[string]any)["token"].(string)

	// 5. Change password using token2
	changeReq := httptest.NewRequest(http.MethodPatch, "/api/v1/profile/password", strings.NewReader(`{"current_password":"initialpassword123","new_password":"NewStrongPassword456!"}`))
	changeReq.Header.Set("Authorization", "Bearer "+token2)
	changeReq.Header.Set("Content-Type", "application/json")
	changeRec := httptest.NewRecorder()
	router.ServeHTTP(changeRec, changeReq)
	if changeRec.Code != http.StatusOK {
		t.Fatalf("expected 200 on successful password change, got %d: %s", changeRec.Code, changeRec.Body.String())
	}

	// 6. Old token (token) should now be revoked (401)
	checkOldReq := httptest.NewRequest(http.MethodGet, "/api/v1/profile", nil)
	checkOldReq.Header.Set("Authorization", "Bearer "+token)
	checkOldRec := httptest.NewRecorder()
	router.ServeHTTP(checkOldRec, checkOldReq)
	if checkOldRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for revoked token, got %d", checkOldRec.Code)
	}

	// 7. Token2 should still be valid (200)
	checkNewReq := httptest.NewRequest(http.MethodGet, "/api/v1/profile", nil)
	checkNewReq.Header.Set("Authorization", "Bearer "+token2)
	checkNewRec := httptest.NewRecorder()
	router.ServeHTTP(checkNewRec, checkNewReq)
	if checkNewRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for active token, got %d", checkNewRec.Code)
	}

	// 8. Login with old password fails
	failLoginReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(`{"email":"user@example.com","password":"initialpassword123"}`))
	failLoginReq.Header.Set("Content-Type", "application/json")
	failLoginRec := httptest.NewRecorder()
	router.ServeHTTP(failLoginRec, failLoginReq)
	if failLoginRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 with old password, got %d", failLoginRec.Code)
	}

	// 9. Login with new password succeeds
	succLoginReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(`{"email":"user@example.com","password":"NewStrongPassword456!"}`))
	succLoginReq.Header.Set("Content-Type", "application/json")
	succLoginRec := httptest.NewRecorder()
	router.ServeHTTP(succLoginRec, succLoginReq)
	if succLoginRec.Code != http.StatusOK {
		t.Fatalf("expected 200 with new password, got %d: %s", succLoginRec.Code, succLoginRec.Body.String())
	}
}

func TestProfile_DeleteAccount(t *testing.T) {
	router, _, database, token := setupProfileTestApp(t)
	defer database.Close()

	// 1. Unauthenticated request -> 401
	unauthReq := httptest.NewRequest(http.MethodDelete, "/api/v1/profile", nil)
	unauthRec := httptest.NewRecorder()
	router.ServeHTTP(unauthRec, unauthReq)
	if unauthRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for unauthenticated delete, got %d", unauthRec.Code)
	}

	// 2. Delete account with authenticated token
	delReq := httptest.NewRequest(http.MethodDelete, "/api/v1/profile", nil)
	delReq.Header.Set("Authorization", "Bearer "+token)
	delRec := httptest.NewRecorder()
	router.ServeHTTP(delRec, delReq)
	if delRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for delete account, got %d: %s", delRec.Code, delRec.Body.String())
	}

	// 3. User token should be revoked (subsequent requests fail with 401)
	getReq := httptest.NewRequest(http.MethodGet, "/api/v1/profile", nil)
	getReq.Header.Set("Authorization", "Bearer "+token)
	getRec := httptest.NewRecorder()
	router.ServeHTTP(getRec, getReq)
	if getRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 after account deletion, got %d", getRec.Code)
	}

	// 4. Verify user record in database is anonymized and soft-deleted
	var name, email string
	var deletedAt, avatarURL, fcmToken *string
	err := database.Read.QueryRow(`SELECT name, email, deleted_at, avatar_url, fcm_token FROM users WHERE email LIKE 'deleted_%';`).
		Scan(&name, &email, &deletedAt, &avatarURL, &fcmToken)
	if err != nil {
		t.Fatalf("failed to query anonymized user: %v", err)
	}
	if name != "Deleted User" {
		t.Errorf("expected name 'Deleted User', got %q", name)
	}
	if deletedAt == nil {
		t.Errorf("expected deleted_at to be non-nil")
	}
	if avatarURL != nil {
		t.Errorf("expected avatar_url to be nil, got %v", *avatarURL)
	}
	if fcmToken != nil {
		t.Errorf("expected fcm_token to be nil, got %v", *fcmToken)
	}
}
