package matching

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/auth"
	"github.com/abshwabu/pair/backend/internal/goals"
	"github.com/abshwabu/pair/backend/internal/users"
)

// Handler handles matching HTTP API requests.
type Handler struct {
	matchingRepo *Repository
	goalsRepo    *goals.Repository
	usersRepo    *users.Repository
	worker       *Worker
	notifier     Notifier
}

// NewHandler creates a new matching Handler.
func NewHandler(
	matchingRepo *Repository,
	goalsRepo *goals.Repository,
	usersRepo *users.Repository,
	worker *Worker,
	notifiers ...Notifier,
) *Handler {
	var notif Notifier
	if len(notifiers) > 0 {
		notif = notifiers[0]
	}
	return &Handler{
		matchingRepo: matchingRepo,
		goalsRepo:    goalsRepo,
		usersRepo:    usersRepo,
		worker:       worker,
		notifier:     notif,
	}
}

// SetNotifier sets the notification service.
func (h *Handler) SetNotifier(n Notifier) {
	h.notifier = n
}

// RegisterRoutes registers the matching routes onto a Chi router.
func (h *Handler) RegisterRoutes(r chi.Router, authMW func(http.Handler) http.Handler) {
	r.Route("/matching", func(r chi.Router) {
		r.Use(authMW)
		r.Get("/current", h.GetCurrentState)
		r.Post("/request", h.CreateRequest)
		r.Get("/request/{id}", h.GetRequest)
		r.Delete("/request/{id}", h.CancelRequest)
		r.Post("/proposals/{id}/accept", h.AcceptProposal)
		r.Post("/proposals/{id}/reject", h.RejectProposal)
	})
}

// CreateRequestPayload represents the input payload for creating a match request.
type CreateRequestPayload struct {
	GoalID                 string `json:"goal_id"`
	TimezoneToleranceHours *int   `json:"timezone_tolerance_hours"`
}

// MatchingStateResponse represents the unified state shape.
type MatchingStateResponse struct {
	State     string          `json:"state"`
	RequestID *string         `json:"request_id"`
	PodID     *string         `json:"pod_id"`
	Proposal  *ProposalDetail `json:"proposal"`
}

// ProposalDetail holds safe proposal data presented to the caller.
type ProposalDetail struct {
	ID          string          `json:"id"`
	MyResponse  string          `json:"my_response"`
	ExpiresAt   string          `json:"expires_at"`
	Partner     PartnerProfile  `json:"partner"`
	PartnerGoal PartnerGoalInfo `json:"partner_goal"`
}

// PartnerProfile provides the partner's public info.
type PartnerProfile struct {
	Name           string  `json:"name"`
	AvatarURL      *string `json:"avatar_url"`
	Timezone       string  `json:"timezone"`
	UTCOffsetHours int     `json:"utc_offset_hours"`
}

