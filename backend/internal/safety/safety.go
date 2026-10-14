package safety

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/chat"
	"github.com/abshwabu/pair/backend/internal/pods"
)

// ReportStatus represents the review lifecycle of a moderation report.
type ReportStatus string

const (
	ReportStatusOpen      ReportStatus = "open"
	ReportStatusReviewed  ReportStatus = "reviewed"
	ReportStatusDismissed ReportStatus = "dismissed"
)

// Sentinel errors for safety domain.
var (
	ErrReportNotFound = errors.New("report not found")
	ErrBlockNotFound  = errors.New("block not found")
	ErrSelfReport     = errors.New("cannot report yourself")
	ErrSelfBlock      = errors.New("cannot block yourself")
	ErrDuplicateBlock = errors.New("user is already blocked")
	ErrForbidden      = errors.New("forbidden: not authorized")
	ErrUserNotFound   = errors.New("user not found")
	ErrInvalidStatus  = errors.New("invalid status: must be 'reviewed' or 'dismissed'")
)

// Report represents a report record in the reports table.
type Report struct {
	ID             string       `json:"id"`
	ReporterID     string       `json:"reporter_id"`
	ReportedUserID string       `json:"reported_user_id"`
	PodID          *string      `json:"pod_id"`
	Reason         string       `json:"reason"`
	Status         ReportStatus `json:"status"`
	CreatedAt      time.Time    `json:"created_at"`
}

// UserSummary provides brief public information about a user in safety contexts.
type UserSummary struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}

// ReportDetail includes reporter and reported user metadata for admin reviews.
type ReportDetail struct {
	ID           string       `json:"id"`
	Reporter     UserSummary  `json:"reporter"`
	ReportedUser UserSummary  `json:"reported_user"`
	PodID        *string      `json:"pod_id"`
	Reason       string       `json:"reason"`
	Status       ReportStatus `json:"status"`
	CreatedAt    time.Time    `json:"created_at"`
}

// Block represents a block record in the blocks table.
type Block struct {
	ID            string    `json:"id"`
	UserID        string    `json:"user_id"`
	BlockedUserID string    `json:"blocked_user_id"`
	CreatedAt     time.Time `json:"created_at"`
}

// BlockedUserDetail represents a blocked user with their public profile.
type BlockedUserDetail struct {
	ID            string    `json:"id"` // block ID
	BlockedUserID string    `json:"blocked_user_id"`
	Name          string    `json:"name"`
	AvatarURL     *string   `json:"avatar_url"`
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

// CreateReport inserts a new report into the database.
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

// GetReportByID retrieves a report by ID.
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
			return nil, ErrReportNotFound
		}
		return nil, fmt.Errorf("failed to get report: %w", err)
	}

	rep.Status = ReportStatus(statusStr)
	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		rep.CreatedAt = parsed
	}

	return &rep, nil
}

// ListReports retrieves reports ordered newest first, optionally filtered by status.
func (r *Repository) ListReports(ctx context.Context, status *ReportStatus) ([]ReportDetail, error) {
	query := `
		SELECT r.id, r.reporter_id, u1.name, u1.email,
		       r.reported_user_id, u2.name, u2.email,
		       r.pod_id, r.reason, r.status, r.created_at
		FROM reports r
		JOIN users u1 ON r.reporter_id = u1.id
		JOIN users u2 ON r.reported_user_id = u2.id
		WHERE (? IS NULL OR r.status = ?)
		ORDER BY r.created_at DESC;
	`
	var statusFilter any
	if status != nil && *status != "" {
		statusFilter = string(*status)
	}

	rows, err := r.readDB.QueryContext(ctx, query, statusFilter, statusFilter)
	if err != nil {
		return nil, fmt.Errorf("failed to list reports: %w", err)
	}
	defer rows.Close()

	reports := make([]ReportDetail, 0)
	for rows.Next() {
		var rd ReportDetail
		var statusStr, createdAtStr string
		var podID sql.NullString

		err := rows.Scan(
			&rd.ID,
			&rd.Reporter.ID, &rd.Reporter.Name, &rd.Reporter.Email,
			&rd.ReportedUser.ID, &rd.ReportedUser.Name, &rd.ReportedUser.Email,
			&podID, &rd.Reason, &statusStr, &createdAtStr,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan report detail: %w", err)
		}

		if podID.Valid {
			val := podID.String
			rd.PodID = &val
		}
		rd.Status = ReportStatus(statusStr)
		if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
			rd.CreatedAt = parsed
		}

		reports = append(reports, rd)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("reports rows error: %w", err)
	}

	return reports, nil
}

// UpdateReportStatus updates the status of an existing report.
func (r *Repository) UpdateReportStatus(ctx context.Context, id string, status ReportStatus) (*Report, error) {
	if status != ReportStatusReviewed && status != ReportStatusDismissed {
		return nil, ErrInvalidStatus
	}

	query := `
		UPDATE reports
		SET status = ?
		WHERE id = ?;
	`
	res, err := r.writeDB.ExecContext(ctx, query, string(status), id)
	if err != nil {
		return nil, fmt.Errorf("failed to update report status: %w", err)
	}

	rows, err := res.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rows == 0 {
		return nil, ErrReportNotFound
	}

	return r.GetReportByID(ctx, id)
}

