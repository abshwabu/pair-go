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
