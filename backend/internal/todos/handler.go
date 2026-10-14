package todos

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/auth"
	"github.com/abshwabu/pair/backend/internal/pods"
)

// Handler provides HTTP endpoints for todos in a pod.
type Handler struct {
	repo *Repository
}

// NewHandler creates a new todos Handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// RegisterRoutes registers all todo endpoints on a Chi router with authentication and membership checks.
func (h *Handler) RegisterRoutes(r chi.Router, authMW func(http.Handler) http.Handler) {
	r.Route("/pods/{pod}/todos", func(r chi.Router) {
		r.Use(authMW)
		r.Use(pods.RequireMember())
		r.Get("/", h.List)
		r.Post("/", h.Create)
		r.Route("/{todo}", func(r chi.Router) {
			r.Patch("/", h.Update)
			r.Delete("/", h.Delete)
		})
	})
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

	if err := dec.Decode(dst); err != nil {
		var syntaxError *json.SyntaxError
		var unmarshalTypeError *json.UnmarshalTypeError

		switch {
		case errors.As(err, &syntaxError):
			return fmt.Errorf("malformed JSON at position %d", syntaxError.Offset)
		case errors.Is(err, io.ErrUnexpectedEOF):
			return errors.New("malformed JSON in request body")
		case errors.As(err, &unmarshalTypeError):
			return fmt.Errorf("invalid value for field %q at offset %d", unmarshalTypeError.Field, unmarshalTypeError.Offset)
		case strings.HasPrefix(err.Error(), "json: unknown field "):
			fieldName := strings.TrimPrefix(err.Error(), "json: unknown field ")
			return fmt.Errorf("unknown field %s", fieldName)
		default:
			return err
		}
	}

	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return errors.New("body must only contain a single JSON object")
	}

	return nil
}

func extractPodID(r *http.Request) string {
	if id := chi.URLParam(r, "pod"); id != "" {
		return id
	}
	if id := chi.URLParam(r, "id"); id != "" {
		return id
	}
	if id := chi.URLParam(r, "podID"); id != "" {
		return id
	}
	if id := chi.URLParam(r, "pod_id"); id != "" {
		return id
	}
	if id := r.URL.Query().Get("pod_id"); id != "" {
		return id
	}
	return r.URL.Query().Get("podId")
}

func extractTodoID(r *http.Request) string {
	if id := chi.URLParam(r, "todo"); id != "" {
		return id
	}
	if id := chi.URLParam(r, "todo_id"); id != "" {
		return id
	}
	if id := chi.URLParam(r, "todoID"); id != "" {
		return id
	}
	return chi.URLParam(r, "id")
}

// CreateTodoRequest defines input payload for creating a todo.
type CreateTodoRequest struct {
	Title      string  `json:"title"`
	Notes      *string `json:"notes"`
	DueDate    *string `json:"due_date"`
	AssignedTo *string `json:"assigned_to"`
}

// List handles GET /api/v1/pods/{pod}/todos.
// Supports query params: assigned_to, is_done, sort=due_date.
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	podID := extractPodID(r)
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	filter := ListFilter{
		PodID: podID,
		Sort:  r.URL.Query().Get("sort"),
	}

	if assigned := r.URL.Query().Get("assigned_to"); assigned != "" {
		filter.AssignedTo = &assigned
	}

	if isDoneParam := r.URL.Query().Get("is_done"); isDoneParam != "" {
		parsedBool, err := strconv.ParseBool(isDoneParam)
		if err != nil {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "invalid is_done filter (expected true/false)")
			return
		}
		filter.IsDone = &parsedBool
	}

	items, err := h.repo.List(r.Context(), filter)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list todos")
		return
	}

	if items == nil {
		items = make([]*Todo, 0)
	}

	respondJSON(w, http.StatusOK, items)
}