// CreateBlock creates a block record. If the two users share an active pod,
// it dissolves the pod (by leaving both users) within the SAME transaction,
// and closes live WebSocket connections on the chat hub.
func (r *Repository) CreateBlock(ctx context.Context, userID, blockedUserID string, podsRepo *pods.Repository, chatHub *chat.Hub) (*Block, []string, error) {
	if userID == blockedUserID {
		return nil, nil, ErrSelfBlock
	}

	// 1. Verify blocked user exists
	var count int
	err := r.readDB.QueryRowContext(ctx, `SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL;`, blockedUserID).Scan(&count)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to verify blocked user: %w", err)
	}
	if count == 0 {
		return nil, nil, ErrUserNotFound
	}

	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to begin block transaction: %w", err)
	}
	defer tx.Rollback()

	// 2. Check for duplicate block
	var existingCount int
	err = tx.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM blocks
		WHERE user_id = ? AND blocked_user_id = ?;
	`, userID, blockedUserID).Scan(&existingCount)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to check existing block: %w", err)
	}
	if existingCount > 0 {
		return nil, nil, ErrDuplicateBlock
	}

	// 3. Insert block
	blockID := uuid.NewString()
	now := time.Now().UTC()
	createdAtStr := now.Format(time.RFC3339)

	_, err = tx.ExecContext(ctx, `
		INSERT INTO blocks (id, user_id, blocked_user_id, created_at)
		VALUES (?, ?, ?, ?);
	`, blockID, userID, blockedUserID, createdAtStr)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return nil, nil, ErrDuplicateBlock
		}
		return nil, nil, fmt.Errorf("failed to insert block: %w", err)
	}

	// 4. Find any shared active pods between userID and blockedUserID
	sharedQuery := `
		SELECT p.id
		FROM pods p
		JOIN pod_members pm1 ON p.id = pm1.pod_id AND pm1.user_id = ? AND pm1.left_at IS NULL
		JOIN pod_members pm2 ON p.id = pm2.pod_id AND pm2.user_id = ? AND pm2.left_at IS NULL
		WHERE p.status = 'active';
	`
	rows, err := tx.QueryContext(ctx, sharedQuery, userID, blockedUserID)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to query shared active pods: %w", err)
	}

	var sharedPodIDs []string
	for rows.Next() {
		var podID string
		if err := rows.Scan(&podID); err != nil {
			rows.Close()
			return nil, nil, fmt.Errorf("failed to scan shared pod id: %w", err)
		}
		sharedPodIDs = append(sharedPodIDs, podID)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, nil, fmt.Errorf("shared pods rows error: %w", err)
	}

	// 5. Dissolve shared active pods by leaving both members in the SAME transaction
	for _, podID := range sharedPodIDs {
		// Use podsRepo.LeaveUserTx to ensure both leave and status becomes 'dissolved'
		if podsRepo != nil {
			_ = podsRepo.LeaveUserTx(ctx, tx, podID, userID)
			_ = podsRepo.LeaveUserTx(ctx, tx, podID, blockedUserID)
		} else {
			_ = pods.LeaveUserTx(ctx, tx, podID, userID)
			_ = pods.LeaveUserTx(ctx, tx, podID, blockedUserID)
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, nil, fmt.Errorf("failed to commit block transaction: %w", err)
	}

	// 6. Close live WebSocket connections for dissolved pods
	if chatHub != nil {
		for _, podID := range sharedPodIDs {
			chatHub.ClosePod(podID)
		}
	}

	block := &Block{
		ID:            blockID,
		UserID:        userID,
		BlockedUserID: blockedUserID,
		CreatedAt:     now,
	}

	return block, sharedPodIDs, nil
}

// ListBlocks retrieves the authenticated user's blocks with public profile metadata.
func (r *Repository) ListBlocks(ctx context.Context, userID string) ([]BlockedUserDetail, error) {
	query := `
		SELECT b.id, b.blocked_user_id, u.name, u.avatar_url, b.created_at
		FROM blocks b
		JOIN users u ON b.blocked_user_id = u.id
		WHERE b.user_id = ?
		ORDER BY b.created_at DESC;
	`
	rows, err := r.readDB.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to list blocks: %w", err)
	}
	defer rows.Close()

	blocks := make([]BlockedUserDetail, 0)
	for rows.Next() {
		var b BlockedUserDetail
		var avatarURL sql.NullString
		var createdAtStr string

		err := rows.Scan(&b.ID, &b.BlockedUserID, &b.Name, &avatarURL, &createdAtStr)
		if err != nil {
			return nil, fmt.Errorf("failed to scan blocked user detail: %w", err)
		}

		if avatarURL.Valid {
			val := avatarURL.String
			b.AvatarURL = &val
		}
		if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
			b.CreatedAt = parsed
		}

		blocks = append(blocks, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("blocks rows error: %w", err)
	}

	return blocks, nil
}

// DeleteBlock unblocks a user. Enforces that only the creator/owner can delete the block.
func (r *Repository) DeleteBlock(ctx context.Context, idOrBlockedUserID, currentUserID string) error {
	// 1. Locate the block by block ID or blocked_user_id
	var actualBlockID, blockOwnerID string
	err := r.readDB.QueryRowContext(ctx, `
		SELECT id, user_id
		FROM blocks
		WHERE id = ? OR (user_id = ? AND blocked_user_id = ?);
	`, idOrBlockedUserID, currentUserID, idOrBlockedUserID).Scan(&actualBlockID, &blockOwnerID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrBlockNotFound
		}
		return fmt.Errorf("failed to query block: %w", err)
	}

	// 2. Enforce owner authorization
	if blockOwnerID != currentUserID {
		return ErrForbidden
	}

	// 3. Delete block
	_, err = r.writeDB.ExecContext(ctx, `DELETE FROM blocks WHERE id = ?;`, actualBlockID)
	if err != nil {
		return fmt.Errorf("failed to delete block: %w", err)
	}

	return nil
}
