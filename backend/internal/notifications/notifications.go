package notifications

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Notification represents a notification in the notifications table.
type Notification struct {
	ID        string     `json:"id"`
	UserID    string     `json:"user_id"`
	Type      string     `json:"type"`
	Payload   string     `json:"payload"` // JSON text
	SentAt    *time.Time `json:"sent_at,omitempty"`
	ReadAt    *time.Time `json:"read_at,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}

// Repository handles notifications database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewRepository creates a new notifications Repository.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// Create inserts a new notification record.
func (r *Repository) Create(ctx context.Context, n *Notification) error {
	query := `
		INSERT INTO notifications (id, user_id, type, payload, sent_at, read_at, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?);
	`
	var sentAtStr *string
	if n.SentAt != nil {
		s := n.SentAt.UTC().Format(time.RFC3339)
		sentAtStr = &s
	}

	var readAtStr *string
	if n.ReadAt != nil {
		s := n.ReadAt.UTC().Format(time.RFC3339)
		readAtStr = &s
	}

	createdAtStr := n.CreatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		n.ID, n.UserID, n.Type, n.Payload, sentAtStr, readAtStr, createdAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create notification: %w", err)
	}
	return nil
}

// GetByID retrieves a notification record by its ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Notification, error) {
	query := `
		SELECT id, user_id, type, payload, sent_at, read_at, created_at
		FROM notifications
		WHERE id = ?;
	`
	var n Notification
	var sentAtStr, readAtStr, createdAtStr *string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&n.ID, &n.UserID, &n.Type, &n.Payload, &sentAtStr, &readAtStr, &createdAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errors.New("notification not found")
		}
		return nil, fmt.Errorf("failed to get notification: %w", err)
	}

	if sentAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *sentAtStr); err == nil {
			n.SentAt = &parsed
		}
	}
	if readAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *readAtStr); err == nil {
			n.ReadAt = &parsed
		}
	}
	if createdAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *createdAtStr); err == nil {
			n.CreatedAt = parsed
		}
	}

	return &n, nil
}