// PartnerGoalInfo provides the partner's goal details.
type PartnerGoalInfo struct {
	Title    string `json:"title"`
	Category string `json:"category"`
	Pace     string `json:"pace"`
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

// buildStateResponse constructs the unified matching state payload for a given user.
func (h *Handler) buildStateResponse(ctx context.Context, userID, targetReqID string) (MatchingStateResponse, error) {
	// 1. Check if user is an active member of an active pod
	podID, active, err := h.matchingRepo.GetActivePodForUser(ctx, userID)
	if err == nil && active {
		return MatchingStateResponse{
			State:     "matched",
			RequestID: nil,
			PodID:     &podID,
			Proposal:  nil,
		}, nil
	}

	// 2. Fetch the target request or the user's latest request
	var pr *PodRequest
	if targetReqID != "" {
		req, err := h.matchingRepo.GetByID(ctx, targetReqID)
		if err != nil {
			return MatchingStateResponse{}, err
		}
		if req.UserID != userID {
			return MatchingStateResponse{}, ErrForbidden
		}
		pr = req
	} else {
		req, err := h.matchingRepo.GetLatestRequestForUser(ctx, userID)
		if err != nil {
			if errors.Is(err, ErrRequestNotFound) {
				return MatchingStateResponse{
					State:     "none",
					RequestID: nil,
					PodID:     nil,
					Proposal:  nil,
				}, nil
			}
			return MatchingStateResponse{}, err
		}
		pr = req
	}

	// 3. Map state based on request status
	switch pr.Status {
	case PodRequestStatusCancelled:
		return MatchingStateResponse{
			State:     "none",
			RequestID: nil,
			PodID:     nil,
			Proposal:  nil,
		}, nil

	case PodRequestStatusOpen:
		return MatchingStateResponse{
			State:     "searching",
			RequestID: &pr.ID,
			PodID:     nil,
			Proposal:  nil,
		}, nil

	case PodRequestStatusMatched:
		return MatchingStateResponse{
			State:     "matched",
			RequestID: &pr.ID,
			PodID:     pr.PodID,
			Proposal:  nil,
		}, nil

	case PodRequestStatusProposed:
		if pr.ProposalID == nil || *pr.ProposalID == "" {
			return MatchingStateResponse{
				State:     "searching",
				RequestID: &pr.ID,
				PodID:     nil,
				Proposal:  nil,
			}, nil
		}

		prop, err := h.matchingRepo.GetProposalByID(ctx, *pr.ProposalID)
		if err != nil {
			return MatchingStateResponse{
				State:     "searching",
				RequestID: &pr.ID,
				PodID:     nil,
				Proposal:  nil,
			}, nil
		}

		if prop.Status == ProposalStatusAccepted && prop.PodID != nil {
			return MatchingStateResponse{
				State:     "matched",
				RequestID: &pr.ID,
				PodID:     prop.PodID,
				Proposal:  nil,
			}, nil
		}

		if prop.Status != ProposalStatusPending {
			// Resolved as rejected/expired/cancelled
			return MatchingStateResponse{
				State:     "none",
				RequestID: nil,
				PodID:     nil,
				Proposal:  nil,
			}, nil
		}

		// Determine caller's response and partner identity
		var myResponse string
		var partnerID, partnerReqID string
		if userID == prop.UserAID {
			myResponse = string(prop.UserAResponse)
			partnerID = prop.UserBID
			partnerReqID = prop.RequestBID
		} else {
			myResponse = string(prop.UserBResponse)
			partnerID = prop.UserAID
			partnerReqID = prop.RequestAID
		}

		// Fetch partner user info
		var partnerProfile PartnerProfile
		if h.usersRepo != nil {
			partnerUser, err := h.usersRepo.GetByID(ctx, partnerID)
			if err == nil && partnerUser != nil {
				partnerProfile.Name = partnerUser.Name
				partnerProfile.AvatarURL = partnerUser.AvatarURL
				partnerProfile.Timezone = partnerUser.Timezone

				refTime := h.matchingRepo.Clock().Now()
				offHours, err := timezoneOffsetHours(partnerUser.Timezone, refTime)
				if err == nil {
					partnerProfile.UTCOffsetHours = int(math.Round(offHours))
				}
			}
		}

		// Fetch partner goal info
		var partnerGoalInfo PartnerGoalInfo
		if h.goalsRepo != nil {
			partnerReq, err := h.matchingRepo.GetByID(ctx, partnerReqID)
			if err == nil && partnerReq != nil {
				partnerGoal, err := h.goalsRepo.GetByID(ctx, partnerReq.GoalID)
				if err == nil && partnerGoal != nil {
					partnerGoalInfo.Title = partnerGoal.Title
					partnerGoalInfo.Category = string(partnerGoal.Category)
					partnerGoalInfo.Pace = string(partnerGoal.Pace)
				}
			}
		}

		return MatchingStateResponse{
			State:     "proposed",
			RequestID: &pr.ID,
			PodID:     nil,
			Proposal: &ProposalDetail{
				ID:          prop.ID,
				MyResponse:  myResponse,
				ExpiresAt:   prop.ExpiresAt.UTC().Format(time.RFC3339),
				Partner:     partnerProfile,
				PartnerGoal: partnerGoalInfo,
			},
		}, nil

	default:
		return MatchingStateResponse{
			State:     "none",
			RequestID: nil,
			PodID:     nil,
			Proposal:  nil,
		}, nil
	}
}

// GetCurrentState handles GET /api/v1/matching/current.
func (h *Handler) GetCurrentState(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	stateResp, err := h.buildStateResponse(r.Context(), user.ID, "")
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to fetch current matching state")
		return
	}

	respondJSON(w, http.StatusOK, stateResp)
}

// CreateRequest handles POST /api/v1/matching/request.
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
	if h.goalsRepo != nil {
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
	}

	// Reject if user has a request in status open or proposed
	hasActive, err := h.matchingRepo.HasActiveRequest(r.Context(), user.ID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check existing requests")
		return
	}
	if hasActive {
		respondError(w, http.StatusConflict, "ACTIVE_REQUEST_CONFLICT", "user already has an active matching request")
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

	now := h.matchingRepo.Clock().Now().UTC()
	requestID := uuid.NewString()

	podReq := &PodRequest{
		ID:                     requestID,
		UserID:                 user.ID,
		GoalID:                 goalID,
		Status:                 PodRequestStatusOpen,
		TimezoneToleranceHours: *req.TimezoneToleranceHours,
		Language:               lang,
		PodID:                  nil,
		ProposalID:             nil,
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

// GetRequest handles GET /api/v1/matching/request/{id}.
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

	stateResp, err := h.buildStateResponse(r.Context(), user.ID, id)
	if err != nil {
		if errors.Is(err, ErrRequestNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "pod request not found")
			return
		}
		if errors.Is(err, ErrForbidden) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you do not have permission to view this request")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to retrieve pod request")
		return
	}

	respondJSON(w, http.StatusOK, stateResp)
}

