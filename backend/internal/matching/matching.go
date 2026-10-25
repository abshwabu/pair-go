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

// Clock provides the current time, enabling deterministic testing.
type Clock interface {
	Now() time.Time
}

// RealClock implements Clock using system UTC time.
type RealClock struct{}

func (RealClock) Now() time.Time {
	return time.Now().UTC()
}

// PodRequestStatus represents the state of a matching request.
type PodRequestStatus string

const (
	PodRequestStatusOpen      PodRequestStatus = "open"
	PodRequestStatusProposed  PodRequestStatus = "proposed"
	PodRequestStatusMatched   PodRequestStatus = "matched"
	PodRequestStatusCancelled PodRequestStatus = "cancelled"
)

// ProposalStatus represents the overall lifecycle of a match proposal.
type ProposalStatus string

const (
	ProposalStatusPending   ProposalStatus = "pending"
	ProposalStatusAccepted  ProposalStatus = "accepted"
	ProposalStatusRejected  ProposalStatus = "rejected"
	ProposalStatusExpired   ProposalStatus = "expired"
	ProposalStatusCancelled ProposalStatus = "cancelled"
)

// ProposalResponse represents an individual user's decision on a match proposal.
type ProposalResponse string

const (
	ProposalResponsePending  ProposalResponse = "pending"
	ProposalResponseAccepted ProposalResponse = "accepted"
	ProposalResponseRejected ProposalResponse = "rejected"
)

// Sentinel errors for matching domain.
var (
	ErrRequestNotFound  = errors.New("pod request not found")
	ErrProposalNotFound = errors.New("match proposal not found")
	ErrProposalClosed   = errors.New("proposal_closed")
	ErrForbidden        = errors.New("forbidden: you do not have permission")
	ErrAlreadyMatched   = errors.New("conflict: request has already been matched")
	ErrPairingConflict  = errors.New("conflict: one or both requests are no longer available for matching")
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
	ProposalID             *string          `json:"proposal_id,omitempty"`
	CreatedAt              time.Time        `json:"created_at"`
	UpdatedAt              time.Time        `json:"updated_at"`
}

// MatchProposal represents a record in the match_proposals table.
type MatchProposal struct {
	ID            string           `json:"id"`
	RequestAID    string           `json:"request_a_id"`
	RequestBID    string           `json:"request_b_id"`
	UserAID       string           `json:"user_a_id"`
	UserBID       string           `json:"user_b_id"`
	UserAResponse ProposalResponse `json:"user_a_response"`
	UserBResponse ProposalResponse `json:"user_b_response"`
	Status        ProposalStatus   `json:"status"`
	PodID         *string          `json:"pod_id,omitempty"`
	ExpiresAt     time.Time        `json:"expires_at"`
	CreatedAt     time.Time        `json:"created_at"`
	UpdatedAt     time.Time        `json:"updated_at"`
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

// Repository handles pod_requests and match_proposals database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
	clock   Clock
}

// NewRepository creates a new matching Repository with an optional clock.
func NewRepository(writeDB, readDB *sql.DB, clocks ...Clock) *Repository {
	var c Clock = RealClock{}
	if len(clocks) > 0 && clocks[0] != nil {
		c = clocks[0]
	}
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
		clock:   c,
	}
}

// SetClock updates the clock implementation.
func (r *Repository) SetClock(c Clock) {
	if c != nil {
		r.clock = c
	}
}

// Clock returns the configured Clock.
func (r *Repository) Clock() Clock {
	if r.clock == nil {
		return RealClock{}
	}
	return r.clock
}

