package goals

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/auth"
)

// Handler provides HTTP handlers for goal endpoints.
type Handler struct {
	repo *Repository
}

// NewHandler creates a new goals Handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// RegisterRoutes registers all goal endpoints with authentication on a Chi router.
func (h *Handler) RegisterRoutes(r chi.Router, authMW func(http.Handler) http.Handler) {
	r.Route("/goals", func(r chi.Router) {
		r.Use(authMW)
		r.Post("/", h.Create)
		r.Get("/", h.List)
		r.Get("/{id}", h.GetByID)
		r.Patch("/{id}", h.Update)
		r.Delete("/{id}", h.Delete)
	})
}

// CreateGoalRequest defines the input payload for creating a goal.
type CreateGoalRequest struct {
	Category          string `json:"category"`
	Title             string `json:"title"`
	TargetDescription string `json:"target_description"`
	Pace              string `json:"pace"`
}

// UpdateGoalRequest defines the input payload for updating a goal.
type UpdateGoalRequest struct {
	Category          *string `json:"category"`
	Title             *string `json:"title"`
	TargetDescription *string `json:"target_description"`
	Pace              *string `json:"pace"`
}

type response struct {
	Data  any       `json:"data"`
	Meta  any       `json:"meta"`
	Error *apiError `json:"error"`
}

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func respondJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(response{
		Data:  data,
		Meta:  nil,
		Error: nil,
	})
}

func respondError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(response{
		Data: nil,
		Meta: nil,
		Error: &apiError{
			Code:    code,
			Message: message,
		},
	})
}

func decodeJSON(r *http.Request, dst any) error {
	if r.Body == nil {
		return errors.New("request body cannot be empty")
	}

	maxBytesReader := http.MaxBytesReader(nil, r.Body, 1048576)
	dec := json.NewDecoder(maxBytesReader)
	dec.DisallowUnknownFields()

	err := dec.Decode(dst)
	if err != nil {
		var syntaxError *json.SyntaxError
		var unmarshalTypeError *json.UnmarshalTypeError

		switch {
		case errors.As(err, &syntaxError):
			return fmt.Errorf("malformed JSON at position %d", syntaxError.Offset)
		case errors.Is(err, io.ErrUnexpectedEOF):
			return errors.New("malformed JSON")
		case errors.As(err, &unmarshalTypeError):
			return fmt.Errorf("invalid value for field %q at position %d", unmarshalTypeError.Field, unmarshalTypeError.Offset)
		case strings.HasPrefix(err.Error(), "json: unknown field "):
			fieldName := strings.TrimPrefix(err.Error(), "json: unknown field ")
			return fmt.Errorf("unknown field %s", fieldName)
		case errors.Is(err, io.EOF):
			return errors.New("request body cannot be empty")
		case err.Error() == "http: request body too large":
			return errors.New("request body exceeds maximum allowed size (1MB)")
		default:
			return err
		}
	}

	if dec.More() {
		return errors.New("request body must contain only a single JSON object")
	}

	return nil
}

// Create handles POST /api/v1/goals (create a goal for the authenticated user).
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	var req CreateGoalRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	title := strings.TrimSpace(req.Title)
	if title == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "title is required")
		return
	}
	if len([]rune(title)) > 120 {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "title must not exceed 120 characters")
		return
	}

	cat := GoalCategory(strings.TrimSpace(req.Category))
	if !IsValidCategory(cat) {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "invalid category: must be one of read, watch, fitness, habit, custom")
		return
	}

	pace := GoalPace(strings.TrimSpace(req.Pace))
	if !IsValidPace(pace) {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "invalid pace: must be one of relaxed, steady, intense")
		return
	}

	now := time.Now().UTC()
	g := &Goal{
		ID:                uuid.NewString(),
		UserID:            user.ID,
		Category:          cat,
		Title:             title,
		TargetDescription: strings.TrimSpace(req.TargetDescription),
		Pace:              pace,
		CreatedAt:         now,
		UpdatedAt:         now,
	}

	if err := h.repo.Create(r.Context(), g); err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create goal")
		return
	}

	respondJSON(w, http.StatusCreated, g)
}

