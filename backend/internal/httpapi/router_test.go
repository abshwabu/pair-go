package httpapi_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/abshwabu/pair/backend/internal/config"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/httpapi"
)

func TestHealthzEndpoint(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "test_pair.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}
	defer database.Close()

	cfg := &config.Config{
		Port:   "8080",
		DBPath: dbPath,
	}

	router := httpapi.NewRouter(cfg, database)

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rr := httptest.NewRecorder()

	router.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}

	var resp httpapi.Response
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to unmarshal JSON response: %v", err)
	}

	if resp.Error != nil {
		t.Errorf("expected error to be nil, got %+v", resp.Error)
	}

	dataMap, ok := resp.Data.(map[string]any)
	if !ok {
		t.Fatalf("expected data to be map[string]any, got %T", resp.Data)
	}

	if dataMap["status"] != "ok" {
		t.Errorf("expected data.status to be 'ok', got %v", dataMap["status"])
	}

	if dataMap["database"] != "ok" {
		t.Errorf("expected data.database to be 'ok', got %v", dataMap["database"])
	}
}
