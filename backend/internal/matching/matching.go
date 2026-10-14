package matching

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/goals"
)

// PodRequestStatus represents the state of a matching request.
type PodRequestStatus string

const (
	PodRequestStatusOpen      PodRequestStatus = "open"
	PodRequestStatusMatched   PodRequestStatus = "matched"
	PodRequestStatusCancelled PodRequestStatus = "cancelled"
)

// Sentinel errors for matching domain.
var (
	ErrRequestNotFound = errors.New("pod request not found")
	ErrForbidden       = errors.New("forbidden: you do not own this request")
	ErrAlreadyMatched  = errors.New("conflict: request has already been matched")
	ErrPairingConflict = errors.New("conflict: one or both requests are no longer available for matching")
)

// PodRequest represents a match request in the pod_requests table.
type PodRequest struct {
	ID                     string           `json:"id"`
	UserID                 string           `json:"user_id"`
	GoalID                 string           `json:"goal_id"`
	Status                 PodRequestStatus `json:"status"`
	TimezoneToleranceHours int              `json:"timezone_tolerance_hours"`
	Language               string           `json:"language"`
	PodID                  *string          `json:"pod_id,omitempty"`
	CreatedAt              time.Time        `json:"created_at"`
	UpdatedAt              time.Time        `json:"updated_at"`
}

// Request contains all attributes needed for candidate scoring and pairing.
type Request struct {
	ID                     string             `json:"id"`
	UserID                 string             `json:"user_id"`
	GoalID                 string             `json:"goal_id"`
	GoalCategory           goals.GoalCategory `json:"goal_category"`
	Pace                   goals.GoalPace     `json:"pace"`
	Timezone               string             `json:"timezone"`
	TimezoneToleranceHours int                `json:"timezone_tolerance_hours"`
	Language               string             `json:"language"`
	CreatedAt              time.Time          `json:"created_at"`
}

// MinScoreThreshold is the minimum score required to consider two requests a match.
const MinScoreThreshold = 50

func paceLevel(p goals.GoalPace) (int, bool) {
	switch p {
	case goals.GoalPaceRelaxed:
		return 0, true
	case goals.GoalPaceSteady:
		return 1, true
	case goals.GoalPaceIntense:
		return 2, true
	default:
		return -1, false
	}
}

func timezoneOffsetHours(tz string, ref time.Time) (float64, error) {
	loc, err := time.LoadLocation(strings.TrimSpace(tz))
	if err != nil {
		return 0, err
	}
	_, offsetSec := ref.In(loc).Zone()
	return float64(offsetSec) / 3600.0, nil
}

func timezoneDiffHours(tzA, tzB string, ref time.Time) (float64, error) {
	offA, err := timezoneOffsetHours(tzA, ref)
	if err != nil {
		return 0, err
	}
	offB, err := timezoneOffsetHours(tzB, ref)
	if err != nil {
		return 0, err
	}
	diff := math.Abs(offA - offB)
	if diff > 12.0 {
		diff = 24.0 - diff
	}
	return diff, nil
}

// Score evaluates matching compatibility between two candidate requests.
// It is a pure function returning (score, true) if compatible, or (0, false) if incompatible.
func Score(a, b Request) (int, bool) {
	// 1. Cannot match a user with themselves
	if a.UserID == b.UserID {
		return 0, false
	}

	// 2. Same goal category (hard requirement)
	if a.GoalCategory == "" || a.GoalCategory != b.GoalCategory {
		return 0, false
	}

	// 3. Same language (hard requirement)
	langA := strings.ToLower(strings.TrimSpace(a.Language))
	langB := strings.ToLower(strings.TrimSpace(b.Language))
	if langA == "" || langA != langB {
		return 0, false
	}

	// 4. Timezone offset difference within BOTH users' stated tolerance (hard requirement)
	ref := time.Now().UTC()
	diffHours, err := timezoneDiffHours(a.Timezone, b.Timezone, ref)
	if err != nil {
		return 0, false
	}

	if diffHours > float64(a.TimezoneToleranceHours) || diffHours > float64(b.TimezoneToleranceHours) {
		return 0, false
	}

	// 5. Compatible pace (soft score: same pace best, adjacent pace partial)
	levelA, okA := paceLevel(a.Pace)
	levelB, okB := paceLevel(b.Pace)
	if !okA || !okB {
		return 0, false
	}

	paceDiff := levelA - levelB
	if paceDiff < 0 {
		paceDiff = -paceDiff
	}

	var paceScore int
	switch paceDiff {
	case 0:
		paceScore = 40 // Same pace: best
	case 1:
		paceScore = 20 // Adjacent pace: partial
	default:
		paceScore = 0 // Distant pace
	}

	// Timezone closeness bonus: up to 12 points for closer timezones
	tzBonus := int(math.Round(12.0 - diffHours))
	if tzBonus < 0 {
		tzBonus = 0
	}

	baseScore := 50
	totalScore := baseScore + paceScore + tzBonus

	if totalScore < MinScoreThreshold {
		return 0, false
	}

	return totalScore, true
}

