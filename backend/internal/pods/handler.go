package pods

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/abshwabu/pair/backend/internal/auth"
)

// Handler provides HTTP endpoints for pods.
type Handler struct {
	repo *Repository
}

// NewHandler creates a new pods Handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// RegisterRoutes registers all pod endpoints with authentication and membership checks on a Chi router.
func (h *Handler) RegisterRoutes(r chi.Router, authMW func(http.Handler) http.Handler) {
	r.Route("/pods", func(r chi.Router) {
		r.Use(authMW)
		r.Get("/", h.List)
		r.Route("/{pod}", func(r chi.Router) {
			r.Use(RequireMember())
			r.Get("/", h.GetByID)
			r.Post("/leave", h.Leave)
		})
	})
}

type response struct {
	Data  any       `json:"data"`
	Meta  any       `json:"meta"`
	Error *apiError `json:"error"`
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

// List lists all pods the authenticated user is currently an active member of (left_at IS NULL).
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	activePods, err := h.repo.ListActivePodsForUser(r.Context(), user.ID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list pods")
		return
	}

	if activePods == nil {
		activePods = make([]*PodDetail, 0)
	}

	respondJSON(w, http.StatusOK, activePods)
}

// GetByID returns the detail of a single pod (including members and streak summary).
// Requires active membership (enforced by RequireMember middleware or checked directly).
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	podID := chi.URLParam(r, "id")
	if podID == "" {
		podID = chi.URLParam(r, "pod")
	}
	if podID == "" {
		podID = chi.URLParam(r, "podID")
	}
	if podID == "" {
		podID = chi.URLParam(r, "pod_id")
	}
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	// Double-check membership if handler was mounted outside RequireMember middleware
	if _, ok := PodMemberFromContext(r.Context()); !ok {
		if _, err := h.repo.RequireMember(r.Context(), podID, user.ID); err != nil {
			if errors.Is(err, ErrPodNotFound) {
				respondError(w, http.StatusNotFound, "NOT_FOUND", "pod not found")
				return
			}
			if errors.Is(err, ErrNotMember) {
				respondError(w, http.StatusForbidden, "FORBIDDEN", "you are not an active member of this pod")
				return
			}
			respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to verify pod membership")
			return
		}
	}

	detail, err := h.repo.GetPodDetail(r.Context(), podID)
	if err != nil {
		if errors.Is(err, ErrPodNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "pod not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to get pod detail")
		return
	}

	respondJSON(w, http.StatusOK, detail)
}

// Leave marks the authenticated user as left from the pod.
// If active members drop below 2, sets the pod status to dissolved.
func (h *Handler) Leave(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	podID := chi.URLParam(r, "id")
	if podID == "" {
		podID = chi.URLParam(r, "pod")
	}
	if podID == "" {
		podID = chi.URLParam(r, "podID")
	}
	if podID == "" {
		podID = chi.URLParam(r, "pod_id")
	}
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	err := h.repo.LeaveUser(r.Context(), podID, user.ID)
	if err != nil {
		if errors.Is(err, ErrPodNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "pod not found")
			return
		}
		if errors.Is(err, ErrNotMember) || errors.Is(err, ErrAlreadyLeft) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you are not an active member of this pod")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to leave pod")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"message": "left pod successfully",
	})
}