// Create handles POST /api/v1/pods/{pod}/todos.
// Creates a new todo in the given pod.
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	podID := extractPodID(r)
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	var req CreateTodoRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	title := strings.TrimSpace(req.Title)
	if title == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "title is required")
		return
	}

	var dueDate *string
	if req.DueDate != nil {
		d := strings.TrimSpace(*req.DueDate)
		if d != "" {
			if _, err := time.Parse("2006-01-02", d); err != nil {
				respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "due_date must be in YYYY-MM-DD format")
				return
			}
			dueDate = &d
		}
	}

	var assignedTo *string
	if req.AssignedTo != nil {
		a := strings.TrimSpace(*req.AssignedTo)
		if a != "" && a != "shared" {
			assignedTo = &a
		}
	}

	now := time.Now().UTC()
	todo := &Todo{
		ID:          uuid.NewString(),
		PodID:       podID,
		CreatedBy:   user.ID,
		AssignedTo:  assignedTo,
		Title:       title,
		Notes:       req.Notes,
		DueDate:     dueDate,
		IsDone:      false,
		CompletedAt: nil,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	if err := h.repo.Create(r.Context(), todo); err != nil {
		if errors.Is(err, ErrInvalidMember) {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "assigned_to must be an active member of the pod")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create todo")
		return
	}

	respondJSON(w, http.StatusCreated, todo)
}

// Update handles PATCH /api/v1/pods/{pod}/todos/{todo}.
// Applies partial updates and handles toggling is_done (completed_at).
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	podID := extractPodID(r)
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	todoID := extractTodoID(r)
	if todoID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing todo id")
		return
	}

	var raw map[string]json.RawMessage
	if err := decodeJSON(r, &raw); err != nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	var input UpdateTodoInput

	if rawTitle, exists := raw["title"]; exists {
		var title string
		if err := json.Unmarshal(rawTitle, &title); err != nil {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "title must be a string")
			return
		}
		title = strings.TrimSpace(title)
		if title == "" {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "title cannot be empty")
			return
		}
		input.Title = &title
	}

	if rawNotes, exists := raw["notes"]; exists {
		if string(rawNotes) == "null" {
			input.ClearNotes = true
		} else {
			var notes string
			if err := json.Unmarshal(rawNotes, &notes); err != nil {
				respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "notes must be a string or null")
				return
			}
			input.Notes = &notes
		}
	}

	if rawDueDate, exists := raw["due_date"]; exists {
		if string(rawDueDate) == "null" {
			input.ClearDueDate = true
		} else {
			var dueDate string
			if err := json.Unmarshal(rawDueDate, &dueDate); err != nil {
				respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "due_date must be a string or null")
				return
			}
			dueDate = strings.TrimSpace(dueDate)
			if dueDate == "" {
				input.ClearDueDate = true
			} else {
				if _, err := time.Parse("2006-01-02", dueDate); err != nil {
					respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "due_date must be in YYYY-MM-DD format")
					return
				}
				input.DueDate = &dueDate
			}
		}
	}

	if rawAssigned, exists := raw["assigned_to"]; exists {
		if string(rawAssigned) == "null" {
			input.ClearAssigned = true
		} else {
			var assigned string
			if err := json.Unmarshal(rawAssigned, &assigned); err != nil {
				respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "assigned_to must be a string or null")
				return
			}
			assigned = strings.TrimSpace(assigned)
			if assigned == "" || assigned == "shared" {
				input.ClearAssigned = true
			} else {
				input.AssignedTo = &assigned
			}
		}
	}

	if rawIsDone, exists := raw["is_done"]; exists {
		var isDone bool
		if err := json.Unmarshal(rawIsDone, &isDone); err != nil {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "is_done must be a boolean")
			return
		}
		input.IsDone = &isDone
	}

	updated, err := h.repo.Update(r.Context(), podID, todoID, input)
	if err != nil {
		if errors.Is(err, ErrTodoNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "todo not found")
			return
		}
		if errors.Is(err, ErrInvalidMember) {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "assigned_to must be an active member of the pod")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update todo")
		return
	}

	respondJSON(w, http.StatusOK, updated)
}

// Delete handles DELETE /api/v1/pods/{pod}/todos/{todo}.
// Allowed if requester is created_by, or todo is shared (assigned_to NULL); otherwise 403.
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	podID := extractPodID(r)
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	todoID := extractTodoID(r)
	if todoID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing todo id")
		return
	}

	err := h.repo.Delete(r.Context(), podID, todoID, user.ID)
	if err != nil {
		if errors.Is(err, ErrTodoNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "todo not found")
			return
		}
		if errors.Is(err, ErrForbidden) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you are not allowed to delete this todo")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to delete todo")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"message": "todo deleted successfully",
	})
}
