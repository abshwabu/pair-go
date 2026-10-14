package safety

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// ReportStatus represents status of moderation report.
type ReportStatus string

const (
	ReportStatusOpen      ReportStatus = "open"
	ReportStatusReviewed  ReportStatus = "reviewed"
	ReportStatusDismissed ReportStatus = "dismissed"
)

// Report represents a user or pod report in the reports table.
type Report struct {
	ID             string       `json:"id"`
	ReporterID     string       `json:"reporter_id"`
	ReportedUserID string       `json:"reported_user_id"`
	PodID          *string      `json:"pod_id,omitempty"`
	Reason         string       `json:"reason"`
	Status         ReportStatus `json:"status"`
	CreatedAt      time.Time    `json:"created_at"`
}

// Block represents a block record in the blocks table.
type Block struct {
	ID            string    `json:"id"`
	UserID        string    `json:"user_id"`
	BlockedUserID string    `json:"blocked_user_id"`
	CreatedAt     time.Time `json:"created_at"`
}

// Repository handles safety database operations (reports and blocks).
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewRepository creates a new safety Repository.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// CreateReport inserts a new report record.
func (r *Repository) CreateReport(ctx context.Context, rep *Report) error {
	query := `
		INSERT INTO reports (id, reporter_id, reported_user_id, pod_id, reason, status, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?);
	`
	createdAtStr := rep.CreatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		rep.ID, rep.ReporterID, rep.ReportedUserID, rep.PodID, rep.Reason, string(rep.Status), createdAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create report: %w", err)
	}
	return nil
}

// GetReportByID retrieves a report record by its ID.
func (r *Repository) GetReportByID(ctx context.Context, id string) (*Report, error) {
	query := `
		SELECT id, reporter_id, reported_user_id, pod_id, reason, status, created_at
		FROM reports
		WHERE id = ?;
	`
	var rep Report
	var statusStr, createdAtStr string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&rep.ID, &rep.ReporterID, &rep.ReportedUserID, &rep.PodID, &rep.Reason, &statusStr, &createdAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errors.New("report not found")
		}
		return nil, fmt.Errorf("failed to get report: %w", err)
	}

	rep.Status = ReportStatus(statusStr)
	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		rep.CreatedAt = parsed
	}

	return &rep, nil
}

// CreateBlock inserts a new block record.
func (r *Repository) CreateBlock(ctx context.Context, b *Block) error {
	query := `
		INSERT INTO blocks (id, user_id, blocked_user_id, created_at)
		VALUES (?, ?, ?, ?);
	`
	createdAtStr := b.CreatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query, b.ID, b.UserID, b.BlockedUserID, createdAtStr)
	if err != nil {
		return fmt.Errorf("failed to create block: %w", err)
	}
	return nil
}

// GetBlockByID retrieves a block record by its ID.
func (r *Repository) GetBlockByID(ctx context.Context, id string) (*Block, error) {
	query := `
		SELECT id, user_id, blocked_user_id, created_at
		FROM blocks
		WHERE id = ?;
	`
	var b Block
	var createdAtStr string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&b.ID, &b.UserID, &b.BlockedUserID, &createdAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errors.New("block not found")
		}
		return nil, fmt.Errorf("failed to get block: %w", err)
	}

	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		b.CreatedAt = parsed
	}

	return &b, nil
}
