package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/abshwabu/pair/backend/internal/users"
)

// ErrTokenNotFound is returned when an auth token cannot be located.
var ErrTokenNotFound = errors.New("auth token not found")

type contextKey string

const (
	userContextKey      contextKey = "pair_auth_user"
	tokenHashContextKey contextKey = "pair_auth_token_hash"
)

// UserFromContext retrieves the authenticated user from the context.
func UserFromContext(ctx context.Context) (*users.User, bool) {
	u, ok := ctx.Value(userContextKey).(*users.User)
	return u, ok && u != nil
}

// WithUser returns a new context containing the authenticated user.
func WithUser(ctx context.Context, u *users.User) context.Context {
	return context.WithValue(ctx, userContextKey, u)
}

// TokenHashFromContext retrieves the token hash from the context.
func TokenHashFromContext(ctx context.Context) (string, bool) {
	h, ok := ctx.Value(tokenHashContextKey).(string)
	return h, ok && h != ""
}

// WithTokenHash returns a new context containing the token hash.
func WithTokenHash(ctx context.Context, tokenHash string) context.Context {
	return context.WithValue(ctx, tokenHashContextKey, tokenHash)
}

// AuthToken represents an opaque session token in the auth_tokens table.
type AuthToken struct {
	ID         string     `json:"id"`
	UserID     string     `json:"user_id"`
	TokenHash  string     `json:"-"`
	LastUsedAt *time.Time `json:"last_used_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
}

// Repository handles auth_tokens database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewRepository creates a new auth Repository.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// Create inserts a new auth_token record.
func (r *Repository) Create(ctx context.Context, t *AuthToken) error {
	query := `
		INSERT INTO auth_tokens (id, user_id, token_hash, last_used_at, created_at)
		VALUES (?, ?, ?, ?, ?);
	`
	var lastUsedAtStr *string
	if t.LastUsedAt != nil {
		s := t.LastUsedAt.UTC().Format(time.RFC3339)
		lastUsedAtStr = &s
	}
	createdAtStr := t.CreatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query, t.ID, t.UserID, t.TokenHash, lastUsedAtStr, createdAtStr)
	if err != nil {
		return fmt.Errorf("failed to create auth token: %w", err)
	}
	return nil
}

// GetByID retrieves an auth_token record by its ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*AuthToken, error) {
	query := `
		SELECT id, user_id, token_hash, last_used_at, created_at
		FROM auth_tokens
		WHERE id = ?;
	`
	var t AuthToken
	var lastUsedAtStr, createdAtStr *string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&t.ID, &t.UserID, &t.TokenHash, &lastUsedAtStr, &createdAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrTokenNotFound
		}
		return nil, fmt.Errorf("failed to get auth token: %w", err)
	}

	if lastUsedAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *lastUsedAtStr); err == nil {
			t.LastUsedAt = &parsed
		}
	}
	if createdAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *createdAtStr); err == nil {
			t.CreatedAt = parsed
		}
	}

	return &t, nil
}

// GetByHash retrieves an auth_token record by its SHA-256 token hash.
func (r *Repository) GetByHash(ctx context.Context, tokenHash string) (*AuthToken, error) {
	query := `
		SELECT id, user_id, token_hash, last_used_at, created_at
		FROM auth_tokens
		WHERE token_hash = ?;
	`
	var t AuthToken
	var lastUsedAtStr, createdAtStr *string

	err := r.readDB.QueryRowContext(ctx, query, tokenHash).Scan(
		&t.ID, &t.UserID, &t.TokenHash, &lastUsedAtStr, &createdAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrTokenNotFound
		}
		return nil, fmt.Errorf("failed to get auth token by hash: %w", err)
	}

	if lastUsedAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *lastUsedAtStr); err == nil {
			t.LastUsedAt = &parsed
		}
	}
	if createdAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *createdAtStr); err == nil {
			t.CreatedAt = parsed
		}
	}

	return &t, nil
}

// UpdateLastUsedAt updates the last_used_at timestamp on a token row.
func (r *Repository) UpdateLastUsedAt(ctx context.Context, tokenHash string, lastUsedAt time.Time) error {
	query := `
		UPDATE auth_tokens
		SET last_used_at = ?
		WHERE token_hash = ?;
	`
	lastUsedAtStr := lastUsedAt.UTC().Format(time.RFC3339)
	_, err := r.writeDB.ExecContext(ctx, query, lastUsedAtStr, tokenHash)
	if err != nil {
		return fmt.Errorf("failed to update token last_used_at: %w", err)
	}
	return nil
}

// DeleteByHash deletes a token row by its SHA-256 hash (used for logout).
func (r *Repository) DeleteByHash(ctx context.Context, tokenHash string) error {
	query := `
		DELETE FROM auth_tokens
		WHERE token_hash = ?;
	`
	result, err := r.writeDB.ExecContext(ctx, query, tokenHash)
	if err != nil {
		return fmt.Errorf("failed to delete auth token: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return ErrTokenNotFound
	}
	return nil
}

// DeleteAllExcept deletes all auth tokens for a user except the specified token hash.
func (r *Repository) DeleteAllExcept(ctx context.Context, userID, exceptTokenHash string) error {
	query := `
		DELETE FROM auth_tokens
		WHERE user_id = ? AND token_hash != ?;
	`
	_, err := r.writeDB.ExecContext(ctx, query, userID, exceptTokenHash)
	if err != nil {
		return fmt.Errorf("failed to delete other tokens: %w", err)
	}
	return nil
}

// DeleteAllForUserTx deletes all auth tokens for a user within an existing transaction.
func (r *Repository) DeleteAllForUserTx(ctx context.Context, tx *sql.Tx, userID string) error {
	query := `
		DELETE FROM auth_tokens
		WHERE user_id = ?;
	`
	_, err := tx.ExecContext(ctx, query, userID)
	if err != nil {
		return fmt.Errorf("failed to delete auth tokens in tx: %w", err)
	}
	return nil
}

// HashPassword hashes a plaintext password using bcrypt.
func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("failed to hash password: %w", err)
	}
	return string(bytes), nil
}

// CheckPassword compares a plaintext password with its bcrypt hash.
func CheckPassword(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

// GenerateRawToken generates 32 cryptographically secure random bytes and returns
// them base64url-encoded without padding.
func GenerateRawToken() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("failed to generate random token bytes: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

// HashToken calculates the SHA-256 hex string of a raw opaque bearer token.
func HashToken(rawToken string) string {
	hash := sha256.Sum256([]byte(rawToken))
	return hex.EncodeToString(hash[:])
}