// Repository handles pod_requests database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewRepository creates a new matching Repository.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// Create inserts a new pod_request record.
func (r *Repository) Create(ctx context.Context, pr *PodRequest) error {
	query := `
		INSERT INTO pod_requests (
			id, user_id, goal_id, status, timezone_tolerance_hours,
			language, pod_id, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
	`
	createdAtStr := pr.CreatedAt.UTC().Format(time.RFC3339)
	updatedAtStr := pr.UpdatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		pr.ID, pr.UserID, pr.GoalID, string(pr.Status), pr.TimezoneToleranceHours,
		pr.Language, pr.PodID, createdAtStr, updatedAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create pod request: %w", err)
	}
	return nil
}

// GetByID retrieves a pod request record by its ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*PodRequest, error) {
	query := `
		SELECT id, user_id, goal_id, status, timezone_tolerance_hours,
		       language, pod_id, created_at, updated_at
		FROM pod_requests
		WHERE id = ?;
	`
	var pr PodRequest
	var statusStr, createdAtStr, updatedAtStr string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&pr.ID, &pr.UserID, &pr.GoalID, &statusStr, &pr.TimezoneToleranceHours,
		&pr.Language, &pr.PodID, &createdAtStr, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrRequestNotFound
		}
		return nil, fmt.Errorf("failed to get pod request: %w", err)
	}

	pr.Status = PodRequestStatus(statusStr)
	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		pr.CreatedAt = parsed
	}
	if parsed, err := time.Parse(time.RFC3339, updatedAtStr); err == nil {
		pr.UpdatedAt = parsed
	}

	return &pr, nil
}

// GetRequestDetails retrieves a pod request joined with user timezone and goal category/pace.
func (r *Repository) GetRequestDetails(ctx context.Context, id string) (*Request, error) {
	query := `
		SELECT pr.id, pr.user_id, pr.goal_id, g.category, g.pace, u.timezone,
		       pr.timezone_tolerance_hours, pr.language, pr.created_at
		FROM pod_requests pr
		JOIN users u ON pr.user_id = u.id
		JOIN goals g ON pr.goal_id = g.id
		WHERE pr.id = ?;
	`
	var req Request
	var catStr, paceStr, createdAtStr string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&req.ID, &req.UserID, &req.GoalID, &catStr, &paceStr, &req.Timezone,
		&req.TimezoneToleranceHours, &req.Language, &createdAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrRequestNotFound
		}
		return nil, fmt.Errorf("failed to get request details: %w", err)
	}

	req.GoalCategory = goals.GoalCategory(catStr)
	req.Pace = goals.GoalPace(paceStr)
	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		req.CreatedAt = parsed
	}

	return &req, nil
}

// HasOpenRequest returns true if the user already has a pod request in 'open' status.
func (r *Repository) HasOpenRequest(ctx context.Context, userID string) (bool, error) {
	query := `
		SELECT EXISTS (
			SELECT 1 FROM pod_requests
			WHERE user_id = ? AND status = 'open'
		);
	`
	var exists int
	err := r.readDB.QueryRowContext(ctx, query, userID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check open request: %w", err)
	}
	return exists == 1, nil
}

// IsUserInActivePod returns true if the user is currently an active member of an active pod.
func (r *Repository) IsUserInActivePod(ctx context.Context, userID string) (bool, error) {
	query := `
		SELECT EXISTS (
			SELECT 1 FROM pod_members pm
			JOIN pods p ON pm.pod_id = p.id
			WHERE pm.user_id = ?
			  AND p.status = 'active'
			  AND (pm.left_at IS NULL OR pm.left_at = '')
		);
	`
	var exists int
	err := r.readDB.QueryRowContext(ctx, query, userID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check active pod membership: %w", err)
	}
	return exists == 1, nil
}

