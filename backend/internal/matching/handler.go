package matching

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
	"github.com/abshwabu/pair/backend/internal/goals"
)

// Handler handles matching HTTP API requests.
type Handler struct {
	matchingRepo *Repository
	goalsRepo    *goals.Repository
	worker       *Worker
}

// NewHandler creates a new matching Handler.
func NewHandler(matchingRepo *Repository, goalsRepo *goals.Repository, worker *Worker) *Handler {
	return &Handler{
		matchingRepo: matchingRepo,
		goalsRepo:    goalsRepo,
		worker:       worker,
	}
}

// RegisterRoutes registers the matching routes onto a Chi router.
func (h *Handler) RegisterRoutes(r chi.Router, authMW func(http.Handler) http.Handler) {
	r.Route("/matching", func(r chi.Router) {
		r.Use(authMW)
		r.Post("/request", h.CreateRequest)
		r.Get("/request/{id}", h.GetRequest)
		r.Delete("/request/{id}", h.CancelRequest)
	})
}

// CreateRequestPayload represents the input payload for creating a match request.
type CreateRequestPayload struct {
	GoalID                 string `json:"goal_id"`
	TimezoneToleranceHours *int   `json:"timezone_tolerance_hours"`
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

// CreateRequest handles POST /api/v1/matching/request
func (h *Handler) CreateRequest(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	var req CreateRequestPayload
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	goalID := strings.TrimSpace(req.GoalID)
	if goalID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "goal_id is required")
		return
	}

	if req.TimezoneToleranceHours == nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "timezone_tolerance_hours is required")
		return
	}

	if *req.TimezoneToleranceHours < 0 || *req.TimezoneToleranceHours > 12 {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "timezone_tolerance_hours must be between 0 and 12")
		return
	}

	// Verify goal exists and belongs to the user
	g, err := h.goalsRepo.GetByID(r.Context(), goalID)
	if err != nil {
		if errors.Is(err, goals.ErrGoalNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "goal not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to retrieve goal")
		return
	}

	if err := goals.AuthorizeOwner(g, user.ID); err != nil {
		respondError(w, http.StatusForbidden, "FORBIDDEN", "goal does not belong to you")
		return
	}

	// Reject if user already has an open request
	hasOpen, err := h.matchingRepo.HasOpenRequest(r.Context(), user.ID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check existing requests")
		return
	}
	if hasOpen {
		respondError(w, http.StatusConflict, "ACTIVE_REQUEST_CONFLICT", "user already has an open matching request")
		return
	}

	// Reject if user is an active member of an active pod
	inActivePod, err := h.matchingRepo.IsUserInActivePod(r.Context(), user.ID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check active pod membership")
		return
	}
	if inActivePod {
		respondError(w, http.StatusConflict, "ACTIVE_POD_CONFLICT", "user is already an active member of an active pod")
		return
	}

	lang := strings.TrimSpace(user.Language)
	if lang == "" {
		lang = "en"
	}

	now := time.Now().UTC()
	requestID := uuid.NewString()

	podReq := &PodRequest{
		ID:                     requestID,
		UserID:                 user.ID,
		GoalID:                 goalID,
		Status:                 PodRequestStatusOpen,
		TimezoneToleranceHours: *req.TimezoneToleranceHours,
		Language:               lang,
		PodID:                  nil,
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	if err := h.matchingRepo.Create(r.Context(), podReq); err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create match request")
		return
	}

	// Signal matching worker
	if h.worker != nil {
		h.worker.Enqueue(requestID)
	}

	respondJSON(w, http.StatusCreated, podReq)
}

// GetRequest handles GET /api/v1/matching/request/{id}
func (h *Handler) GetRequest(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing request id parameter")
		return
	}

	pr, err := h.matchingRepo.GetByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, ErrRequestNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "pod request not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to retrieve pod request")
		return
	}

	if pr.UserID != user.ID {
		respondError(w, http.StatusForbidden, "FORBIDDEN", "you do not have permission to view this request")
		return
	}

	respondJSON(w, http.StatusOK, pr)
}

// CancelRequest handles DELETE /api/v1/matching/request/{id}
func (h *Handler) CancelRequest(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing request id parameter")
		return
	}

	pr, err := h.matchingRepo.GetByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, ErrRequestNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "pod request not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to retrieve pod request")
		return
	}

	if pr.UserID != user.ID {
		respondError(w, http.StatusForbidden, "FORBIDDEN", "you do not have permission to cancel this request")
		return
	}

	if pr.Status == PodRequestStatusMatched {
		respondError(w, http.StatusConflict, "ALREADY_MATCHED", "cannot cancel request that has already been matched")
		return
	}

	if err := h.matchingRepo.Cancel(r.Context(), id, user.ID); err != nil {
		if errors.Is(err, ErrAlreadyMatched) {
			respondError(w, http.StatusConflict, "ALREADY_MATCHED", "cannot cancel request that has already been matched")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to cancel pod request")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"message": "request cancelled successfully",
	})
}
