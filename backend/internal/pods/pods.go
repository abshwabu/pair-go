package pods

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/abshwabu/pair/backend/internal/auth"
)

// PodStatus represents the lifecycle state of a pod.
type PodStatus string

const (
	PodStatusPending   PodStatus = "pending"
	PodStatusActive    PodStatus = "active"
	PodStatusCompleted PodStatus = "completed"
	PodStatusDissolved PodStatus = "dissolved"
)

// Sentinel errors for pods domain.
var (
	ErrPodNotFound = errors.New("pod not found")
	ErrNotMember   = errors.New("forbidden: user is not an active member of this pod")
	ErrAlreadyLeft = errors.New("user has already left this pod")
)

type contextKey string

const (
	podContextKey       contextKey = "pair_pod_context"
	podMemberContextKey contextKey = "pair_pod_member_context"
)

// Pod represents a paired accountability pod in the pods table.
type Pod struct {
	ID           string    `json:"id"`
	GoalCategory string    `json:"goal_category"`
	Status       PodStatus `json:"status"`
	Capacity     int       `json:"capacity"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// PodMember represents an assigned member of a pod in the pod_members table.
type PodMember struct {
	ID       string     `json:"id"`
	PodID    string     `json:"pod_id"`
	UserID   string     `json:"user_id"`
	GoalID   string     `json:"goal_id"`
	JoinedAt time.Time  `json:"joined_at"`
	LeftAt   *time.Time `json:"left_at,omitempty"`
}

// MemberPublicProfile represents a member's public user information.
type MemberPublicProfile struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	AvatarURL *string `json:"avatar_url"`
}

// MemberGoalInfo represents a member's goal information in the pod.
type MemberGoalInfo struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Category string `json:"category"`
	Pace     string `json:"pace"`
}

// PodMemberDetail represents a member in the pod detail view.
type PodMemberDetail struct {
	User     MemberPublicProfile `json:"user"`
	Goal     MemberGoalInfo      `json:"goal"`
	JoinedAt time.Time           `json:"joined_at"`
	LeftAt   *time.Time          `json:"left_at,omitempty"`
}

// StreakSummary represents streak metrics for a pod.
type StreakSummary struct {
	CurrentStreak   int     `json:"current_streak"`
	BestStreak      int     `json:"best_streak"`
	LastCheckInDate *string `json:"last_check_in_date"`
}

// PodDetail represents the detailed view of a pod with members and streak summary.
type PodDetail struct {
	ID           string            `json:"id"`
	GoalCategory string            `json:"goal_category"`
	Status       PodStatus         `json:"status"`
	Capacity     int               `json:"capacity"`
	CreatedAt    time.Time         `json:"created_at"`
	UpdatedAt    time.Time         `json:"updated_at"`
	Members      []PodMemberDetail `json:"members"`
	Streak       StreakSummary     `json:"streak"`
}

// Context helpers for Pod and PodMember
func WithPod(ctx context.Context, p *Pod) context.Context {
	return context.WithValue(ctx, podContextKey, p)
}

func PodFromContext(ctx context.Context) (*Pod, bool) {
	p, ok := ctx.Value(podContextKey).(*Pod)
	return p, ok && p != nil
}

func WithPodMember(ctx context.Context, m *PodMember) context.Context {
	return context.WithValue(ctx, podMemberContextKey, m)
}

func PodMemberFromContext(ctx context.Context) (*PodMember, bool) {
	m, ok := ctx.Value(podMemberContextKey).(*PodMember)
	return m, ok && m != nil
}

// Repository handles pods and pod_members database operations.
type Repository struct {
	writeDB *sql.DB
	readDB  *sql.DB
}

var defaultRepo *Repository

// NewRepository creates a new pods Repository and sets it as defaultRepo.
func NewRepository(writeDB, readDB *sql.DB) *Repository {
	r := &Repository{
		writeDB: writeDB,
		readDB:  readDB,
	}
	defaultRepo = r
	return r
}

// SetDefaultRepository sets the package-level default pods repository.
func SetDefaultRepository(r *Repository) {
	defaultRepo = r
}

// GetDefaultRepository returns the package-level default pods repository.
func GetDefaultRepository() *Repository {
	return defaultRepo
}

// Create inserts a new pod record.
func (r *Repository) Create(ctx context.Context, p *Pod) error {
	query := `
		INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?);
	`
	createdAtStr := p.CreatedAt.UTC().Format(time.RFC3339)
	updatedAtStr := p.UpdatedAt.UTC().Format(time.RFC3339)

	_, err := r.writeDB.ExecContext(ctx, query,
		p.ID, p.GoalCategory, string(p.Status), p.Capacity, createdAtStr, updatedAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create pod: %w", err)
	}
	return nil
}

// GetByID retrieves a pod record by its ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Pod, error) {
	query := `
		SELECT id, goal_category, status, capacity, created_at, updated_at
		FROM pods
		WHERE id = ?;
	`
	var p Pod
	var statusStr, createdAtStr, updatedAtStr string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&p.ID, &p.GoalCategory, &statusStr, &p.Capacity, &createdAtStr, &updatedAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrPodNotFound
		}
		return nil, fmt.Errorf("failed to get pod: %w", err)
	}

	p.Status = PodStatus(statusStr)
	if parsed, err := time.Parse(time.RFC3339, createdAtStr); err == nil {
		p.CreatedAt = parsed
	}
	if parsed, err := time.Parse(time.RFC3339, updatedAtStr); err == nil {
		p.UpdatedAt = parsed
	}

	return &p, nil
}

// CreateMember inserts a new pod_member record.
func (r *Repository) CreateMember(ctx context.Context, m *PodMember) error {
	query := `
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at, left_at)
		VALUES (?, ?, ?, ?, ?, ?);
	`
	joinedAtStr := m.JoinedAt.UTC().Format(time.RFC3339)
	var leftAtStr *string
	if m.LeftAt != nil {
		s := m.LeftAt.UTC().Format(time.RFC3339)
		leftAtStr = &s
	}

	_, err := r.writeDB.ExecContext(ctx, query,
		m.ID, m.PodID, m.UserID, m.GoalID, joinedAtStr, leftAtStr,
	)
	if err != nil {
		return fmt.Errorf("failed to create pod member: %w", err)
	}
	return nil
}

// GetMemberByID retrieves a pod member record by its ID.
func (r *Repository) GetMemberByID(ctx context.Context, id string) (*PodMember, error) {
	query := `
		SELECT id, pod_id, user_id, goal_id, joined_at, left_at
		FROM pod_members
		WHERE id = ?;
	`
	var m PodMember
	var joinedAtStr string
	var leftAtStr *string

	err := r.readDB.QueryRowContext(ctx, query, id).Scan(
		&m.ID, &m.PodID, &m.UserID, &m.GoalID, &joinedAtStr, &leftAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errors.New("pod member not found")
		}
		return nil, fmt.Errorf("failed to get pod member: %w", err)
	}

	if parsed, err := time.Parse(time.RFC3339, joinedAtStr); err == nil {
		m.JoinedAt = parsed
	}
	if leftAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *leftAtStr); err == nil {
			m.LeftAt = &parsed
		}
	}

	return &m, nil
}

// GetActiveMember retrieves an active pod member (where left_at IS NULL).
func (r *Repository) GetActiveMember(ctx context.Context, podID, userID string) (*PodMember, error) {
	query := `
		SELECT id, pod_id, user_id, goal_id, joined_at, left_at
		FROM pod_members
		WHERE pod_id = ? AND user_id = ? AND (left_at IS NULL OR left_at = '');
	`
	var m PodMember
	var joinedAtStr string
	var leftAtStr *string

	err := r.readDB.QueryRowContext(ctx, query, podID, userID).Scan(
		&m.ID, &m.PodID, &m.UserID, &m.GoalID, &joinedAtStr, &leftAtStr,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotMember
		}
		return nil, fmt.Errorf("failed to get active member: %w", err)
	}

	if parsed, err := time.Parse(time.RFC3339, joinedAtStr); err == nil {
		m.JoinedAt = parsed
	}
	if leftAtStr != nil {
		if parsed, err := time.Parse(time.RFC3339, *leftAtStr); err == nil {
			m.LeftAt = &parsed
		}
	}

	return &m, nil
}

// RequireMember validates active membership in a pod.
func (r *Repository) RequireMember(ctx context.Context, podID, userID string) (*PodMember, error) {
	// First check if pod exists
	if _, err := r.GetByID(ctx, podID); err != nil {
		return nil, err
	}
	return r.GetActiveMember(ctx, podID, userID)
}

// GetPodDetail retrieves a pod detail including both members (profile + goal) and streak summary.
func (r *Repository) GetPodDetail(ctx context.Context, id string) (*PodDetail, error) {
	pod, err := r.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	detail := &PodDetail{
		ID:           pod.ID,
		GoalCategory: pod.GoalCategory,
		Status:       pod.Status,
		Capacity:     pod.Capacity,
		CreatedAt:    pod.CreatedAt,
		UpdatedAt:    pod.UpdatedAt,
		Members:      make([]PodMemberDetail, 0, 2),
		Streak: StreakSummary{
			CurrentStreak:   0,
			BestStreak:      0,
			LastCheckInDate: nil,
		},
	}

	// 1. Fetch members with user profile and goal details
	memberQuery := `
		SELECT pm.joined_at, pm.left_at,
		       u.id, u.name, u.avatar_url,
		       g.id, g.title, g.category, g.pace
		FROM pod_members pm
		JOIN users u ON pm.user_id = u.id
		JOIN goals g ON pm.goal_id = g.id
		WHERE pm.pod_id = ?
		ORDER BY pm.joined_at ASC;
	`
	rows, err := r.readDB.QueryContext(ctx, memberQuery, id)
	if err != nil {
		return nil, fmt.Errorf("failed to query pod members: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var joinedAtStr string
		var leftAtStr *string
		var m PodMemberDetail

		if err := rows.Scan(
			&joinedAtStr, &leftAtStr,
			&m.User.ID, &m.User.Name, &m.User.AvatarURL,
			&m.Goal.ID, &m.Goal.Title, &m.Goal.Category, &m.Goal.Pace,
		); err != nil {
			return nil, fmt.Errorf("failed to scan member detail: %w", err)
		}

		if parsed, err := time.Parse(time.RFC3339, joinedAtStr); err == nil {
			m.JoinedAt = parsed
		}
		if leftAtStr != nil {
			if parsed, err := time.Parse(time.RFC3339, *leftAtStr); err == nil {
				m.LeftAt = &parsed
			}
		}

		detail.Members = append(detail.Members, m)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("row iteration error: %w", err)
	}

	// 2. Fetch streak summary
	streakQuery := `
		SELECT current_streak, best_streak, last_check_in_date
		FROM streaks
		WHERE pod_id = ?;
	`
	_ = r.readDB.QueryRowContext(ctx, streakQuery, id).Scan(
		&detail.Streak.CurrentStreak,
		&detail.Streak.BestStreak,
		&detail.Streak.LastCheckInDate,
	)

	return detail, nil
}

// ListActivePodsForUser retrieves all pods the user is an active member of (left_at IS NULL).
func (r *Repository) ListActivePodsForUser(ctx context.Context, userID string) ([]*PodDetail, error) {
	query := `
		SELECT p.id
		FROM pods p
		JOIN pod_members pm ON p.id = pm.pod_id
		WHERE pm.user_id = ? AND (pm.left_at IS NULL OR pm.left_at = '')
		ORDER BY p.created_at DESC;
	`
	rows, err := r.readDB.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to query active pods: %w", err)
	}
	defer rows.Close()

	var podIDs []string
	for rows.Next() {
		var podID string
		if err := rows.Scan(&podID); err != nil {
			return nil, fmt.Errorf("failed to scan pod id: %w", err)
		}
		podIDs = append(podIDs, podID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("row iteration error: %w", err)
	}

	podsList := make([]*PodDetail, 0, len(podIDs))
	for _, pid := range podIDs {
		detail, err := r.GetPodDetail(ctx, pid)
		if err != nil {
			return nil, err
		}
		podsList = append(podsList, detail)
	}

	return podsList, nil
}

// LeaveUser sets pod_members.left_at for the user; if active members drop below 2, sets pods.status to dissolved.
// Executes in a single SQLite write transaction.
func (r *Repository) LeaveUser(ctx context.Context, podID, userID string) error {
	tx, err := r.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin leave transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	// 1. Check if pod exists
	var podStatus string
	if err := tx.QueryRowContext(ctx, `SELECT status FROM pods WHERE id = ?;`, podID).Scan(&podStatus); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrPodNotFound
		}
		return fmt.Errorf("failed to check pod: %w", err)
	}

	// 2. Check if user is an active member
	var memberID string
	var leftAt *string
	err = tx.QueryRowContext(ctx, `
		SELECT id, left_at FROM pod_members
		WHERE pod_id = ? AND user_id = ?;
	`, podID, userID).Scan(&memberID, &leftAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotMember
		}
		return fmt.Errorf("failed to check member status: %w", err)
	}

	if leftAt != nil && *leftAt != "" {
		return ErrAlreadyLeft
	}

	now := time.Now().UTC().Format(time.RFC3339)

	// 3. Set left_at on pod_members
	updateMemberQuery := `
		UPDATE pod_members
		SET left_at = ?
		WHERE id = ? AND left_at IS NULL;
	`
	res, err := tx.ExecContext(ctx, updateMemberQuery, now, memberID)
	if err != nil {
		return fmt.Errorf("failed to set left_at: %w", err)
	}
	rowsAffected, err := res.RowsAffected()
	if err != nil || rowsAffected == 0 {
		return ErrAlreadyLeft
	}

	// 4. Count remaining active members in the pod
	countQuery := `
		SELECT COUNT(*)
		FROM pod_members
		WHERE pod_id = ? AND (left_at IS NULL OR left_at = '');
	`
	var activeMembers int
	if err := tx.QueryRowContext(ctx, countQuery, podID).Scan(&activeMembers); err != nil {
		return fmt.Errorf("failed to count active members: %w", err)
	}

	// 5. If active members drop below 2, set pods.status to dissolved
	if activeMembers < 2 {
		dissolveQuery := `
			UPDATE pods
			SET status = 'dissolved', updated_at = ?
			WHERE id = ?;
		`
		if _, err := tx.ExecContext(ctx, dissolveQuery, now, podID); err != nil {
			return fmt.Errorf("failed to update pod status to dissolved: %w", err)
		}
	}

	return tx.Commit()
}

// LeaveUser is a package-level function for leaving a pod, reusable by safety/blocks code.
func LeaveUser(ctx context.Context, podID, userID string) error {
	if defaultRepo == nil {
		return errors.New("pods repository not initialized")
	}
	return defaultRepo.LeaveUser(ctx, podID, userID)
}

// RequireMemberUser is a package-level function for verifying active pod membership, reusable by handlers/services.
func RequireMemberUser(ctx context.Context, podID, userID string) (*PodMember, error) {
	if defaultRepo == nil {
		return nil, errors.New("pods repository not initialized")
	}
	return defaultRepo.RequireMember(ctx, podID, userID)
}

type errResponse struct {
	Data  any       `json:"data"`
	Meta  any       `json:"meta"`
	Error *apiError `json:"error"`
}

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func respondErr(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(errResponse{
		Data: nil,
		Meta: nil,
		Error: &apiError{
			Code:    code,
			Message: message,
		},
	})
}

// RequireMember returns a Chi middleware that enforces active pod membership (left_at IS NULL).
// If podID is provided, it validates against that ID.
// If podID is omitted or empty, it extracts the pod ID from Chi URL params ("id", "podID", "pod_id") or query params ("pod_id", "podId").
func RequireMember(podID ...string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			user, ok := auth.UserFromContext(r.Context())
			if !ok || user == nil {
				respondErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
				return
			}

			targetPodID := ""
			if len(podID) > 0 && podID[0] != "" {
				targetPodID = podID[0]
			} else {
				targetPodID = chi.URLParam(r, "id")
				if targetPodID == "" {
					targetPodID = chi.URLParam(r, "podID")
				}
				if targetPodID == "" {
					targetPodID = chi.URLParam(r, "pod_id")
				}
				if targetPodID == "" {
					targetPodID = chi.URLParam(r, "pod")
				}
				if targetPodID == "" {
					targetPodID = r.URL.Query().Get("pod_id")
				}
				if targetPodID == "" {
					targetPodID = r.URL.Query().Get("podId")
				}
			}

			if targetPodID == "" {
				respondErr(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
				return
			}

			repo := defaultRepo
			if repo == nil {
				respondErr(w, http.StatusInternalServerError, "INTERNAL_ERROR", "pods repository not initialized")
				return
			}

			// 1. Check if pod exists
			pod, err := repo.GetByID(r.Context(), targetPodID)
			if err != nil {
				if errors.Is(err, ErrPodNotFound) {
					respondErr(w, http.StatusNotFound, "NOT_FOUND", "pod not found")
					return
				}
				respondErr(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check pod")
				return
			}

			// 2. Check active membership (left_at IS NULL)
			member, err := repo.GetActiveMember(r.Context(), targetPodID, user.ID)
			if err != nil {
				if errors.Is(err, ErrNotMember) {
					respondErr(w, http.StatusForbidden, "FORBIDDEN", "you are not an active member of this pod")
					return
				}
				respondErr(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to verify pod membership")
				return
			}

			// 3. Inject verified pod and member into context
			ctx := WithPod(r.Context(), pod)
			ctx = WithPodMember(ctx, member)

			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