// List handles GET /api/v1/goals (list the authenticated user's goals, newest first).
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	list, err := h.repo.ListByUserID(r.Context(), user.ID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list goals")
		return
	}

	respondJSON(w, http.StatusOK, list)
}

// GetByID handles GET /api/v1/goals/{id} (show a single goal; 403 if not owner, 404 if not found).
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing goal id parameter")
		return
	}

	g, err := h.repo.GetByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, ErrGoalNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "goal not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to retrieve goal")
		return
	}

	if err := AuthorizeOwner(g, user.ID); err != nil {
		respondError(w, http.StatusForbidden, "FORBIDDEN", "you do not have permission to access this goal")
		return
	}

	respondJSON(w, http.StatusOK, g)
}

// Update handles PATCH /api/v1/goals/{id} (update goal if not attached to an active pod via pod_members; otherwise 409).
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing goal id parameter")
		return
	}

	g, err := h.repo.GetByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, ErrGoalNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "goal not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to retrieve goal")
		return
	}

	if err := AuthorizeOwner(g, user.ID); err != nil {
		respondError(w, http.StatusForbidden, "FORBIDDEN", "you do not have permission to update this goal")
		return
	}

	isAttached, err := h.repo.IsAttachedToActivePod(r.Context(), id)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check pod status")
		return
	}
	if isAttached {
		respondError(w, http.StatusConflict, "ACTIVE_POD_CONFLICT", "cannot update goal attached to an active pod")
		return
	}

	var req UpdateGoalRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	if req.Category == nil && req.Title == nil && req.TargetDescription == nil && req.Pace == nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "at least one field (category, title, target_description, pace) must be provided")
		return
	}

	var params UpdateGoalParams

	if req.Category != nil {
		cat := GoalCategory(strings.TrimSpace(*req.Category))
		if !IsValidCategory(cat) {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "invalid category: must be one of read, watch, fitness, habit, custom")
			return
		}
		params.Category = &cat
	}

	if req.Title != nil {
		title := strings.TrimSpace(*req.Title)
		if title == "" {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "title cannot be empty")
			return
		}
		if len([]rune(title)) > 120 {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "title must not exceed 120 characters")
			return
		}
		params.Title = &title
	}

	if req.TargetDescription != nil {
		desc := strings.TrimSpace(*req.TargetDescription)
		params.TargetDescription = &desc
	}

	if req.Pace != nil {
		pace := GoalPace(strings.TrimSpace(*req.Pace))
		if !IsValidPace(pace) {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "invalid pace: must be one of relaxed, steady, intense")
			return
		}
		params.Pace = &pace
	}

	updated, err := h.repo.Update(r.Context(), id, params)
	if err != nil {
		if errors.Is(err, ErrGoalNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "goal not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update goal")
		return
	}

	respondJSON(w, http.StatusOK, updated)
}

// Delete handles DELETE /api/v1/goals/{id} (delete goal if not attached to active pod; otherwise 409).
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing goal id parameter")
		return
	}

	g, err := h.repo.GetByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, ErrGoalNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "goal not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to retrieve goal")
		return
	}

	if err := AuthorizeOwner(g, user.ID); err != nil {
		respondError(w, http.StatusForbidden, "FORBIDDEN", "you do not have permission to delete this goal")
		return
	}

	isAttached, err := h.repo.IsAttachedToActivePod(r.Context(), id)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check pod status")
		return
	}
	if isAttached {
		respondError(w, http.StatusConflict, "ACTIVE_POD_CONFLICT", "cannot delete goal attached to an active pod")
		return
	}

	if err := h.repo.Delete(r.Context(), id); err != nil {
		if errors.Is(err, ErrGoalNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "goal not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to delete goal")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"message": "goal deleted successfully",
	})
}