// CancelRequest handles DELETE /api/v1/matching/request/{id}.
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

	result, err := h.matchingRepo.CancelRequest(r.Context(), id, user.ID)
	if err != nil {
		if errors.Is(err, ErrRequestNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "pod request not found")
			return
		}
		if errors.Is(err, ErrForbidden) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you do not have permission to cancel this request")
			return
		}
		if errors.Is(err, ErrAlreadyMatched) {
			respondError(w, http.StatusConflict, "ALREADY_MATCHED", "cannot cancel request that has already been matched")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to cancel pod request")
		return
	}

	// If cancelled during proposed, reopen partner and notify
	if result != nil && result.WasProposed {
		if h.worker != nil && result.PartnerReqID != "" {
			h.worker.Enqueue(result.PartnerReqID)
		}
		if h.notifier != nil && result.PartnerID != "" {
			payload := map[string]any{
				"type":  "match_declined",
				"title": "Still looking",
				"body":  "Your last match didn't work out, we're finding you someone new",
			}
			_ = h.notifier.Send(r.Context(), result.PartnerID, "match_declined", payload)
		}
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"message": "request cancelled successfully",
	})
}

// AcceptProposal handles POST /api/v1/matching/proposals/{id}/accept.
func (h *Handler) AcceptProposal(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing proposal id")
		return
	}

	result, err := h.matchingRepo.AcceptProposal(r.Context(), id, user.ID)
	if err != nil {
		if errors.Is(err, ErrProposalNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "match proposal not found")
			return
		}
		if errors.Is(err, ErrForbidden) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you are not a participant in this proposal")
			return
		}
		if errors.Is(err, ErrProposalClosed) {
			respondError(w, http.StatusConflict, "proposal_closed", "match proposal is no longer pending")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to accept proposal: "+err.Error())
		return
	}

	// If both accepted, notify both users
	if result.BothAccepted && h.notifier != nil {
		payload := map[string]any{
			"type":   "match_confirmed",
			"pod_id": result.PodID,
			"title":  "You're paired!",
			"body":   "Your pod is ready",
		}
		_ = h.notifier.Send(r.Context(), user.ID, "match_confirmed", payload)
		_ = h.notifier.Send(r.Context(), result.PartnerID, "match_confirmed", payload)
	}

	stateResp, err := h.buildStateResponse(r.Context(), user.ID, result.CallerReqID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to build state response")
		return
	}

	respondJSON(w, http.StatusOK, stateResp)
}

// RejectProposal handles POST /api/v1/matching/proposals/{id}/reject.
func (h *Handler) RejectProposal(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	id := chi.URLParam(r, "id")
	if id == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing proposal id")
		return
	}

	result, err := h.matchingRepo.RejectProposal(r.Context(), id, user.ID)
	if err != nil {
		if errors.Is(err, ErrProposalNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "match proposal not found")
			return
		}
		if errors.Is(err, ErrForbidden) {
			respondError(w, http.StatusForbidden, "FORBIDDEN", "you are not a participant in this proposal")
			return
		}
		if errors.Is(err, ErrProposalClosed) {
			respondError(w, http.StatusConflict, "proposal_closed", "match proposal is already resolved")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to reject proposal: "+err.Error())
		return
	}

	// Signal worker for both requests
	if h.worker != nil {
		h.worker.Enqueue(result.ReqAID)
		h.worker.Enqueue(result.ReqBID)
	}

	// Notify the OTHER user
	if h.notifier != nil && result.PartnerID != "" {
		payload := map[string]any{
			"type":  "match_declined",
			"title": "Still looking",
			"body":  "Your last match didn't work out, we're finding you someone new",
		}
		_ = h.notifier.Send(r.Context(), result.PartnerID, "match_declined", payload)
	}

	// Return caller's new state (searching)
	stateResp, err := h.buildStateResponse(r.Context(), user.ID, result.CallerReqID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to build state response")
		return
	}

	respondJSON(w, http.StatusOK, stateResp)
}
