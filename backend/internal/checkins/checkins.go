package checkins

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Sentinel errors for check-ins domain.
var (
	ErrAlreadyCheckedIn = errors.New("user has already checked in for today")
	ErrCheckInNotFound  = errors.New("check-in not found")
	ErrStreakNotFound   = errors.New("streak not found")
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
	LastCheckInDate *string   `json:"last_check_in_date"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// PodStreakDetails represents the streak status and today's check-in progress for a pod.
type PodStreakDetails struct {
	CurrentStreak         int     `json:"current_streak"`
	BestStreak            int     `json:"best_streak"`
	LastCheckInDate       *string `json:"last_check_in_date"`
	MeCheckedInToday      bool    `json:"me_checked_in_today"`
	PartnerCheckedInToday bool    `json:"partner_checked_in_today"`
	BothCheckedInToday    bool    `json:"both_checked_in_today"`
}

// DailyCheckInItem represents check-in participation for a specific UTC date.
type DailyCheckInItem struct {
	Date          string   `json:"date"`
	MemberIDs     []string `json:"member_ids"`
	BothCheckedIn bool     `json:"both_checked_in"`
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
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return ErrAlreadyCheckedIn
		}
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
			return nil, ErrCheckInNotFound
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
	var lastCheckInDate sql.NullString

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&s.ID, &s.PodID, &s.CurrentStreak, &s.BestStreak, &lastCheckInDate, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrStreakNotFound
		}
		return nil, fmt.Errorf("failed to get streak: %w", err)
	}

	if lastCheckInDate.Valid {
		val := lastCheckInDate.String
		s.LastCheckInDate = &val
	}
	if parsed, err := time.Parse(time.RFC3339, updatedAtStr); err == nil {
		s.UpdatedAt = parsed
	}

	return &s, nil
}

// GetStreakByPodID retrieves a streak record for a specific pod.
func (r *Repository) GetStreakByPodID(ctx context.Context, podID string) (*Streak, error) {
	query := `
		SELECT id, pod_id, current_streak, best_streak, last_check_in_date, updated_at
		FROM streaks
		WHERE pod_id = ?;
	`
	var s Streak
	var updatedAtStr string
	var lastCheckInDate sql.NullString

	err := r.readDB.QueryRowContext(ctx, query, podID).Scan(
		&s.ID, &s.PodID, &s.CurrentStreak, &s.BestStreak, &lastCheckInDate, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrStreakNotFound
		}
		return nil, fmt.Errorf("failed to get streak by pod id: %w", err)
	}

	if lastCheckInDate.Valid {
		val := lastCheckInDate.String
		s.LastCheckInDate = &val
	}
	if parsed, err := time.Parse(time.RFC3339, updatedAtStr); err == nil {
		s.UpdatedAt = parsed
	}

	return &s, nil
}

// RecordCheckIn inserts a check_in and recalculates pod streaks within ONE write transaction.
// If the user has already checked in for today's UTC date, ErrAlreadyCheckedIn is returned.
func (r *Repository) RecordCheckIn(ctx context.Context, podID, userID string, note *string, streakService *StreakService) (*CheckIn, *Streak, bool, error) {
	todayUTC := time.Now().UTC()
	todayDate := todayUTC.Format("2006-01-02")
	createdAtStr := todayUTC.Format(time.RFC3339)

	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return nil, nil, false, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// 1. Check if user already checked in for today
	var existingCount int
	err = tx.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM check_ins
		WHERE pod_id = ? AND user_id = ? AND check_in_date = ?;
	`, podID, userID, todayDate).Scan(&existingCount)
	if err != nil {
		return nil, nil, false, fmt.Errorf("failed to verify existing check-in: %w", err)
	}
	if existingCount > 0 {
		return nil, nil, false, ErrAlreadyCheckedIn
	}

	// 2. Insert check-in record
	checkInID := uuid.NewString()
	_, err = tx.ExecContext(ctx, `
		INSERT INTO check_ins (id, pod_id, user_id, check_in_date, note, created_at)
		VALUES (?, ?, ?, ?, ?, ?);
	`, checkInID, podID, userID, todayDate, note, createdAtStr)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return nil, nil, false, ErrAlreadyCheckedIn
		}
		return nil, nil, false, fmt.Errorf("failed to insert check-in: %w", err)
	}

	// 3. Recalculate streak within the SAME transaction
	streak, err := streakService.RecalculateContext(ctx, tx, podID, todayDate)
	if err != nil {
		return nil, nil, false, fmt.Errorf("failed to recalculate streak: %w", err)
	}

	// 4. Determine if both active members have checked in today
	var checkedInCount int
	err = tx.QueryRowContext(ctx, `
		SELECT COUNT(DISTINCT user_id)
		FROM check_ins
		WHERE pod_id = ? AND check_in_date = ? AND user_id IN (
			SELECT user_id FROM pod_members WHERE pod_id = ? AND left_at IS NULL
		);
	`, podID, todayDate, podID).Scan(&checkedInCount)
	if err != nil {
		return nil, nil, false, fmt.Errorf("failed to count active checked-in members: %w", err)
	}

	var activeMembersCount int
	err = tx.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM pod_members
		WHERE pod_id = ? AND left_at IS NULL;
	`, podID).Scan(&activeMembersCount)
	if err != nil {
		return nil, nil, false, fmt.Errorf("failed to count active pod members: %w", err)
	}

	bothCheckedIn := (activeMembersCount >= 2 && checkedInCount == activeMembersCount)

	if err := tx.Commit(); err != nil {
		return nil, nil, false, fmt.Errorf("failed to commit check-in transaction: %w", err)
	}

	checkIn := &CheckIn{
		ID:          checkInID,
		PodID:       podID,
		UserID:      userID,
		CheckInDate: todayDate,
		Note:        note,
		CreatedAt:   todayUTC,
	}

	return checkIn, streak, bothCheckedIn, nil
}

// GetPodStreakDetails retrieves streak metrics and today's check-in states for the requester and partner.
func (r *Repository) GetPodStreakDetails(ctx context.Context, podID, currentUserID string) (*PodStreakDetails, error) {
	todayUTC := time.Now().UTC()
	todayDate := todayUTC.Format("2006-01-02")
	yesterdayDate := todayUTC.AddDate(0, 0, -1).Format("2006-01-02")

	// 1. Fetch streak row
	st, err := r.GetStreakByPodID(ctx, podID)
	if err != nil && !errors.Is(err, ErrStreakNotFound) {
		return nil, fmt.Errorf("failed to get pod streak: %w", err)
	}

	currentStreak := 0
	bestStreak := 0
	var lastCheckInDate *string

	if st != nil {
		bestStreak = st.BestStreak
		lastCheckInDate = st.LastCheckInDate

		// If a full day has passed without both members checking in, display current_streak as 0
		if st.LastCheckInDate != nil {
			if *st.LastCheckInDate == todayDate || *st.LastCheckInDate == yesterdayDate {
				currentStreak = st.CurrentStreak
			}
		}
	}

	// 2. Fetch active members to identify partner
	rows, err := r.readDB.QueryContext(ctx, `
		SELECT user_id
		FROM pod_members
		WHERE pod_id = ? AND left_at IS NULL;
	`, podID)
	if err != nil {
		return nil, fmt.Errorf("failed to query pod members: %w", err)
	}
	defer rows.Close()

	var partnerID string
	for rows.Next() {
		var uid string
		if err := rows.Scan(&uid); err != nil {
			return nil, fmt.Errorf("failed to scan member user id: %w", err)
		}
		if uid != currentUserID {
			partnerID = uid
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("pod members rows error: %w", err)
	}

	// 3. Fetch check-ins for today
	checkInRows, err := r.readDB.QueryContext(ctx, `
		SELECT user_id
		FROM check_ins
		WHERE pod_id = ? AND check_in_date = ?;
	`, podID, todayDate)
	if err != nil {
		return nil, fmt.Errorf("failed to query today's check-ins: %w", err)
	}
	defer checkInRows.Close()

	meCheckedIn := false
	partnerCheckedIn := false

	for checkInRows.Next() {
		var uid string
		if err := checkInRows.Scan(&uid); err != nil {
			return nil, fmt.Errorf("failed to scan check-in user id: %w", err)
		}
		if uid == currentUserID {
			meCheckedIn = true
		}
		if partnerID != "" && uid == partnerID {
			partnerCheckedIn = true
		}
	}
	if err := checkInRows.Err(); err != nil {
		return nil, fmt.Errorf("today's check-ins rows error: %w", err)
	}

	bothCheckedIn := meCheckedIn && partnerCheckedIn

	return &PodStreakDetails{
		CurrentStreak:         currentStreak,
		BestStreak:            bestStreak,
		LastCheckInDate:       lastCheckInDate,
		MeCheckedInToday:      meCheckedIn,
		PartnerCheckedInToday: partnerCheckedIn,
		BothCheckedInToday:    bothCheckedIn,
	}, nil
}

// ListPodCheckInsByDate retrieves distinct check-in dates and member participation, most recent first.
func (r *Repository) ListPodCheckInsByDate(ctx context.Context, podID string, limit int) ([]DailyCheckInItem, error) {
	if limit <= 0 {
		limit = 60
	}

	// Count active members to determine both_checked_in
	var activeMembersCount int
	err := r.readDB.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM pod_members
		WHERE pod_id = ? AND left_at IS NULL;
	`, podID).Scan(&activeMembersCount)
	if err != nil {
		return nil, fmt.Errorf("failed to query active members count: %w", err)
	}

	// Query check-ins ordered by check_in_date DESC
	rows, err := r.readDB.QueryContext(ctx, `
		SELECT check_in_date, user_id
		FROM check_ins
		WHERE pod_id = ?
		ORDER BY check_in_date DESC, created_at ASC;
	`, podID)
	if err != nil {
		return nil, fmt.Errorf("failed to query check-ins: %w", err)
	}
	defer rows.Close()

	type dateGroup struct {
		date       string
		memberMap  map[string]struct{}
		memberList []string
	}

	groups := make([]*dateGroup, 0)
	groupIndex := make(map[string]*dateGroup)

	for rows.Next() {
		var d, uid string
		if err := rows.Scan(&d, &uid); err != nil {
			return nil, fmt.Errorf("failed to scan check-in row: %w", err)
		}

		g, exists := groupIndex[d]
		if !exists {
			if len(groups) >= limit {
				// Reached requested distinct date limit
				continue
			}
			g = &dateGroup{
				date:       d,
				memberMap:  make(map[string]struct{}),
				memberList: make([]string, 0, 2),
			}
			groupIndex[d] = g
			groups = append(groups, g)
		}

		if _, seen := g.memberMap[uid]; !seen {
			g.memberMap[uid] = struct{}{}
			g.memberList = append(g.memberList, uid)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("check-ins rows error: %w", err)
	}

	result := make([]DailyCheckInItem, 0, len(groups))
	for _, g := range groups {
		both := (activeMembersCount >= 2 && len(g.memberList) >= activeMembersCount)
		result = append(result, DailyCheckInItem{
			Date:          g.date,
			MemberIDs:     g.memberList,
			BothCheckedIn: both,
		})
	}

	return result, nil
}

// GetPartnerID returns the user ID of the active partner in the pod (active member where user_id != userID).
func (r *Repository) GetPartnerID(ctx context.Context, podID, userID string) (string, error) {
	query := `
		SELECT user_id
		FROM pod_members
		WHERE pod_id = ? AND user_id != ? AND (left_at IS NULL OR left_at = '')
		LIMIT 1;
	`
	var partnerID string
	err := r.readDB.QueryRowContext(ctx, query, podID, userID).Scan(&partnerID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", errors.New("partner not found in pod")
		}
		return "", fmt.Errorf("failed to query partner id: %w", err)
	}
	return partnerID, nil
}

