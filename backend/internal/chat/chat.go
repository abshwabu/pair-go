package chat

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Sentinel errors for chat domain.
var (
	ErrMessageNotFound = errors.New("message not found")
	ErrValidation      = errors.New("validation error")
)

// Message represents a chat message in the messages table.
type Message struct {
	ID            string    `json:"id"`
	PodID         string    `json:"pod_id"`
	SenderID      string    `json:"sender_id"`
	Body          *string   `json:"body"`
	AttachmentURL *string   `json:"attachment_url"`
	CreatedAt     time.Time `json:"created_at"`
}

// Repository handles messages database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewRepository creates a new chat Repository.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// Create inserts a new message record into SQLite.
func (r *Repository) Create(ctx context.Context, m *Message) error {
	query := `
		INSERT INTO messages (id, pod_id, sender_id, body, attachment_url, created_at)
		VALUES (?, ?, ?, ?, ?, ?);
	`
	createdAtStr := m.CreatedAt.UTC().Format("2006-01-02T15:04:05.000000Z")

	_, err := r.writeDB.ExecContext(ctx, query,
		m.ID, m.PodID, m.SenderID, m.Body, m.AttachmentURL, createdAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create message: %w", err)
	}
	return nil
}

// GetByID retrieves a message record by its ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Message, error) {
	query := `
		SELECT id, pod_id, sender_id, body, attachment_url, created_at
		FROM messages
		WHERE id = ?;
	`
	var m Message
	var createdAtStr string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&m.ID, &m.PodID, &m.SenderID, &m.Body, &m.AttachmentURL, &createdAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrMessageNotFound
		}
		return nil, fmt.Errorf("failed to get message: %w", err)
	}

	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		m.CreatedAt = parsed
	}

	return &m, nil
}

// ListMessages performs cursor pagination on messages in a pod.
// If beforeID is provided, it retrieves messages older than that message.
// Returns messages ordered oldest-to-newest within the page, and the next_cursor (or nil if exhausted).
func (r *Repository) ListMessages(ctx context.Context, podID string, beforeID *string, limit int) ([]*Message, *string, error) {
	if limit <= 0 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}

	var baseQuery string
	var args []any

	if beforeID != nil && *beforeID != "" {
		// Look up the 'before' message to get its created_at timestamp
		var beforeCreatedAt string
		err := r.readDB.QueryRowContext(ctx, `SELECT created_at FROM messages WHERE id = ? AND pod_id = ?;`, *beforeID, podID).Scan(&beforeCreatedAt)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil, nil, ErrMessageNotFound
			}
			return nil, nil, fmt.Errorf("failed to lookup before message: %w", err)
		}

		baseQuery = `
			SELECT id, pod_id, sender_id, body, attachment_url, created_at
			FROM messages
			WHERE pod_id = ? AND (created_at < ? OR (created_at = ? AND id < ?))
			ORDER BY created_at DESC, id DESC
			LIMIT ?;
		`
		args = []any{podID, beforeCreatedAt, beforeCreatedAt, *beforeID, limit + 1}
	} else {
		baseQuery = `
			SELECT id, pod_id, sender_id, body, attachment_url, created_at
			FROM messages
			WHERE pod_id = ?
			ORDER BY created_at DESC, id DESC
			LIMIT ?;
		`
		args = []any{podID, limit + 1}
	}

	rows, err := r.readDB.QueryContext(ctx, baseQuery, args...)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to list messages: %w", err)
	}
	defer rows.Close()

	var results []*Message
	for rows.Next() {
		var m Message
		var createdAtStr string

		if err := rows.Scan(&m.ID, &m.PodID, &m.SenderID, &m.Body, &m.AttachmentURL, &createdAtStr); err != nil {
			return nil, nil, fmt.Errorf("failed to scan message: %w", err)
		}
		if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
			m.CreatedAt = parsed
		}
		results = append(results, &m)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, fmt.Errorf("row error listing messages: %w", err)
	}

	var nextCursor *string
	if len(results) > limit {
		// The oldest item within this page is at results[limit-1]
		cursorVal := results[limit-1].ID
		nextCursor = &cursorVal
		results = results[:limit]
	}

	// Reverse results so that within the page they are returned oldest-to-newest
	for i, j := 0, len(results)-1; i < j; i, j = i+1, j-1 {
		results[i], results[j] = results[j], results[i]
	}

	if results == nil {
		results = make([]*Message, 0)
	}

	return results, nextCursor, nil
}
