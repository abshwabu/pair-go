package safety

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/auth"
	"github.com/abshwabu/pair/backend/internal/chat"
	"github.com/abshwabu/pair/backend/internal/pods"
)

// Handler provides HTTP endpoints for reports and blocks.
type Handler struct {
	repo     *Repository
	podsRepo *pods.Repository
	chatHub  *chat.Hub
}

// NewHandler creates a new safety Handler.
func NewHandler(repo *Repository, podsRepo *pods.Repository, chatHub *chat.Hub) *Handler {
	return &Handler{
		repo:     repo,
		podsRepo: podsRepo,
		chatHub:  chatHub,
	}
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

	bodyBytes, err := io.ReadAll(io.LimitReader(r.Body, 1048576))
	if err != nil {
		return err
	}
	if len(strings.TrimSpace(string(bodyBytes))) == 0 {
		return errors.New("request body cannot be empty")
	}

	dec := json.NewDecoder(strings.NewReader(string(bodyBytes)))
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}

// CreateReportRequest defines the payload for POST /api/v1/reports.
type CreateReportRequest struct {
	ReportedUserID string  `json:"reported_user_id"`
	PodID          *string `json:"pod_id"`
	Reason         string  `json:"reason"`
}

// CreateReport handles user reports.
func (h *Handler) CreateReport(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	var req CreateReportRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid json: "+err.Error())
		return
	}

	reportedUserID := strings.TrimSpace(req.ReportedUserID)
	if reportedUserID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "reported_user_id is required")
		return
	}
	if reportedUserID == user.ID {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "cannot report yourself")
		return
	}

	reason := strings.TrimSpace(req.Reason)
	if len(reason) < 10 || len(reason) > 1000 {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "reason must be between 10 and 1000 characters")
		return
	}

	var podID *string
	if req.PodID != nil && strings.TrimSpace(*req.PodID) != "" {
		pid := strings.TrimSpace(*req.PodID)
		podID = &pid

		// If pod_id is given, the reporter must be a member of that pod
		isMember := false
		if h.podsRepo != nil {
			_, err := h.podsRepo.GetActiveMember(r.Context(), pid, user.ID)
			if err == nil {
				isMember = true
			}
		}
		if !isMember && h.repo != nil {
			m, err := h.repo.IsPodMember(r.Context(), pid, user.ID)
			if err == nil && m {
				isMember = true
			}
		}
		if !isMember {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you must be a member of the specified pod to report within it")
			return
		}
	}

	rep := &Report{
		ID:             uuid.NewString(),
		ReporterID:     user.ID,
		ReportedUserID: reportedUserID,
		PodID:          podID,
		Reason:         reason,
		Status:         ReportStatusOpen,
		CreatedAt:      time.Now().UTC(),
	}

	if err := h.repo.CreateReport(r.Context(), rep); err != nil {
		if errors.Is(err, ErrUserNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "reported user not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create report: "+err.Error())
		return
	}

	respondJSON(w, http.StatusCreated, rep)
}

// ListReports retrieves all reports for administrators, filtered by status.
func (h *Handler) ListReports(w http.ResponseWriter, r *http.Request) {
	statusParam := strings.TrimSpace(r.URL.Query().Get("status"))
	var statusFilter *ReportStatus

	if statusParam == "" {
		defaultStatus := ReportStatusOpen
		statusFilter = &defaultStatus
	} else if !strings.EqualFold(statusParam, "all") {
		st := ReportStatus(strings.ToLower(statusParam))
		statusFilter = &st
	}

	reports, err := h.repo.ListReports(r.Context(), statusFilter)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list reports: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, reports)
}

// UpdateReportRequest defines the payload for PATCH /api/v1/reports/{id}.
type UpdateReportRequest struct {
	Status string `json:"status"`
}

// UpdateReport allows an admin to update a report's status to 'reviewed' or 'dismissed'.
func (h *Handler) UpdateReport(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing report id")
		return
	}

	var req UpdateReportRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid json: "+err.Error())
		return
	}

	statusLower := strings.ToLower(strings.TrimSpace(req.Status))
	if statusLower != string(ReportStatusReviewed) && statusLower != string(ReportStatusDismissed) {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "status must be 'reviewed' or 'dismissed'")
		return
	}

	updated, err := h.repo.UpdateReportStatus(r.Context(), id, ReportStatus(statusLower))
	if err != nil {
		if errors.Is(err, ErrReportNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "report not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update report: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, updated)
}

// CreateBlockRequest defines the payload for POST /api/v1/blocks.
type CreateBlockRequest struct {
	BlockedUserID string `json:"blocked_user_id"`
}

// CreateBlock handles blocking another user.
func (h *Handler) CreateBlock(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	var req CreateBlockRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid json: "+err.Error())
		return
	}

	blockedUserID := strings.TrimSpace(req.BlockedUserID)
	if blockedUserID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "blocked_user_id is required")
		return
	}
	if blockedUserID == user.ID {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "cannot block yourself")
		return
	}

	block, _, err := h.repo.CreateBlock(r.Context(), user.ID, blockedUserID, h.podsRepo, h.chatHub)
	if err != nil {
		if errors.Is(err, ErrSelfBlock) {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "cannot block yourself")
			return
		}
		if errors.Is(err, ErrUserNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "user not found")
			return
		}
		if errors.Is(err, ErrDuplicateBlock) {
			respondError(w, http.StatusConflict, "CONFLICT", "user is already blocked")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to block user: "+err.Error())
		return
	}

	respondJSON(w, http.StatusCreated, block)
}

// ListBlocks retrieves all blocks created by the authenticated user.
func (h *Handler) ListBlocks(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	blocks, err := h.repo.ListBlocks(r.Context(), user.ID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list blocks: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, blocks)
}

// DeleteBlock unblocks a user. Only the block owner is permitted to unblock.
func (h *Handler) DeleteBlock(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing block id")
		return
	}

	if err := h.repo.DeleteBlock(r.Context(), id, user.ID); err != nil {
		if errors.Is(err, ErrBlockNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "block not found")
			return
		}
		if errors.Is(err, ErrForbidden) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you are not authorized to delete this block")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to delete block: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"message": "unblocked successfully",
	})
}

// RegisterRoutes registers safety endpoints on a Chi router.
func (h *Handler) RegisterRoutes(r chi.Router, authMW func(http.Handler) http.Handler, adminMW ...func(http.Handler) http.Handler) {
	var admMW func(http.Handler) http.Handler
	if len(adminMW) > 0 && adminMW[0] != nil {
		admMW = adminMW[0]
	}

	r.Route("/reports", func(r chi.Router) {
		r.Use(authMW)
		r.Post("/", h.CreateReport)

		if admMW != nil {
			r.Group(func(r chi.Router) {
				r.Use(admMW)
				r.Get("/", h.ListReports)
				r.Patch("/{id}", h.UpdateReport)
			})
		}
	})

	r.Route("/blocks", func(r chi.Router) {
		r.Use(authMW)
		r.Post("/", h.CreateBlock)
		r.Get("/", h.ListBlocks)
		r.Delete("/{id}", h.DeleteBlock)
	})
}
