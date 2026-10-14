package users

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

// User represents a user record in the users table.
type User struct {
	ID           string     `json:"id"`
	Name         string     `json:"name"`
	Email        string     `json:"email"`
	PasswordHash string     `json:"-"`
	AvatarURL    *string    `json:"avatar_url,omitempty"`
	Timezone     string     `json:"timezone"`
	Language     string     `json:"language"`
	FCMToken     *string    `json:"fcm_token,omitempty"`
	IsAdmin      bool       `json:"is_admin"`
	DeletedAt    *time.Time `json:"deleted_at,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

// Repository handles users database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewRepository creates a new users Repository.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// Create inserts a new user record.
func (r *Repository) Create(ctx context.Context, u *User) error {
	query := `
		INSERT INTO users (
			id, name, email, password_hash, avatar_url, timezone, language,
			fcm_token, is_admin, deleted_at, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
	`
	isAdminInt := 0
	if u.IsAdmin {
		isAdminInt = 1
	}

	var deletedAtStr *string
	if u.DeletedAt != nil {
		s := u.DeletedAt.UTC().Format(time.RFC3339)
		deletedAtStr = &s
	}

	createdAtStr := u.CreatedAt.UTC().Format(time.RFC3339)
	updatedAtStr := u.UpdatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		u.ID, u.Name, u.Email, u.PasswordHash, u.AvatarURL, u.Timezone, u.Language,
		u.FCMToken, isAdminInt, deletedAtStr, createdAtStr, updatedAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}
	return nil
}

// ErrUserNotFound is returned when a user record does not exist.
var ErrUserNotFound = errors.New("user not found")

// GetByID retrieves a user record by its ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*User, error) {
	query := `
		SELECT id, name, email, password_hash, avatar_url, timezone, language,
		       fcm_token, is_admin, deleted_at, created_at, updated_at
		FROM users
		WHERE id = ?;
	`
	var u User
	var isAdminInt int
	var deletedAtStr, createdAtStr, updatedAtStr *string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.AvatarURL, &u.Timezone, &u.Language,
		&u.FCMToken, &isAdminInt, &deletedAtStr, &createdAtStr, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	u.IsAdmin = isAdminInt == 1
	if deletedAtStr != nil {
		if t, err := time.Parse(time.RFC3339, *deletedAtStr); err == nil {
			u.DeletedAt = &t
		}
	}
	if createdAtStr != nil {
		if t, err := time.Parse(time.RFC3339, *createdAtStr); err == nil {
			u.CreatedAt = t
		}
	}
	if updatedAtStr != nil {
		if t, err := time.Parse(time.RFC3339, *updatedAtStr); err == nil {
			u.UpdatedAt = t
		}
	}

	return &u, nil
}

// GetByEmail retrieves a user record by email (case-insensitive).
func (r *Repository) GetByEmail(ctx context.Context, email string) (*User, error) {
	query := `
		SELECT id, name, email, password_hash, avatar_url, timezone, language,
		       fcm_token, is_admin, deleted_at, created_at, updated_at
		FROM users
		WHERE LOWER(email) = LOWER(?);
	`
	var u User
	var isAdminInt int
	var deletedAtStr, createdAtStr, updatedAtStr *string

	err := r.readDB.QueryRowContext(ctx, query, email).Scan(
		&u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.AvatarURL, &u.Timezone, &u.Language,
		&u.FCMToken, &isAdminInt, &deletedAtStr, &createdAtStr, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("failed to get user by email: %w", err)
	}

	u.IsAdmin = isAdminInt == 1
	if deletedAtStr != nil {
		if t, err := time.Parse(time.RFC3339, *deletedAtStr); err == nil {
			u.DeletedAt = &t
		}
	}
	if createdAtStr != nil {
		if t, err := time.Parse(time.RFC3339, *createdAtStr); err == nil {
			u.CreatedAt = t
		}
	}
	if updatedAtStr != nil {
		if t, err := time.Parse(time.RFC3339, *updatedAtStr); err == nil {
			u.UpdatedAt = t
		}
	}

	return &u, nil
}

// UpdateProfileParams contains optional fields to update on the user profile.
type UpdateProfileParams struct {
	Name     *string
	Timezone *string
	Language *string
}

// UpdateProfile updates the specified profile fields for an active user.
func (r *Repository) UpdateProfile(ctx context.Context, id string, params UpdateProfileParams) (*User, error) {
	var setClauses []string
	var args []any

	if params.Name != nil {
		setClauses = append(setClauses, "name = ?")
		args = append(args, *params.Name)
	}
	if params.Timezone != nil {
		setClauses = append(setClauses, "timezone = ?")
		args = append(args, *params.Timezone)
	}
	if params.Language != nil {
		setClauses = append(setClauses, "language = ?")
		args = append(args, *params.Language)
	}

	if len(setClauses) == 0 {
		return r.GetByID(ctx, id)
	}

	now := time.Now().UTC().Format(time.RFC3339)
	setClauses = append(setClauses, "updated_at = ?")
	args = append(args, now)
	args = append(args, id)

	query := fmt.Sprintf("UPDATE users SET %s WHERE id = ? AND deleted_at IS NULL;", strings.Join(setClauses, ", "))
	res, err := r.writeDB.ExecContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to update user profile: %w", err)
	}

	rows, err := res.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rows == 0 {
		return nil, ErrUserNotFound
	}

	return r.GetByID(ctx, id)
}

// UpdateAvatarURL updates the user's avatar_url field.
func (r *Repository) UpdateAvatarURL(ctx context.Context, id string, avatarURL string) (*User, error) {
	now := time.Now().UTC().Format(time.RFC3339)
	query := `UPDATE users SET avatar_url = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL;`
	res, err := r.writeDB.ExecContext(ctx, query, avatarURL, now, id)
	if err != nil {
		return nil, fmt.Errorf("failed to update avatar URL: %w", err)
	}

	rows, err := res.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rows == 0 {
		return nil, ErrUserNotFound
	}

	return r.GetByID(ctx, id)
}

// SetAdmin updates the is_admin status for a user identified by email.
func (r *Repository) SetAdmin(ctx context.Context, email string, isAdmin bool) error {
	now := time.Now().UTC().Format(time.RFC3339)
	isAdminInt := 0
	if isAdmin {
		isAdminInt = 1
	}
	query := `UPDATE users SET is_admin = ?, updated_at = ? WHERE LOWER(email) = LOWER(?) AND deleted_at IS NULL;`
	res, err := r.writeDB.ExecContext(ctx, query, isAdminInt, now, email)
	if err != nil {
		return fmt.Errorf("failed to update admin status: %w", err)
	}

	rows, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rows == 0 {
		return ErrUserNotFound
	}

	return nil
}
