package goals

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

// GoalCategory represents allowed goal categories.
type GoalCategory string

const (
	GoalCategoryRead    GoalCategory = "read"
	GoalCategoryWatch   GoalCategory = "watch"
	GoalCategoryFitness GoalCategory = "fitness"
	GoalCategoryHabit   GoalCategory = "habit"
	GoalCategoryCustom  GoalCategory = "custom"
)

// GoalPace represents pacing options.
type GoalPace string

const (
	GoalPaceRelaxed GoalPace = "relaxed"
	GoalPaceSteady  GoalPace = "steady"
	GoalPaceIntense GoalPace = "intense"
)

// Sentinel errors for goals domain.
var (
	ErrGoalNotFound = errors.New("goal not found")
	ErrForbidden    = errors.New("forbidden: you do not own this goal")
	ErrActivePod    = errors.New("conflict: goal is attached to an active pod")
)

// IsValidCategory verifies if the category is one of the allowed enum values.
func IsValidCategory(c GoalCategory) bool {
	switch c {
	case GoalCategoryRead, GoalCategoryWatch, GoalCategoryFitness, GoalCategoryHabit, GoalCategoryCustom:
		return true
	default:
		return false
	}
}

// IsValidPace verifies if the pace is one of the allowed enum values.
func IsValidPace(p GoalPace) bool {
	switch p {
	case GoalPaceRelaxed, GoalPaceSteady, GoalPaceIntense:
		return true
	default:
		return false
	}
}

// AuthorizeOwner verifies that the given goal belongs to the specified userID.
// Returns ErrForbidden if the user is not the owner of the goal.
func AuthorizeOwner(goal *Goal, userID string) error {
	if goal == nil || goal.UserID != userID {
		return ErrForbidden
	}
	return nil
}

// IsOwner returns true if the goal belongs to the specified userID.
func IsOwner(goal *Goal, userID string) bool {
	return goal != nil && goal.UserID == userID
}

// Goal represents a goal record in the goals table.
type Goal struct {
	ID                string       `json:"id"`
	UserID            string       `json:"user_id"`
	Category          GoalCategory `json:"category"`
	Title             string       `json:"title"`
	TargetDescription string       `json:"target_description"`
	Pace              GoalPace     `json:"pace"`
	CreatedAt         time.Time    `json:"created_at"`
	UpdatedAt         time.Time    `json:"updated_at"`
}

// Repository handles goals database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewRepository creates a new goals Repository.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// Create inserts a new goal record.
func (r *Repository) Create(ctx context.Context, g *Goal) error {
	query := `
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?);
	`
	createdAtStr := g.CreatedAt.UTC().Format(time.RFC3339)
	updatedAtStr := g.UpdatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		g.ID, g.UserID, string(g.Category), g.Title, g.TargetDescription, string(g.Pace),
		createdAtStr, updatedAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create goal: %w", err)
	}
	return nil
}

// GetByID retrieves a goal record by its ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Goal, error) {
	query := `
		SELECT id, user_id, category, title, target_description, pace, created_at, updated_at
		FROM goals
		WHERE id = ?;
	`
	var g Goal
	var categoryStr, paceStr, createdAtStr, updatedAtStr string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&g.ID, &g.UserID, &categoryStr, &g.Title, &g.TargetDescription, &paceStr,
		&createdAtStr, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrGoalNotFound
		}
		return nil, fmt.Errorf("failed to get goal: %w", err)
	}

	g.Category = GoalCategory(categoryStr)
	g.Pace = GoalPace(paceStr)
	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		g.CreatedAt = parsed
	}
	if parsed, err := time.Parse(time.RFC3339, updatedAtStr); err == nil {
		g.UpdatedAt = parsed
	}

	return &g, nil
}

// ListByUserID retrieves all goals for a given user, newest first.
func (r *Repository) ListByUserID(ctx context.Context, userID string) ([]*Goal, error) {
	query := `
		SELECT id, user_id, category, title, target_description, pace, created_at, updated_at
		FROM goals
		WHERE user_id = ?
		ORDER BY created_at DESC, rowid DESC;
	`
	rows, err := r.readDB.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to list goals: %w", err)
	}
	defer rows.Close()

	goals := make([]*Goal, 0)
	for rows.Next() {
		var g Goal
		var categoryStr, paceStr, createdAtStr, updatedAtStr string
		if err := rows.Scan(
			&g.ID, &g.UserID, &categoryStr, &g.Title, &g.TargetDescription, &paceStr,
			&createdAtStr, &updatedAtStr,
		); err != nil {
			return nil, fmt.Errorf("failed to scan goal: %w", err)
		}

		g.Category = GoalCategory(categoryStr)
		g.Pace = GoalPace(paceStr)
		if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
			g.CreatedAt = parsed
		}
		if parsed, err := time.Parse(time.RFC3339, updatedAtStr); err == nil {
			g.UpdatedAt = parsed
		}
		goals = append(goals, &g)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("row iteration error: %w", err)
	}

	return goals, nil
}

// UpdateGoalParams defines the optional fields for updating a goal.
type UpdateGoalParams struct {
	Category          *GoalCategory
	Title             *string
	TargetDescription *string
	Pace              *GoalPace
}

// Update modifies an existing goal with non-nil parameters and updates updated_at.
func (r *Repository) Update(ctx context.Context, id string, params UpdateGoalParams) (*Goal, error) {
	var setClauses []string
	var args []any

	if params.Category != nil {
		setClauses = append(setClauses, "category = ?")
		args = append(args, string(*params.Category))
	}
	if params.Title != nil {
		setClauses = append(setClauses, "title = ?")
		args = append(args, *params.Title)
	}
	if params.TargetDescription != nil {
		setClauses = append(setClauses, "target_description = ?")
		args = append(args, *params.TargetDescription)
	}
	if params.Pace != nil {
		setClauses = append(setClauses, "pace = ?")
		args = append(args, string(*params.Pace))
	}

	if len(setClauses) == 0 {
		return r.GetByID(ctx, id)
	}

	now := time.Now().UTC().Format(time.RFC3339)
	setClauses = append(setClauses, "updated_at = ?")
	args = append(args, now)
	args = append(args, id)

	query := fmt.Sprintf("UPDATE goals SET %s WHERE id = ?;", strings.Join(setClauses, ", "))
	res, err := r.writeDB.ExecContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to update goal: %w", err)
	}

	rows, err := res.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rows == 0 {
		return nil, ErrGoalNotFound
	}

	return r.GetByID(ctx, id)
}

// Delete removes a goal record by its ID.
func (r *Repository) Delete(ctx context.Context, id string) error {
	query := `DELETE FROM goals WHERE id = ?;`
	res, err := r.writeDB.ExecContext(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to delete goal: %w", err)
	}

	rows, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rows == 0 {
		return ErrGoalNotFound
	}

	return nil
}

// IsAttachedToActivePod checks if the goal is associated with an active pod via pod_members.
func (r *Repository) IsAttachedToActivePod(ctx context.Context, goalID string) (bool, error) {
	query := `
		SELECT EXISTS (
			SELECT 1
			FROM pod_members pm
			JOIN pods p ON pm.pod_id = p.id
			WHERE pm.goal_id = ?
			  AND p.status = 'active'
			  AND (pm.left_at IS NULL OR pm.left_at = '')
		);
	`
	var exists int
	err := r.readDB.QueryRowContext(ctx, query, goalID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check active pod attachment: %w", err)
	}
	return exists == 1, nil
}
