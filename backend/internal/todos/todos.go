package todos

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Sentinel errors for todos domain.
var (
	ErrTodoNotFound      = errors.New("todo not found")
	ErrForbidden         = errors.New("forbidden")
	ErrInvalidMember     = errors.New("assigned_to must be an active member of the pod")
	ErrInvalidDateFormat = errors.New("due_date must be in YYYY-MM-DD format")
)

// Todo represents a shared task in a pod in the todos table.
type Todo struct {
	ID          string     `json:"id"`
	PodID       string     `json:"pod_id"`
	CreatedBy   string     `json:"created_by"`
	AssignedTo  *string    `json:"assigned_to"`
	Title       string     `json:"title"`
	Notes       *string    `json:"notes"`
	DueDate     *string    `json:"due_date"`
	IsDone      bool       `json:"is_done"`
	CompletedAt *time.Time `json:"completed_at"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// ListFilter defines parameters for filtering and sorting todos.
type ListFilter struct {
	PodID      string
	AssignedTo *string // nil = no filter; pointer to "shared" = IS NULL; pointer to user_id = = ?
	IsDone     *bool   // nil = no filter; true = is_done = 1; false = is_done = 0
	Sort       string  // "due_date" or default
}

// UpdateTodoInput defines partial updates to a todo.
type UpdateTodoInput struct {
	Title         *string
	Notes         *string
	ClearNotes    bool
	DueDate       *string
	ClearDueDate  bool
	AssignedTo    *string
	ClearAssigned bool
	IsDone        *bool
}

// Repository handles todos database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

// NewRepository creates a new todos Repository.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	return &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
}

// IsActivePodMember checks if a user is an active member of a pod (left_at IS NULL).
func (r *Repository) IsActivePodMember(ctx context.Context, podID, userID string) (bool, error) {
	query := `
		SELECT 1 FROM pod_members
		WHERE pod_id = ? AND user_id = ? AND (left_at IS NULL OR left_at = '');
	`
	var exists int
	err := r.readDB.QueryRowContext(ctx, query, podID, userID).Scan(&exists)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, fmt.Errorf("failed to check pod member: %w", err)
	}
	return true, nil
}

// Create inserts a new todo record.
func (r *Repository) Create(ctx context.Context, t *Todo) error {
	// If assigned_to is specified, verify that the assignee is an active member of the pod
	if t.AssignedTo != nil && *t.AssignedTo != "" {
		active, err := r.IsActivePodMember(ctx, t.PodID, *t.AssignedTo)
		if err != nil {
			return err
		}
		if !active {
			return ErrInvalidMember
		}
	}

	query := `
		INSERT INTO todos (
			id, pod_id, created_by, assigned_to, title, notes, due_date,
			is_done, completed_at, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
	`
	isDoneInt := 0
	if t.IsDone {
		isDoneInt = 1
	}

	var completedAtStr *string
	if t.CompletedAt != nil {
		s := t.CompletedAt.UTC().Format(time.RFC3339)
		completedAtStr = &s
	}

	createdAtStr := t.CreatedAt.UTC().Format(time.RFC3339)
	updatedAtStr := t.UpdatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		t.ID, t.PodID, t.CreatedBy, t.AssignedTo, t.Title, t.Notes, t.DueDate,
		isDoneInt, completedAtStr, createdAtStr, updatedAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create todo: %w", err)
	}
	return nil
}

// GetByID retrieves a todo record by its ID and pod ID.
// Guarantees cross-pod isolation: returns ErrTodoNotFound if the todo does not belong to the given pod.
func (r *Repository) GetByID(ctx context.Context, podID, id string) (*Todo, error) {
	query := `
		SELECT id, pod_id, created_by, assigned_to, title, notes, due_date,
		       is_done, completed_at, created_at, updated_at
		FROM todos
		WHERE id = ? AND pod_id = ?;
	`
	var t Todo
	var isDoneInt int
	var completedAtStr, createdAtStr, updatedAtStr *string

	err := r.readDB.QueryRowContext(ctx, query, id, podID).Scan(
		&t.ID, &t.PodID, &t.CreatedBy, &t.AssignedTo, &t.Title, &t.Notes, &t.DueDate,
		&isDoneInt, &completedAtStr, &createdAtStr, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrTodoNotFound
		}
		return nil, fmt.Errorf("failed to get todo: %w", err)
	}

	t.IsDone = isDoneInt == 1
	if completedAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *completedAtStr); err == nil {
			t.CompletedAt = &parsed
		}
	}
	if createdAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *createdAtStr); err == nil {
			t.CreatedAt = parsed
		}
	}
	if updatedAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *updatedAtStr); err == nil {
			t.UpdatedAt = parsed
		}
	}

	return &t, nil
}

// List retrieves todos in a pod based on the given filters and sort order.
func (r *Repository) List(ctx context.Context, filter ListFilter) ([]*Todo, error) {
	baseQuery := `
		SELECT id, pod_id, created_by, assigned_to, title, notes, due_date,
		       is_done, completed_at, created_at, updated_at
		FROM todos
		WHERE pod_id = ?
	`
	args := []any{filter.PodID}

	if filter.AssignedTo != nil {
		if *filter.AssignedTo == "shared" {
			baseQuery += " AND assigned_to IS NULL"
		} else {
			baseQuery += " AND assigned_to = ?"
			args = append(args, *filter.AssignedTo)
		}
	}

	if filter.IsDone != nil {
		if *filter.IsDone {
			baseQuery += " AND is_done = 1"
		} else {
			baseQuery += " AND is_done = 0"
		}
	}

	if filter.Sort == "due_date" {
		baseQuery += " ORDER BY CASE WHEN due_date IS NULL THEN 1 ELSE 0 END ASC, due_date ASC, created_at ASC;"
	} else {
		// Default order: open first, then by due_date, then created_at
		baseQuery += " ORDER BY is_done ASC, CASE WHEN due_date IS NULL THEN 1 ELSE 0 END ASC, due_date ASC, created_at ASC;"
	}

	rows, err := r.readDB.QueryContext(ctx, baseQuery, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to list todos: %w", err)
	}
	defer rows.Close()

	results := make([]*Todo, 0)
	for rows.Next() {
		var t Todo
		var isDoneInt int
		var completedAtStr, createdAtStr, updatedAtStr *string

		if err := rows.Scan(
			&t.ID, &t.PodID, &t.CreatedBy, &t.AssignedTo, &t.Title, &t.Notes, &t.DueDate,
			&isDoneInt, &completedAtStr, &createdAtStr, &updatedAtStr,
		); err != nil {
			return nil, fmt.Errorf("failed to scan todo: %w", err)
		}

		t.IsDone = isDoneInt == 1
		if completedAtStr != nil {
			if parsed, err := time.Parse(time.RFC3339, *completedAtStr); err == nil {
				t.CompletedAt = &parsed
			}
		}
		if createdAtStr != nil {
			if parsed, err := time.Parse(time.RFC3339, *createdAtStr); err == nil {
				t.CreatedAt = parsed
			}
		}
		if updatedAtStr != nil {
			if parsed, err := time.Parse(time.RFC3339, *updatedAtStr); err == nil {
				t.UpdatedAt = parsed
			}
		}

		results = append(results, &t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("row error listing todos: %w", err)
	}

	return results, nil
}

// Update applies partial updates to a todo inside a single write transaction.
// Toggling is_done to true sets completed_at to now, toggling to false clears it to NULL.
func (r *Repository) Update(ctx context.Context, podID, todoID string, input UpdateTodoInput) (*Todo, error) {
	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to begin update tx: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	// 1. Fetch current todo
	query := `
		SELECT id, pod_id, created_by, assigned_to, title, notes, due_date,
		       is_done, completed_at, created_at, updated_at
		FROM todos
		WHERE id = ? AND pod_id = ?;
	`
	var t Todo
	var isDoneInt int
	var completedAtStr, createdAtStr, updatedAtStr *string

	err = tx.QueryRowContext(ctx, query, todoID, podID).Scan(
		&t.ID, &t.PodID, &t.CreatedBy, &t.AssignedTo, &t.Title, &t.Notes, &t.DueDate,
		&isDoneInt, &completedAtStr, &createdAtStr, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrTodoNotFound
		}
		return nil, fmt.Errorf("failed to load todo for update: %w", err)
	}

	t.IsDone = isDoneInt == 1
	if completedAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *completedAtStr); err == nil {
			t.CompletedAt = &parsed
		}
	}
	if createdAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *createdAtStr); err == nil {
			t.CreatedAt = parsed
		}
	}
	if updatedAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *updatedAtStr); err == nil {
			t.UpdatedAt = parsed
		}
	}

	// 2. Apply updates
	if input.Title != nil {
		t.Title = *input.Title
	}
	if input.ClearNotes {
		t.Notes = nil
	} else if input.Notes != nil {
		t.Notes = input.Notes
	}
	if input.ClearDueDate {
		t.DueDate = nil
	} else if input.DueDate != nil {
		t.DueDate = input.DueDate
	}
	if input.ClearAssigned {
		t.AssignedTo = nil
	} else if input.AssignedTo != nil {
		if *input.AssignedTo == "shared" || *input.AssignedTo == "" {
			t.AssignedTo = nil
		} else {
			// Verify that the assigned user is an active member of the pod
			var memberExists int
			mErr := tx.QueryRowContext(ctx, `
				SELECT 1 FROM pod_members
				WHERE pod_id = ? AND user_id = ? AND (left_at IS NULL OR left_at = '');
			`, podID, *input.AssignedTo).Scan(&memberExists)
			if mErr != nil {
				if errors.Is(mErr, sql.ErrNoRows) {
					return nil, ErrInvalidMember
				}
				return nil, fmt.Errorf("failed to verify assignee membership: %w", mErr)
			}
			t.AssignedTo = input.AssignedTo
		}
	}

	now := time.Now().UTC()
	if input.IsDone != nil {
		if *input.IsDone {
			if !t.IsDone {
				t.IsDone = true
				t.CompletedAt = &now
			}
		} else {
			t.IsDone = false
			t.CompletedAt = nil
		}
	}

	t.UpdatedAt = now

	// 3. Save back
	updateQuery := `
		UPDATE todos
		SET title = ?, notes = ?, due_date = ?, assigned_to = ?,
		    is_done = ?, completed_at = ?, updated_at = ?
		WHERE id = ? AND pod_id = ?;
	`
	isDoneInt = 0
	if t.IsDone {
		isDoneInt = 1
	}

	var newCompletedAtStr *string
	if t.CompletedAt != nil {
		s := t.CompletedAt.UTC().Format(time.RFC3339)
		newCompletedAtStr = &s
	}
	updatedAtStrVal := t.UpdatedAt.UTC().Format(time.RFC3339)

	_, err = tx.ExecContext(ctx, updateQuery,
		t.Title, t.Notes, t.DueDate, t.AssignedTo,
		isDoneInt, newCompletedAtStr, updatedAtStrVal,
		todoID, podID,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to execute update: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("failed to commit update: %w", err)
	}

	return &t, nil
}

// Delete removes a todo record if authorized.
// Allowed if the requester is created_by, or the todo is shared (assigned_to NULL); otherwise returns ErrForbidden.
func (r *Repository) Delete(ctx context.Context, podID, todoID, userID string) error {
	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin delete tx: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	query := `
		SELECT created_by, assigned_to
		FROM todos
		WHERE id = ? AND pod_id = ?;
	`
	var createdBy string
	var assignedTo *string

	err = tx.QueryRowContext(ctx, query, todoID, podID).Scan(&createdBy, &assignedTo)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrTodoNotFound
		}
		return fmt.Errorf("failed to query todo for delete: %w", err)
	}

	// Allowed if requester is created_by, or the todo is shared (assigned_to NULL)
	isAllowed := (createdBy == userID) || (assignedTo == nil || *assignedTo == "")
	if !isAllowed {
		return ErrForbidden
	}

	_, err = tx.ExecContext(ctx, `DELETE FROM todos WHERE id = ? AND pod_id = ?;`, todoID, podID)
	if err != nil {
		return fmt.Errorf("failed to delete todo: %w", err)
	}

	return tx.Commit()
}
