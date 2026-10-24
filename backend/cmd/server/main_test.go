package main_test

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/users"
)

func TestMakeAdmin_Repository(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "admin_repo_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}
	defer database.Close()

	usersRepo := users.NewRepository(database.Write, database.Read)
	ctx := context.Background()

	// 1. Promoting a non-existent user returns an error
	err = usersRepo.SetAdmin(ctx, "nonexistent@example.com", true)
	if err == nil {
		t.Fatalf("expected error for nonexistent user, got nil")
	}

	// 2. Insert standard non-admin user
	userID := uuid.NewString()
	email := "regular@example.com"
	now := time.Now().UTC().Format(time.RFC3339)
	_, err = database.Write.Exec(`
		INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at)
		VALUES (?, 'Regular User', ?, 'hash', 'UTC', 'en', 0, ?, ?);
	`, userID, email, now, now)
	if err != nil {
		t.Fatalf("failed to insert user: %v", err)
	}

	// 3. Promote user to admin
	if err := usersRepo.SetAdmin(ctx, email, true); err != nil {
		t.Fatalf("failed to set admin: %v", err)
	}

	// 4. Verify user is now an admin
	u, err := usersRepo.GetByID(ctx, userID)
	if err != nil {
		t.Fatalf("failed to get user: %v", err)
	}
	if !u.IsAdmin {
		t.Fatalf("expected user to be admin, but is_admin is false")
	}
}

func TestMakeAdmin_CLIHelper(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "admin_cli_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	userID := uuid.NewString()
	email := "promote_me@example.com"
	now := time.Now().UTC().Format(time.RFC3339)
	_, err = database.Write.Exec(`
		INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at)
		VALUES (?, 'CLI Promote User', ?, 'hash', 'UTC', 'en', 0, ?, ?);
	`, userID, email, now, now)
	if err != nil {
		t.Fatalf("failed to insert user: %v", err)
	}
	_ = database.Close()

	// Execute CLI helper: go run main.go --make-admin <email>
	cmd := exec.Command("go", "run", "main.go", "--make-admin", email)
	cmd.Dir = "."
	cmd.Env = append(os.Environ(), "DB_PATH="+dbPath)

	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("failed to run --make-admin command: %v, output: %s", err, string(out))
	}

	// Reopen DB to verify admin promotion
	dbCheck, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to reopen db: %v", err)
	}
	defer dbCheck.Close()

	var isAdmin int
	err = dbCheck.Read.QueryRow(`SELECT is_admin FROM users WHERE id = ?;`, userID).Scan(&isAdmin)
	if err != nil {
		t.Fatalf("failed to query is_admin: %v", err)
	}
	if isAdmin != 1 {
		t.Fatalf("expected is_admin to be 1, got %d", isAdmin)
	}
}
