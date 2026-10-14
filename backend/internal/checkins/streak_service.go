package checkins

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// StreakService handles streak calculation logic for pods.
type StreakService struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewStreakService creates a new StreakService.
func NewStreakService(writeDB, readDB *sql.DB) *StreakService {
	return &StreakService{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// Recalculate recalculates the pod streak for a given UTC date ("YYYY-MM-DD") within an existing transaction.
// If both active members have checked in for that date:
// - If last_check_in_date is yesterday (or null), increments current_streak.
// - If last_check_in_date is older than yesterday, restarts current_streak at 1.
// - Updates best_streak when exceeded.
// - Sets last_check_in_date to date.
// It is idempotent for the same date (does not increment more than once on the same date).
func (s *StreakService) Recalculate(tx *sql.Tx, podID, date string) (*Streak, error) {
	return s.RecalculateContext(context.Background(), tx, podID, date)
}

// RecalculateContext recalculates the pod streak with a context within an existing transaction.
func (s *StreakService) RecalculateContext(ctx context.Context, tx *sql.Tx, podID, date string) (*Streak, error) {
	if tx == nil {
		return nil, errors.New("transaction is required for streak recalculation")
	}

	currDate, err := time.Parse("2006-01-02", date)
	if err != nil {
		return nil, fmt.Errorf("invalid date format %q: %w", date, err)
	}
	yesterday := currDate.AddDate(0, 0, -1).Format("2006-01-02")
	nowStr := time.Now().UTC().Format(time.RFC3339)

	// 1. Fetch active members of the pod
	rows, err := tx.QueryContext(ctx, `
		SELECT user_id
		FROM pod_members
		WHERE pod_id = ? AND left_at IS NULL
	`, podID)
	if err != nil {
		return nil, fmt.Errorf("failed to query active pod members: %w", err)
	}
	defer rows.Close()

	activeMemberIDs := make([]string, 0, 2)
	for rows.Next() {
		var uid string
		if err := rows.Scan(&uid); err != nil {
			return nil, fmt.Errorf("failed to scan active member id: %w", err)
		}
		activeMemberIDs = append(activeMemberIDs, uid)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("active members rows error: %w", err)
	}

	// 2. Fetch or initialize the streak record in tx
	streakQuery := `
		SELECT id, pod_id, current_streak, best_streak, last_check_in_date, updated_at
		FROM streaks
		WHERE pod_id = ?;
	`
	var st Streak
	var updatedAtStr string
	var lastCheckInDate sql.NullString

	err = tx.QueryRowContext(ctx, streakQuery, podID).Scan(
		&st.ID, &st.PodID, &st.CurrentStreak, &st.BestStreak, &lastCheckInDate, &updatedAtStr,
	)

	isNew := false
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			isNew = true
			st = Streak{
				ID:            uuid.NewString(),
				PodID:         podID,
				CurrentStreak: 0,
				BestStreak:    0,
				UpdatedAt:     time.Now().UTC(),
			}
		} else {
			return nil, fmt.Errorf("failed to query streak: %w", err)
		}
	} else {
		if lastCheckInDate.Valid {
			val := lastCheckInDate.String
			st.LastCheckInDate = &val
		}
		if parsed, err := time.Parse(time.RFC3339, updatedAtStr); err == nil {
			st.UpdatedAt = parsed
		}
	}

	// 3. Count distinct active members who checked in on this date
	var checkedInCount int
	err = tx.QueryRowContext(ctx, `
		SELECT COUNT(DISTINCT user_id)
		FROM check_ins
		WHERE pod_id = ? AND check_in_date = ? AND user_id IN (
			SELECT user_id FROM pod_members WHERE pod_id = ? AND left_at IS NULL
		);
	`, podID, date, podID).Scan(&checkedInCount)
	if err != nil {
		return nil, fmt.Errorf("failed to count member check-ins for date: %w", err)
	}

	bothActiveCheckedIn := (len(activeMemberIDs) >= 2 && checkedInCount == len(activeMemberIDs))

	if bothActiveCheckedIn {
		// Idempotency: if last_check_in_date is already today's date, do not increment again
		if st.LastCheckInDate != nil && *st.LastCheckInDate == date {
			return &st, nil
		}

		if st.LastCheckInDate == nil || *st.LastCheckInDate == yesterday {
			// If last_check_in_date is yesterday (or null), increment
			st.CurrentStreak++
		} else if *st.LastCheckInDate < yesterday {
			// If last_check_in_date is older than yesterday, start again at 1
			st.CurrentStreak = 1
		} else {
			// last_check_in_date is in the future compared to date; preserve idempotency
			return &st, nil
		}

		// Update best_streak when exceeded
		if st.CurrentStreak > st.BestStreak {
			st.BestStreak = st.CurrentStreak
		}
		st.LastCheckInDate = &date
		st.UpdatedAt = time.Now().UTC()

		upsertQuery := `
			INSERT INTO streaks (id, pod_id, current_streak, best_streak, last_check_in_date, updated_at)
			VALUES (?, ?, ?, ?, ?, ?)
			ON CONFLICT(pod_id) DO UPDATE SET
				current_streak = excluded.current_streak,
				best_streak = excluded.best_streak,
				last_check_in_date = excluded.last_check_in_date,
				updated_at = excluded.updated_at;
		`
		_, err = tx.ExecContext(ctx, upsertQuery,
			st.ID, st.PodID, st.CurrentStreak, st.BestStreak, st.LastCheckInDate, nowStr,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to upsert streak: %w", err)
		}
	} else if isNew {
		// Ensure initial row exists even if only one (or zero) member checked in
		insertInitial := `
			INSERT INTO streaks (id, pod_id, current_streak, best_streak, last_check_in_date, updated_at)
			VALUES (?, ?, 0, 0, NULL, ?)
			ON CONFLICT(pod_id) DO NOTHING;
		`
		_, err = tx.ExecContext(ctx, insertInitial, st.ID, st.PodID, nowStr)
		if err != nil {
			return nil, fmt.Errorf("failed to insert initial streak row: %w", err)
		}
	}

	return &st, nil
}
