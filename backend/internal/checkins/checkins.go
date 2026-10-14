package checkins

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// CheckIn represents a daily check-in in the check_ins table.
type CheckIn struct {
	ID          string    `json:"id"`
	PodID       string    `json:"pod_id"`
	UserID      string    `json:"user_id"`
	CheckInDate string    `json:"check_in_date"` // YYYY-MM-DD (UTC)
	Note        *string   `json:"note,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

// Streak represents an accountability streak in the streaks table.
type Streak struct {
	ID              string    `json:"id"`
	PodID           string    `json:"pod_id"`
	CurrentStreak   int       `json:"current_streak"`
	BestStreak      int       `json:"best_streak"`
	LastCheckInDate *string   `json:"last_check_in_date,omitempty"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// Repository handles check_ins and streaks database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewRepository creates a new checkins Repository.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// CreateCheckIn inserts a new check_in record.
func (r *Repository) CreateCheckIn(ctx context.Context, c *CheckIn) error {
	query := `
		INSERT INTO check_ins (id, pod_id, user_id, check_in_date, note, created_at)
		VALUES (?, ?, ?, ?, ?, ?);
	`
	createdAtStr := c.CreatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		c.ID, c.PodID, c.UserID, c.CheckInDate, c.Note, createdAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create check-in: %w", err)
	}
	return nil
}

// GetCheckInByID retrieves a check-in record by its ID.
func (r *Repository) GetCheckInByID(ctx context.Context, id string) (*CheckIn, error) {
	query := `
		SELECT id, pod_id, user_id, check_in_date, note, created_at
		FROM check_ins
		WHERE id = ?;
	`
	var c CheckIn
	var createdAtStr string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&c.ID, &c.PodID, &c.UserID, &c.CheckInDate, &c.Note, &createdAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errors.New("check-in not found")
		}
		return nil, fmt.Errorf("failed to get check-in: %w", err)
	}

	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		c.CreatedAt = parsed
	}

	return &c, nil
}

// CreateStreak inserts a new streak record.
func (r *Repository) CreateStreak(ctx context.Context, s *Streak) error {
	query := `
		INSERT INTO streaks (id, pod_id, current_streak, best_streak, last_check_in_date, updated_at)
		VALUES (?, ?, ?, ?, ?, ?);
	`
	updatedAtStr := s.UpdatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		s.ID, s.PodID, s.CurrentStreak, s.BestStreak, s.LastCheckInDate, updatedAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create streak: %w", err)
	}
	return nil
}

// GetStreakByID retrieves a streak record by its ID.
func (r *Repository) GetStreakByID(ctx context.Context, id string) (*Streak, error) {
	query := `
		SELECT id, pod_id, current_streak, best_streak, last_check_in_date, updated_at
		FROM streaks
		WHERE id = ?;
	`
	var s Streak
	var updatedAtStr string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&s.ID, &s.PodID, &s.CurrentStreak, &s.BestStreak, &s.LastCheckInDate, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errors.New("streak not found")
		}
		return nil, fmt.Errorf("failed to get streak: %w", err)
	}

	if parsed, err := time.Parse(time.RFC3339, updatedAtStr); err == nil {
		s.UpdatedAt = parsed
	}

	return &s, nil
}