// Cancel updates an open request status to 'cancelled'.
func (r *Repository) Cancel(ctx context.Context, id, userID string) error {
	pr, err := r.GetByID(ctx, id)
	if err != nil {
		return err
	}

	if pr.UserID != userID {
		return ErrForbidden
	}

	if pr.Status == PodRequestStatusMatched {
		return ErrAlreadyMatched
	}

	if pr.Status == PodRequestStatusCancelled {
		return nil
	}

	now := time.Now().UTC().Format(time.RFC3339)
	query := `
		UPDATE pod_requests
		SET status = 'cancelled', updated_at = ?
		WHERE id = ? AND status = 'open';
	`
	res, err := r.writeDB.ExecContext(ctx, query, now, id)
	if err != nil {
		return fmt.Errorf("failed to cancel pod request: %w", err)
	}

	rows, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rows == 0 {
		return ErrAlreadyMatched
	}

	return nil
}

// FindCandidateRequests finds all candidate open requests matching the category and language, excluding blocked pairs.
func (r *Repository) FindCandidateRequests(ctx context.Context, currentReq *Request) ([]*Request, error) {
	query := `
		SELECT pr.id, pr.user_id, pr.goal_id, g.category, g.pace, u.timezone,
		       pr.timezone_tolerance_hours, pr.language, pr.created_at
		FROM pod_requests pr
		JOIN users u ON pr.user_id = u.id
		JOIN goals g ON pr.goal_id = g.id
		WHERE pr.status = 'open'
		  AND pr.id != ?
		  AND pr.user_id != ?
		  AND g.category = ?
		  AND LOWER(pr.language) = LOWER(?)
		  AND NOT EXISTS (
		      SELECT 1 FROM blocks b
		      WHERE (b.user_id = ? AND b.blocked_user_id = pr.user_id)
		         OR (b.user_id = pr.user_id AND b.blocked_user_id = ?)
		  )
		ORDER BY pr.created_at ASC;
	`
	rows, err := r.readDB.QueryContext(ctx, query,
		currentReq.ID, currentReq.UserID, string(currentReq.GoalCategory),
		currentReq.Language, currentReq.UserID, currentReq.UserID,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to query candidate requests: %w", err)
	}
	defer rows.Close()

	candidates := make([]*Request, 0)
	for rows.Next() {
		var req Request
		var catStr, paceStr, createdAtStr string
		if err := rows.Scan(
			&req.ID, &req.UserID, &req.GoalID, &catStr, &paceStr, &req.Timezone,
			&req.TimezoneToleranceHours, &req.Language, &createdAtStr,
		); err != nil {
			return nil, fmt.Errorf("failed to scan candidate: %w", err)
		}

		req.GoalCategory = goals.GoalCategory(catStr)
		req.Pace = goals.GoalPace(paceStr)
		if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
			req.CreatedAt = parsed
		}
		candidates = append(candidates, &req)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("candidate iteration error: %w", err)
	}

	return candidates, nil
}