// Create inserts a new pod_request record.
func (r *Repository) Create(ctx context.Context, pr *PodRequest) error {
	query := `
		INSERT INTO pod_requests (
			id, user_id, goal_id, status, timezone_tolerance_hours,
			language, pod_id, proposal_id, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
	`
	createdAtStr := pr.CreatedAt.UTC().Format(time.RFC3339)
	updatedAtStr := pr.UpdatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		pr.ID, pr.UserID, pr.GoalID, string(pr.Status), pr.TimezoneToleranceHours,
		pr.Language, pr.PodID, pr.ProposalID, createdAtStr, updatedAtStr,
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
		       language, pod_id, proposal_id, created_at, updated_at
		FROM pod_requests
		WHERE id = ?;
	`
	var pr PodRequest
	var statusStr, createdAtStr, updatedAtStr string
	var podID, proposalID sql.NullString

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&pr.ID, &pr.UserID, &pr.GoalID, &statusStr, &pr.TimezoneToleranceHours,
		&pr.Language, &podID, &proposalID, &createdAtStr, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrRequestNotFound
		}
		return nil, fmt.Errorf("failed to get pod request: %w", err)
	}

	pr.Status = PodRequestStatus(statusStr)
	if podID.Valid {
		val := podID.String
		pr.PodID = &val
	}
	if proposalID.Valid {
		val := proposalID.String
		pr.ProposalID = &val
	}
	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		pr.CreatedAt = parsed
	}
	if parsed, err := time.Parse(time.RFC3339, updatedAtStr); err == nil {
		pr.UpdatedAt = parsed
	}

	return &pr, nil
}

// GetLatestRequestForUser retrieves the user's most recent pod request.
func (r *Repository) GetLatestRequestForUser(ctx context.Context, userID string) (*PodRequest, error) {
	query := `
		SELECT id, user_id, goal_id, status, timezone_tolerance_hours,
		       language, pod_id, proposal_id, created_at, updated_at
		FROM pod_requests
		WHERE user_id = ?
		ORDER BY created_at DESC
		LIMIT 1;
	`
	var pr PodRequest
	var statusStr, createdAtStr, updatedAtStr string
	var podID, proposalID sql.NullString

	err := r.readDB.QueryRowContext(ctx, query, userID).Scan(
		&pr.ID, &pr.UserID, &pr.GoalID, &statusStr, &pr.TimezoneToleranceHours,
		&pr.Language, &podID, &proposalID, &createdAtStr, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrRequestNotFound
		}
		return nil, fmt.Errorf("failed to get latest request for user: %w", err)
	}

	pr.Status = PodRequestStatus(statusStr)
	if podID.Valid {
		val := podID.String
		pr.PodID = &val
	}
	if proposalID.Valid {
		val := proposalID.String
		pr.ProposalID = &val
	}
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

// HasActiveRequest returns true if the user already has a pod request in 'open' or 'proposed' status.
func (r *Repository) HasActiveRequest(ctx context.Context, userID string) (bool, error) {
	query := `
		SELECT EXISTS (
			SELECT 1 FROM pod_requests
			WHERE user_id = ? AND status IN ('open', 'proposed')
		);
	`
	var exists int
	err := r.readDB.QueryRowContext(ctx, query, userID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check active request: %w", err)
	}
	return exists == 1, nil
}

// HasOpenRequest returns true if the user already has a pod request in 'open' status.
func (r *Repository) HasOpenRequest(ctx context.Context, userID string) (bool, error) {
	return r.HasActiveRequest(ctx, userID)
}

// GetActivePodForUser returns the active pod ID and true if the user is an active member of an active pod.
func (r *Repository) GetActivePodForUser(ctx context.Context, userID string) (string, bool, error) {
	query := `
		SELECT p.id
		FROM pod_members pm
		JOIN pods p ON pm.pod_id = p.id
		WHERE pm.user_id = ?
		  AND p.status = 'active'
		  AND (pm.left_at IS NULL OR pm.left_at = '')
		LIMIT 1;
	`
	var podID string
	err := r.readDB.QueryRowContext(ctx, query, userID).Scan(&podID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", false, nil
		}
		return "", false, fmt.Errorf("failed to query active pod: %w", err)
	}
	return podID, true, nil
}

// IsUserInActivePod returns true if the user is currently an active member of an active pod.
func (r *Repository) IsUserInActivePod(ctx context.Context, userID string) (bool, error) {
	_, active, err := r.GetActivePodForUser(ctx, userID)
	return active, err
}

// FindCandidateRequests finds all candidate open requests matching category and language,
// excluding pairs that block each other, and excluding pairs that already have a proposal with status 'rejected' between them.
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
		  AND NOT EXISTS (
		      SELECT 1 FROM match_proposals mp
		      WHERE mp.status = 'rejected'
		        AND ((mp.user_a_id = ? AND mp.user_b_id = pr.user_id)
		          OR (mp.user_b_id = ? AND mp.user_a_id = pr.user_id))
		  )
		ORDER BY pr.created_at ASC;
	`
	rows, err := r.readDB.QueryContext(ctx, query,
		currentReq.ID, currentReq.UserID, string(currentReq.GoalCategory),
		currentReq.Language, currentReq.UserID, currentReq.UserID,
		currentReq.UserID, currentReq.UserID,
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

// Propose executes the proposal creation in ONE write transaction.
// It re-reads both requests, aborts if either is no longer open, inserts a match_proposals row
// with expires_at = now + ttl, sets both requests to proposed with proposal_id, and creates NO pod.
func (r *Repository) Propose(ctx context.Context, reqA, reqB *Request, ttl time.Duration) (string, error) {
	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return "", fmt.Errorf("failed to begin propose transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	// 1. Re-check both requests are still open
	checkQuery := `SELECT status FROM pod_requests WHERE id = ?;`
	var statusA, statusB string
	if err := tx.QueryRowContext(ctx, checkQuery, reqA.ID).Scan(&statusA); err != nil {
		return "", fmt.Errorf("failed to re-check request A: %w", err)
	}
	if statusA != string(PodRequestStatusOpen) {
		return "", ErrPairingConflict
	}

	if err := tx.QueryRowContext(ctx, checkQuery, reqB.ID).Scan(&statusB); err != nil {
		return "", fmt.Errorf("failed to re-check request B: %w", err)
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
		return "", fmt.Errorf("failed to check active pod: %w", err)
	}
	if activeExists == 1 {
		return "", ErrPairingConflict
	}

	now := r.Clock().Now().UTC()
	expiresAt := now.Add(ttl)
	nowStr := now.Format(time.RFC3339)
	expiresAtStr := expiresAt.Format(time.RFC3339)
	proposalID := uuid.NewString()

	// 3. Insert match_proposals row
	insertPropQuery := `
		INSERT INTO match_proposals (
			id, request_a_id, request_b_id, user_a_id, user_b_id,
			user_a_response, user_b_response, status, pod_id, expires_at,
			created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, 'pending', 'pending', 'pending', NULL, ?, ?, ?);
	`
	if _, err := tx.ExecContext(ctx, insertPropQuery,
		proposalID, reqA.ID, reqB.ID, reqA.UserID, reqB.UserID,
		expiresAtStr, nowStr, nowStr,
	); err != nil {
		return "", fmt.Errorf("failed to insert match proposal: %w", err)
	}

	// 4. Update both pod_requests to proposed with proposal_id
	updateReqQuery := `
		UPDATE pod_requests
		SET status = 'proposed', proposal_id = ?, updated_at = ?
		WHERE id = ? AND status = 'open';
	`
	resA, err := tx.ExecContext(ctx, updateReqQuery, proposalID, nowStr, reqA.ID)
	if err != nil {
		return "", fmt.Errorf("failed to update request A: %w", err)
	}
	rowsA, err := resA.RowsAffected()
	if err != nil || rowsA != 1 {
		return "", ErrPairingConflict
	}

	resB, err := tx.ExecContext(ctx, updateReqQuery, proposalID, nowStr, reqB.ID)
	if err != nil {
		return "", fmt.Errorf("failed to update request B: %w", err)
	}
	rowsB, err := resB.RowsAffected()
	if err != nil || rowsB != 1 {
		return "", ErrPairingConflict
	}

	if err := tx.Commit(); err != nil {
		return "", fmt.Errorf("failed to commit propose transaction: %w", err)
	}

	return proposalID, nil
}

// GetProposalByID retrieves a match proposal record by its ID.
func (r *Repository) GetProposalByID(ctx context.Context, id string) (*MatchProposal, error) {
	query := `
		SELECT id, request_a_id, request_b_id, user_a_id, user_b_id,
		       user_a_response, user_b_response, status, pod_id,
		       expires_at, created_at, updated_at
		FROM match_proposals
		WHERE id = ?;
	`
	var p MatchProposal
	var aResp, bResp, statusStr, expiresStr, createdStr, updatedStr string
	var podID sql.NullString

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&p.ID, &p.RequestAID, &p.RequestBID, &p.UserAID, &p.UserBID,
		&aResp, &bResp, &statusStr, &podID,
		&expiresStr, &createdStr, &updatedStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrProposalNotFound
		}
		return nil, fmt.Errorf("failed to get proposal: %w", err)
	}

	p.UserAResponse = ProposalResponse(aResp)
	p.UserBResponse = ProposalResponse(bResp)
	p.Status = ProposalStatus(statusStr)
	if podID.Valid {
		val := podID.String
		p.PodID = &val
	}
	if parsed, err := time.Parse(time.RFC3339, expiresStr); err == nil {
		p.ExpiresAt = parsed
	}
	if parsed, err := time.Parse(time.RFC3339, createdStr); err == nil {
		p.CreatedAt = parsed
	}
	if parsed, err := time.Parse(time.RFC3339, updatedStr); err == nil {
		p.UpdatedAt = parsed
	}

	return &p, nil
}

// AcceptProposalResult contains outcome data after accepting a proposal.
type AcceptProposalResult struct {
	Proposal     *MatchProposal
	BothAccepted bool
	PodID        string
	PartnerID    string
	CallerReqID  string
}

// AcceptProposal handles a user accepting a proposal in ONE write transaction.
func (r *Repository) AcceptProposal(ctx context.Context, proposalID, userID string) (*AcceptProposalResult, error) {
	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to begin accept transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	// 1. Re-read proposal inside write transaction
	query := `
		SELECT id, request_a_id, request_b_id, user_a_id, user_b_id,
		       user_a_response, user_b_response, status, pod_id,
		       expires_at, created_at, updated_at
		FROM match_proposals
		WHERE id = ?;
	`
	var p MatchProposal
	var aResp, bResp, statusStr, expiresStr, createdStr, updatedStr string
	var podID sql.NullString

	err = tx.QueryRowContext(ctx, query, proposalID).Scan(
		&p.ID, &p.RequestAID, &p.RequestBID, &p.UserAID, &p.UserBID,
		&aResp, &bResp, &statusStr, &podID,
		&expiresStr, &createdStr, &updatedStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrProposalNotFound
		}
		return nil, fmt.Errorf("failed to read proposal: %w", err)
	}

	p.UserAResponse = ProposalResponse(aResp)
	p.UserBResponse = ProposalResponse(bResp)
	p.Status = ProposalStatus(statusStr)
	if podID.Valid {
		val := podID.String
		p.PodID = &val
	}
	if parsed, err := time.Parse(time.RFC3339, expiresStr); err == nil {
		p.ExpiresAt = parsed
	}
	if parsed, err := time.Parse(time.RFC3339, createdStr); err == nil {
		p.CreatedAt = parsed
	}
	if parsed, err := time.Parse(time.RFC3339, updatedStr); err == nil {
		p.UpdatedAt = parsed
	}

	// 2. Verify caller is participant
	if userID != p.UserAID && userID != p.UserBID {
		return nil, ErrForbidden
	}

	isUserA := (userID == p.UserAID)
	var partnerID, callerReqID string
	if isUserA {
		partnerID = p.UserBID
		callerReqID = p.RequestAID
	} else {
		partnerID = p.UserAID
		callerReqID = p.RequestBID
	}

	// 3. Check status
	if p.Status != ProposalStatusPending {
		return nil, ErrProposalClosed
	}

	now := r.Clock().Now().UTC()
	nowStr := now.Format(time.RFC3339)

	newAResp := p.UserAResponse
	newBResp := p.UserBResponse
	if isUserA {
		newAResp = ProposalResponseAccepted
	} else {
		newBResp = ProposalResponseAccepted
	}

	bothAccepted := (newAResp == ProposalResponseAccepted && newBResp == ProposalResponseAccepted)

	if bothAccepted {
		// Fetch goals and goal category
		var goalAID, goalBID, catStr string
		err = tx.QueryRowContext(ctx, `
			SELECT pr.goal_id, g.category
			FROM pod_requests pr
			JOIN goals g ON pr.goal_id = g.id
			WHERE pr.id = ?;
		`, p.RequestAID).Scan(&goalAID, &catStr)
		if err != nil {
			return nil, fmt.Errorf("failed to fetch request A goal: %w", err)
		}

		err = tx.QueryRowContext(ctx, `
			SELECT goal_id FROM pod_requests WHERE id = ?;
		`, p.RequestBID).Scan(&goalBID)
		if err != nil {
			return nil, fmt.Errorf("failed to fetch request B goal: %w", err)
		}

		// Create pod
		newPodID := uuid.NewString()
		insertPodQuery := `
			INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at)
			VALUES (?, ?, 'active', 2, ?, ?);
		`
		if _, err := tx.ExecContext(ctx, insertPodQuery, newPodID, catStr, nowStr, nowStr); err != nil {
			return nil, fmt.Errorf("failed to insert pod: %w", err)
		}

		// Create two members
		insertMemberQuery := `
			INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at, left_at)
			VALUES (?, ?, ?, ?, ?, NULL);
		`
		if _, err := tx.ExecContext(ctx, insertMemberQuery, uuid.NewString(), newPodID, p.UserAID, goalAID, nowStr); err != nil {
			return nil, fmt.Errorf("failed to insert member A: %w", err)
		}
		if _, err := tx.ExecContext(ctx, insertMemberQuery, uuid.NewString(), newPodID, p.UserBID, goalBID, nowStr); err != nil {
			return nil, fmt.Errorf("failed to insert member B: %w", err)
		}

		// Create streaks
		insertStreakQuery := `
			INSERT INTO streaks (id, pod_id, current_streak, best_streak, last_check_in_date, updated_at)
			VALUES (?, ?, 0, 0, NULL, ?);
		`
		if _, err := tx.ExecContext(ctx, insertStreakQuery, uuid.NewString(), newPodID, nowStr); err != nil {
			return nil, fmt.Errorf("failed to insert streak: %w", err)
		}

		// Update proposal
		updatePropQuery := `
			UPDATE match_proposals
			SET user_a_response = 'accepted', user_b_response = 'accepted',
			    status = 'accepted', pod_id = ?, updated_at = ?
			WHERE id = ?;
		`
		if _, err := tx.ExecContext(ctx, updatePropQuery, newPodID, nowStr, p.ID); err != nil {
			return nil, fmt.Errorf("failed to update proposal to accepted: %w", err)
		}

		// Update both requests to matched with pod_id
		updateReqsQuery := `
			UPDATE pod_requests
			SET status = 'matched', pod_id = ?, updated_at = ?
			WHERE id IN (?, ?);
		`
		if _, err := tx.ExecContext(ctx, updateReqsQuery, newPodID, nowStr, p.RequestAID, p.RequestBID); err != nil {
			return nil, fmt.Errorf("failed to update requests to matched: %w", err)
		}

		if err := tx.Commit(); err != nil {
			return nil, fmt.Errorf("failed to commit accept transaction: %w", err)
		}

		p.UserAResponse = ProposalResponseAccepted
		p.UserBResponse = ProposalResponseAccepted
		p.Status = ProposalStatusAccepted
		p.PodID = &newPodID
		p.UpdatedAt = now

		return &AcceptProposalResult{
			Proposal:     &p,
			BothAccepted: true,
			PodID:        newPodID,
			PartnerID:    partnerID,
			CallerReqID:  callerReqID,
		}, nil
	}

	// Only caller accepted
	updatePropQuery := `
		UPDATE match_proposals
		SET user_a_response = ?, user_b_response = ?, updated_at = ?
		WHERE id = ?;
	`
	if _, err := tx.ExecContext(ctx, updatePropQuery, string(newAResp), string(newBResp), nowStr, p.ID); err != nil {
		return nil, fmt.Errorf("failed to update proposal response: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("failed to commit partial accept: %w", err)
	}

	p.UserAResponse = newAResp
	p.UserBResponse = newBResp
	p.UpdatedAt = now

	return &AcceptProposalResult{
		Proposal:     &p,
		BothAccepted: false,
		PodID:        "",
		PartnerID:    partnerID,
		CallerReqID:  callerReqID,
	}, nil
}

// RejectProposalResult contains outcome data after rejecting a proposal.
type RejectProposalResult struct {
	Proposal    *MatchProposal
	PartnerID   string
	ReqAID      string
	ReqBID      string
	CallerReqID string
}

// RejectProposal handles a user rejecting a proposal in ONE write transaction.
func (r *Repository) RejectProposal(ctx context.Context, proposalID, userID string) (*RejectProposalResult, error) {
	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to begin reject transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	query := `
		SELECT id, request_a_id, request_b_id, user_a_id, user_b_id,
		       user_a_response, user_b_response, status, pod_id,
		       expires_at, created_at, updated_at
		FROM match_proposals
		WHERE id = ?;
	`
	var p MatchProposal
	var aResp, bResp, statusStr, expiresStr, createdStr, updatedStr string
	var podID sql.NullString

	err = tx.QueryRowContext(ctx, query, proposalID).Scan(
		&p.ID, &p.RequestAID, &p.RequestBID, &p.UserAID, &p.UserBID,
		&aResp, &bResp, &statusStr, &podID,
		&expiresStr, &createdStr, &updatedStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrProposalNotFound
		}
		return nil, fmt.Errorf("failed to read proposal: %w", err)
	}

	p.UserAResponse = ProposalResponse(aResp)
	p.UserBResponse = ProposalResponse(bResp)
	p.Status = ProposalStatus(statusStr)

	// Verify participant
	if userID != p.UserAID && userID != p.UserBID {
		return nil, ErrForbidden
	}

	if p.Status != ProposalStatusPending {
		return nil, ErrProposalClosed
	}

	isUserA := (userID == p.UserAID)
	var partnerID, callerReqID string
	if isUserA {
		partnerID = p.UserBID
		callerReqID = p.RequestAID
		p.UserAResponse = ProposalResponseRejected
	} else {
		partnerID = p.UserAID
		callerReqID = p.RequestBID
		p.UserBResponse = ProposalResponseRejected
	}
	p.Status = ProposalStatusRejected

	now := r.Clock().Now().UTC()
	nowStr := now.Format(time.RFC3339)

	// Update proposal to rejected
	updatePropQuery := `
		UPDATE match_proposals
		SET user_a_response = ?, user_b_response = ?, status = 'rejected', updated_at = ?
		WHERE id = ?;
	`
	if _, err := tx.ExecContext(ctx, updatePropQuery,
		string(p.UserAResponse), string(p.UserBResponse), nowStr, p.ID,
	); err != nil {
		return nil, fmt.Errorf("failed to update proposal to rejected: %w", err)
	}

	// Both requests return to open with proposal_id cleared
	reopenQuery := `
		UPDATE pod_requests
		SET status = 'open', proposal_id = NULL, updated_at = ?
		WHERE id IN (?, ?);
	`
	if _, err := tx.ExecContext(ctx, reopenQuery, nowStr, p.RequestAID, p.RequestBID); err != nil {
		return nil, fmt.Errorf("failed to reopen requests: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("failed to commit reject transaction: %w", err)
	}

	return &RejectProposalResult{
		Proposal:    &p,
		PartnerID:   partnerID,
		ReqAID:      p.RequestAID,
		ReqBID:      p.RequestBID,
		CallerReqID: callerReqID,
	}, nil
}

// CancelRequestResult contains outcome info for canceling a request.
type CancelRequestResult struct {
	WasProposed  bool
	ProposalID   string
	PartnerID    string
	PartnerReqID string
}

// Cancel updates a request to cancelled. If proposed, cancels proposal and returns partner to open.
func (r *Repository) Cancel(ctx context.Context, id, userID string) error {
	_, err := r.CancelRequest(ctx, id, userID)
	return err
}

// CancelRequest cancels a pod request. If proposed, marks proposal cancelled and returns partner's request to open.
func (r *Repository) CancelRequest(ctx context.Context, id, userID string) (*CancelRequestResult, error) {
	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to begin cancel transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	pr, err := r.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	if pr.UserID != userID {
		return nil, ErrForbidden
	}

	if pr.Status == PodRequestStatusMatched {
		return nil, ErrAlreadyMatched
	}

	if pr.Status == PodRequestStatusCancelled {
		return &CancelRequestResult{WasProposed: false}, nil
	}

	now := r.Clock().Now().UTC()
	nowStr := now.Format(time.RFC3339)

	if pr.Status == PodRequestStatusOpen {
		updateQuery := `
			UPDATE pod_requests
			SET status = 'cancelled', updated_at = ?
			WHERE id = ? AND status = 'open';
		`
		res, err := tx.ExecContext(ctx, updateQuery, nowStr, id)
		if err != nil {
			return nil, fmt.Errorf("failed to cancel open request: %w", err)
		}
		rows, err := res.RowsAffected()
		if err != nil || rows == 0 {
			return nil, ErrAlreadyMatched
		}
		if err := tx.Commit(); err != nil {
			return nil, fmt.Errorf("failed to commit cancel: %w", err)
		}
		return &CancelRequestResult{WasProposed: false}, nil
	}

	// Status is 'proposed'
	var result CancelRequestResult
	if pr.ProposalID != nil && *pr.ProposalID != "" {
		// Read proposal
		var propID, reqAID, reqBID, uAID, uBID, propStatus string
		err = tx.QueryRowContext(ctx, `
			SELECT id, request_a_id, request_b_id, user_a_id, user_b_id, status
			FROM match_proposals
			WHERE id = ?;
		`, *pr.ProposalID).Scan(&propID, &reqAID, &reqBID, &uAID, &uBID, &propStatus)
		if err == nil && propStatus == string(ProposalStatusPending) {
			// Mark proposal cancelled
			_, _ = tx.ExecContext(ctx, `
				UPDATE match_proposals SET status = 'cancelled', updated_at = ? WHERE id = ?;
			`, nowStr, propID)

			var partnerID, partnerReqID string
			if userID == uAID {
				partnerID = uBID
				partnerReqID = reqBID
			} else {
				partnerID = uAID
				partnerReqID = reqAID
			}

			// Return partner's request to open
			_, _ = tx.ExecContext(ctx, `
				UPDATE pod_requests SET status = 'open', proposal_id = NULL, updated_at = ? WHERE id = ?;
			`, nowStr, partnerReqID)

			result.WasProposed = true
			result.ProposalID = propID
			result.PartnerID = partnerID
			result.PartnerReqID = partnerReqID
		}
	}

	// Cancel caller's request
	_, err = tx.ExecContext(ctx, `
		UPDATE pod_requests SET status = 'cancelled', proposal_id = NULL, updated_at = ? WHERE id = ?;
	`, nowStr, id)
	if err != nil {
		return nil, fmt.Errorf("failed to cancel request: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("failed to commit request cancellation: %w", err)
	}

	return &result, nil
}

// ExpiredProposalAction captures actions to execute after expiring a proposal.
type ExpiredProposalAction struct {
	ProposalID   string
	ReopenedReqs []string
	NotifUsers   []string
}

// ExpirePendingProposals finds pending proposals with expires_at in the past and marks them expired.
func (r *Repository) ExpirePendingProposals(ctx context.Context) ([]ExpiredProposalAction, error) {
	now := r.Clock().Now().UTC()
	nowStr := now.Format(time.RFC3339)

	query := `
		SELECT id, request_a_id, request_b_id, user_a_id, user_b_id,
		       user_a_response, user_b_response
		FROM match_proposals
		WHERE status = 'pending' AND expires_at <= ?;
	`
	rows, err := r.readDB.QueryContext(ctx, query, nowStr)
	if err != nil {
		return nil, fmt.Errorf("failed to query expired proposals: %w", err)
	}
	defer rows.Close()

	type propItem struct {
		id, reqA, reqB, uA, uB, aResp, bResp string
	}
	var expiredList []propItem

	for rows.Next() {
		var it propItem
		if err := rows.Scan(&it.id, &it.reqA, &it.reqB, &it.uA, &it.uB, &it.aResp, &it.bResp); err != nil {
			return nil, fmt.Errorf("failed to scan expired proposal: %w", err)
		}
		expiredList = append(expiredList, it)
	}
	rows.Close()

	var actions []ExpiredProposalAction

	for _, it := range expiredList {
		tx, err := r.writeDB.BeginTx(ctx, nil)
		if err != nil {
			continue
		}

		// Re-check status is still pending in write tx
		var currentStatus string
		err = tx.QueryRowContext(ctx, `SELECT status FROM match_proposals WHERE id = ?;`, it.id).Scan(&currentStatus)
		if err != nil || currentStatus != string(ProposalStatusPending) {
			_ = tx.Rollback()
			continue
		}

		// Mark proposal expired
		_, err = tx.ExecContext(ctx, `
			UPDATE match_proposals SET status = 'expired', updated_at = ? WHERE id = ?;
		`, nowStr, it.id)
		if err != nil {
			_ = tx.Rollback()
			continue
		}

		action := ExpiredProposalAction{ProposalID: it.id}

		// Handle user A
		if it.aResp == string(ProposalResponseAccepted) {
			_, err = tx.ExecContext(ctx, `
				UPDATE pod_requests SET status = 'open', proposal_id = NULL, updated_at = ? WHERE id = ?;
			`, nowStr, it.reqA)
			if err == nil {
				action.ReopenedReqs = append(action.ReopenedReqs, it.reqA)
				action.NotifUsers = append(action.NotifUsers, it.uA)
			}
		} else {
			// Never answered -> cancel request
			_, _ = tx.ExecContext(ctx, `
				UPDATE pod_requests SET status = 'cancelled', proposal_id = NULL, updated_at = ? WHERE id = ?;
			`, nowStr, it.reqA)
		}

		// Handle user B
		if it.bResp == string(ProposalResponseAccepted) {
			_, err = tx.ExecContext(ctx, `
				UPDATE pod_requests SET status = 'open', proposal_id = NULL, updated_at = ? WHERE id = ?;
			`, nowStr, it.reqB)
			if err == nil {
				action.ReopenedReqs = append(action.ReopenedReqs, it.reqB)
				action.NotifUsers = append(action.NotifUsers, it.uB)
			}
		} else {
			// Never answered -> cancel request
			_, _ = tx.ExecContext(ctx, `
				UPDATE pod_requests SET status = 'cancelled', proposal_id = NULL, updated_at = ? WHERE id = ?;
			`, nowStr, it.reqB)
		}

		if err := tx.Commit(); err != nil {
			continue
		}

		actions = append(actions, action)
	}

	return actions, nil
}

// CancelPendingProposalsBetweenUsers cancels any pending proposals between two users and reopens both requests.
func (r *Repository) CancelPendingProposalsBetweenUsers(ctx context.Context, tx *sql.Tx, user1ID, user2ID string) ([]string, error) {
	nowStr := r.Clock().Now().UTC().Format(time.RFC3339)

	query := `
		SELECT id, request_a_id, request_b_id
		FROM match_proposals
		WHERE status = 'pending'
		  AND ((user_a_id = ? AND user_b_id = ?) OR (user_a_id = ? AND user_b_id = ?));
	`
	rows, err := tx.QueryContext(ctx, query, user1ID, user2ID, user2ID, user1ID)
	if err != nil {
		return nil, fmt.Errorf("failed to query pending proposals: %w", err)
	}
	defer rows.Close()

	type propItem struct {
		id, reqA, reqB string
	}
	var props []propItem
	for rows.Next() {
		var it propItem
		if err := rows.Scan(&it.id, &it.reqA, &it.reqB); err != nil {
			return nil, fmt.Errorf("failed to scan pending proposal: %w", err)
		}
		props = append(props, it)
	}
	rows.Close()

	var reopenedReqs []string
	for _, p := range props {
		_, err := tx.ExecContext(ctx, `
			UPDATE match_proposals SET status = 'cancelled', updated_at = ? WHERE id = ?;
		`, nowStr, p.id)
		if err != nil {
			return nil, fmt.Errorf("failed to cancel proposal %s: %w", p.id, err)
		}

		_, err = tx.ExecContext(ctx, `
			UPDATE pod_requests SET status = 'open', proposal_id = NULL, updated_at = ? WHERE id IN (?, ?);
		`, nowStr, p.reqA, p.reqB)
		if err != nil {
			return nil, fmt.Errorf("failed to reopen requests %s, %s: %w", p.reqA, p.reqB, err)
		}

		reopenedReqs = append(reopenedReqs, p.reqA, p.reqB)
	}

	return reopenedReqs, nil
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
