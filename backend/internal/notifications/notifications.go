package notifications

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
)

var (
	// ErrNotificationNotFound is returned when a notification is not found.
	ErrNotificationNotFound = errors.New("notification not found")
	// ErrForbidden is returned when a user attempts to access or modify another user's notification.
	ErrForbidden = errors.New("forbidden: you do not own this notification")
	// ErrCursorNotFound is returned when the pagination cursor message/notification is not found.
	ErrCursorNotFound = errors.New("cursor notification not found")
)

// Notification represents a notification record in SQLite.
type Notification struct {
	ID        string          `json:"id"`
	UserID    string          `json:"user_id"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
	SentAt    *time.Time      `json:"sent_at,omitempty"`
	ReadAt    *time.Time      `json:"read_at,omitempty"`
	CreatedAt time.Time       `json:"created_at"`
}

// UnsentNotification contains notification details and the target user's FCM token for push delivery.
type UnsentNotification struct {
	ID        string
	UserID    string
	Type      string
	Payload   json.RawMessage
	CreatedAt time.Time
	FCMToken  *string
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
		n.ID, n.UserID, n.Type, string(n.Payload), sentAtStr, readAtStr, createdAtStr,
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
	var payloadStr string
	var sentAtStr, readAtStr, createdAtStr *string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&n.ID, &n.UserID, &n.Type, &payloadStr, &sentAtStr, &readAtStr, &createdAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotificationNotFound
		}
		return nil, fmt.Errorf("failed to get notification: %w", err)
	}

	n.Payload = json.RawMessage(payloadStr)
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

// MarkSent updates sent_at for a notification.
func (r *Repository) MarkSent(ctx context.Context, id string, sentAt time.Time) error {
	query := `UPDATE notifications SET sent_at = ? WHERE id = ?;`
	sentAtStr := sentAt.UTC().Format(time.RFC3339)
	res, err := r.writeDB.ExecContext(ctx, query, sentAtStr, id)
	if err != nil {
		return fmt.Errorf("failed to mark notification sent: %w", err)
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rows == 0 {
		return ErrNotificationNotFound
	}
	return nil
}

// MarkRead marks a notification as read, ensuring the requester is the owner.
func (r *Repository) MarkRead(ctx context.Context, id, userID string, readAt time.Time) (*Notification, error) {
	n, err := r.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if n.UserID != userID {
		return nil, ErrForbidden
	}

	nowStr := readAt.UTC().Format(time.RFC3339)
	query := `UPDATE notifications SET read_at = ? WHERE id = ?;`
	if _, err := r.writeDB.ExecContext(ctx, query, nowStr, id); err != nil {
		return nil, fmt.Errorf("failed to mark notification as read: %w", err)
	}

	return r.GetByID(ctx, id)
}

// ListByUserID performs cursor pagination on notifications for a user, newest first.
func (r *Repository) ListByUserID(ctx context.Context, userID string, beforeID *string, limit int) ([]*Notification, *string, error) {
	if limit <= 0 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}

	var baseQuery string
	var args []any

	if beforeID != nil && *beforeID != "" {
		var beforeCreatedAt string
		err := r.readDB.QueryRowContext(ctx, `SELECT created_at FROM notifications WHERE id = ? AND user_id = ?;`, *beforeID, userID).Scan(&beforeCreatedAt)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil, nil, ErrCursorNotFound
			}
			return nil, nil, fmt.Errorf("failed to lookup before notification: %w", err)
		}

		baseQuery = `
			SELECT id, user_id, type, payload, sent_at, read_at, created_at
			FROM notifications
			WHERE user_id = ? AND (created_at < ? OR (created_at = ? AND id < ?))
			ORDER BY created_at DESC, id DESC
			LIMIT ?;
		`
		args = []any{userID, beforeCreatedAt, beforeCreatedAt, *beforeID, limit + 1}
	} else {
		baseQuery = `
			SELECT id, user_id, type, payload, sent_at, read_at, created_at
			FROM notifications
			WHERE user_id = ?
			ORDER BY created_at DESC, id DESC
			LIMIT ?;
		`
		args = []any{userID, limit + 1}
	}

	rows, err := r.readDB.QueryContext(ctx, baseQuery, args...)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to list notifications: %w", err)
	}
	defer rows.Close()

	var results []*Notification
	for rows.Next() {
		var n Notification
		var payloadStr string
		var sentAtStr, readAtStr, createdAtStr *string

		if err := rows.Scan(&n.ID, &n.UserID, &n.Type, &payloadStr, &sentAtStr, &readAtStr, &createdAtStr); err != nil {
			return nil, nil, fmt.Errorf("failed to scan notification: %w", err)
		}
		n.Payload = json.RawMessage(payloadStr)
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
		results = append(results, &n)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, fmt.Errorf("row error listing notifications: %w", err)
	}

	var nextCursor *string
	if len(results) > limit {
		cursorVal := results[limit-1].ID
		nextCursor = &cursorVal
		results = results[:limit]
	}

	return results, nextCursor, nil
}

// GetUnsent retrieves notifications where sent_at IS NULL along with user's FCM token, oldest first.
func (r *Repository) GetUnsent(ctx context.Context, limit int) ([]*UnsentNotification, error) {
	if limit <= 0 {
		limit = 100
	}
	query := `
		SELECT n.id, n.user_id, n.type, n.payload, n.created_at, u.fcm_token
		FROM notifications n
		JOIN users u ON n.user_id = u.id
		WHERE n.sent_at IS NULL AND u.deleted_at IS NULL
		ORDER BY n.created_at ASC
		LIMIT ?;
	`
	rows, err := r.readDB.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to query unsent notifications: %w", err)
	}
	defer rows.Close()

	var unsent []*UnsentNotification
	for rows.Next() {
		var item UnsentNotification
		var payloadStr string
		var createdAtStr string
		var fcmToken *string

		if err := rows.Scan(&item.ID, &item.UserID, &item.Type, &payloadStr, &createdAtStr, &fcmToken); err != nil {
			return nil, fmt.Errorf("failed to scan unsent notification: %w", err)
		}
		item.Payload = json.RawMessage(payloadStr)
		item.FCMToken = fcmToken
		if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
			item.CreatedAt = parsed
		}
		unsent = append(unsent, &item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("row error querying unsent notifications: %w", err)
	}
	return unsent, nil
}

// Notifier defines the interface for emitting notifications throughout the system.
type Notifier interface {
	Send(ctx context.Context, userID, notificationType string, payload map[string]any) error
}

// Service delivers notifications to the outbox table and notifies background workers.
type Service struct {
	repo     *Repository
	readDB   *sql.DB
	notifyCh chan struct{}
}

// NewService creates a new notifications Service.
func NewService(repo *Repository, readDB *sql.DB) *Service {
	return &Service{
		repo:     repo,
		readDB:   readDB,
		notifyCh: make(chan struct{}, 1),
	}
}

// NotifyChan returns the worker wakeup channel.
func (s *Service) NotifyChan() <-chan struct{} {
	return s.notifyCh
}

// Send records an unsent notification and non-blockingly signals the worker.
func (s *Service) Send(ctx context.Context, userID, notificationType string, payload map[string]any) error {
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal notification payload: %w", err)
	}

	n := &Notification{
		ID:        uuid.NewString(),
		UserID:    userID,
		Type:      notificationType,
		Payload:   payloadBytes,
		SentAt:    nil,
		ReadAt:    nil,
		CreatedAt: time.Now().UTC(),
	}

	if err := s.repo.Create(ctx, n); err != nil {
		return err
	}

	// Wakeup worker
	select {
	case s.notifyCh <- struct{}{}:
	default:
	}

	return nil
}

// EmitStreakBroken satisfies the jobs.NotificationService interface.
// It sends a streak_broken notification to all active members of the pod.
func (s *Service) EmitStreakBroken(ctx context.Context, podID string) error {
	query := `
		SELECT user_id
		FROM pod_members
		WHERE pod_id = ? AND (left_at IS NULL OR left_at = '');
	`
	rows, err := s.readDB.QueryContext(ctx, query, podID)
	if err != nil {
		return fmt.Errorf("failed to query pod members for streak_broken: %w", err)
	}
	defer rows.Close()

	var userIDs []string
	for rows.Next() {
		var uid string
		if err := rows.Scan(&uid); err != nil {
			return fmt.Errorf("failed to scan member user id: %w", err)
		}
		userIDs = append(userIDs, uid)
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("rows error querying pod members: %w", err)
	}

	for _, uid := range userIDs {
		payload := map[string]any{
			"type":    "streak_broken",
			"pod_id":  podID,
			"title":   "Streak Broken",
			"body":    "Your accountability streak for this pod has reset.",
		}
		if err := s.Send(ctx, uid, "streak_broken", payload); err != nil {
			slog.Error("failed to send streak_broken notification", "user_id", uid, "error", err)
		}
	}
	return nil
}