// PairRequests executes the pairing step inside a single SQLite write transaction.
// It verifies both requests are still open, inserts the pod, two pod_members, and streaks,
// then updates both pod_requests to 'matched' with the new pod_id.
func (r *Repository) PairRequests(ctx context.Context, reqA, reqB *Request) (string, error) {
	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return "", fmt.Errorf("failed to begin pairing transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	// 1. Re-check both requests are still open in the write transaction
	checkQuery := `SELECT status FROM pod_requests WHERE id = ?;`

	var statusA, statusB string
	if err := tx.QueryRowContext(ctx, checkQuery, reqA.ID).Scan(&statusA); err != nil {
		return "", fmt.Errorf("failed to re-check status for request A: %w", err)
	}
	if statusA != string(PodRequestStatusOpen) {
		return "", ErrPairingConflict
	}

	if err := tx.QueryRowContext(ctx, checkQuery, reqB.ID).Scan(&statusB); err != nil {
		return "", fmt.Errorf("failed to re-check status for request B: %w", err)
	}
	if statusB != string(PodRequestStatusOpen) {
		return "", ErrPairingConflict
	}

	// 2. Re-check neither user is in an active pod
	activePodQuery := `
		SELECT EXISTS (
			SELECT 1 FROM pod_members pm
			JOIN pods p ON pm.pod_id = p.id
			WHERE pm.user_id IN (?, ?)
			  AND p.status = 'active'
			  AND (pm.left_at IS NULL OR pm.left_at = '')
		);
	`
	var activeExists int
	if err := tx.QueryRowContext(ctx, activePodQuery, reqA.UserID, reqB.UserID).Scan(&activeExists); err != nil {
		return "", fmt.Errorf("failed to check active pod status: %w", err)
	}
	if activeExists == 1 {
		return "", ErrPairingConflict
	}

	now := time.Now().UTC().Format(time.RFC3339)
	podID := uuid.NewString()

	// 3. Create the pods row (status active, capacity 2)
	insertPodQuery := `
		INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at)
		VALUES (?, ?, 'active', 2, ?, ?);
	`
	if _, err := tx.ExecContext(ctx, insertPodQuery, podID, string(reqA.GoalCategory), now, now); err != nil {
		return "", fmt.Errorf("failed to insert pod: %w", err)
	}

	// 4. Create two pod_members rows
	insertMemberQuery := `
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at, left_at)
		VALUES (?, ?, ?, ?, ?, NULL);
	`
	memberAID := uuid.NewString()
	if _, err := tx.ExecContext(ctx, insertMemberQuery, memberAID, podID, reqA.UserID, reqA.GoalID, now); err != nil {
		return "", fmt.Errorf("failed to insert pod member A: %w", err)
	}

	memberBID := uuid.NewString()
	if _, err := tx.ExecContext(ctx, insertMemberQuery, memberBID, podID, reqB.UserID, reqB.GoalID, now); err != nil {
		return "", fmt.Errorf("failed to insert pod member B: %w", err)
	}

	// 5. Create streaks row (zeros)
	streakID := uuid.NewString()
	insertStreakQuery := `
		INSERT INTO streaks (id, pod_id, current_streak, best_streak, last_check_in_date, updated_at)
		VALUES (?, ?, 0, 0, NULL, ?);
	`
	if _, err := tx.ExecContext(ctx, insertStreakQuery, streakID, podID, now); err != nil {
		return "", fmt.Errorf("failed to insert streak: %w", err)
	}

	// 6. Update both pod_requests to matched with pod_id
	updateReqQuery := `
		UPDATE pod_requests
		SET status = 'matched', pod_id = ?, updated_at = ?
		WHERE id = ? AND status = 'open';
	`
	resA, err := tx.ExecContext(ctx, updateReqQuery, podID, now, reqA.ID)
	if err != nil {
		return "", fmt.Errorf("failed to update request A to matched: %w", err)
	}
	rowsA, err := resA.RowsAffected()
	if err != nil || rowsA != 1 {
		return "", ErrPairingConflict
	}

	resB, err := tx.ExecContext(ctx, updateReqQuery, podID, now, reqB.ID)
	if err != nil {
		return "", fmt.Errorf("failed to update request B to matched: %w", err)
	}
	rowsB, err := resB.RowsAffected()
	if err != nil || rowsB != 1 {
		return "", ErrPairingConflict
	}

	// 7. Commit transaction
	if err := tx.Commit(); err != nil {
		return "", fmt.Errorf("failed to commit pairing transaction: %w", err)
	}

	return podID, nil
}

// GetOpenRequestsOlderThan queries open requests created at or before cutoff.
func (r *Repository) GetOpenRequestsOlderThan(ctx context.Context, cutoff time.Time) ([]*Request, error) {
	cutoffStr := cutoff.UTC().Format(time.RFC3339)
	query := `
		SELECT pr.id, pr.user_id, pr.goal_id, g.category, g.pace, u.timezone,
		       pr.timezone_tolerance_hours, pr.language, pr.created_at
		FROM pod_requests pr
		JOIN users u ON pr.user_id = u.id
		JOIN goals g ON pr.goal_id = g.id
		WHERE pr.status = 'open'
		  AND pr.created_at <= ?
		ORDER BY pr.created_at ASC;
	`
	rows, err := r.readDB.QueryContext(ctx, query, cutoffStr)
	if err != nil {
		return nil, fmt.Errorf("failed to query older open requests: %w", err)
	}
	defer rows.Close()

	requests := make([]*Request, 0)
	for rows.Next() {
		var req Request
		var catStr, paceStr, createdAtStr string
		if err := rows.Scan(
			&req.ID, &req.UserID, &req.GoalID, &catStr, &paceStr, &req.Timezone,
			&req.TimezoneToleranceHours, &req.Language, &createdAtStr,
		); err != nil {
			return nil, fmt.Errorf("failed to scan older request: %w", err)
		}

		req.GoalCategory = goals.GoalCategory(catStr)
		req.Pace = goals.GoalPace(paceStr)
		if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
			req.CreatedAt = parsed
		}
		requests = append(requests, &req)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("request iteration error: %w", err)
	}

	return requests, nil
}
