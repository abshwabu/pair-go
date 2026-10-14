package notifications

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/abshwabu/pair/backend/internal/auth"
)

// Handler provides HTTP endpoints for notifications.
type Handler struct {
	repo *Repository
}

// NewHandler creates a new notifications Handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{
		repo: repo,
	}
}

// RegisterRoutes registers notifications routes on a Chi router.
func (h *Handler) RegisterRoutes(r chi.Router, authMW func(http.Handler) http.Handler) {
	r.Route("/notifications", func(r chi.Router) {
		r.Use(authMW)
		r.Get("/", h.ListNotifications)
		r.Patch("/{id}/read", h.MarkRead)
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

func respondJSON(w http.ResponseWriter, status int, data any, meta any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(response{
		Data:  data,
		Meta:  meta,
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

// ListNotifications handles GET /api/v1/notifications (paginated, newest first).
func (h *Handler) ListNotifications(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	limit := 50
	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if l, err := strconv.Atoi(lStr); err == nil && l > 0 {
			limit = l
		}
	}

	var beforePtr *string
	if b := r.URL.Query().Get("before"); b != "" {
		beforePtr = &b
	} else if c := r.URL.Query().Get("cursor"); c != "" {
		beforePtr = &c
	}

	items, nextCursor, err := h.repo.ListByUserID(r.Context(), user.ID, beforePtr, limit)
	if err != nil {
		if errors.Is(err, ErrCursorNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "cursor notification not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list notifications")
		return
	}

	if items == nil {
		items = make([]*Notification, 0)
	}

	respondJSON(w, http.StatusOK, items, map[string]any{
		"next_cursor": nextCursor,
	})
}

// MarkRead handles PATCH /api/v1/notifications/{id}/read (sets read_at, owner only).
func (h *Handler) MarkRead(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing notification id")
		return
	}

	updated, err := h.repo.MarkRead(r.Context(), id, user.ID, time.Now().UTC())
	if err != nil {
		if errors.Is(err, ErrNotificationNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "notification not found")
			return
		}
		if errors.Is(err, ErrForbidden) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you do not have permission to modify this notification")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to mark notification as read")
		return
	}

	respondJSON(w, http.StatusOK, updated, nil)
}
