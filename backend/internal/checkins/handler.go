package checkins

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/abshwabu/pair/backend/internal/auth"
)

// Notifier defines the interface for emitting notifications.
type Notifier interface {
	Send(ctx context.Context, userID, notificationType string, payload map[string]any) error
}

// Handler provides HTTP endpoints for check-ins and streaks.
type Handler struct {
	repo          *Repository
	streakService *StreakService
	notifier      Notifier
	nudgeMu       sync.Mutex
	lastNudges    map[string]time.Time
}

// NewHandler creates a new checkins Handler.
func NewHandler(repo *Repository, streakService *StreakService) *Handler {
	return &Handler{
		repo:          repo,
		streakService: streakService,
		lastNudges:    make(map[string]time.Time),
	}
}

// SetNotifier sets the notification service on the Handler.
func (h *Handler) SetNotifier(n Notifier) {
	h.notifier = n
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

// CheckInRequest represents the payload for POST /api/v1/pods/{pod}/check-ins.
type CheckInRequest struct {
	Note *string `json:"note"`
}

// StreakStatus represents the embedded streak status in a check-in response.
type StreakStatus struct {
	CurrentStreak        int     `json:"current_streak"`
	BestStreak           int     `json:"best_streak"`
	LastCheckInDate      *string `json:"last_check_in_date"`
	CheckedInTodayByBoth bool    `json:"checked_in_today_by_both"`
}

// CheckInResult represents the combined response returned upon checking in.
type CheckInResult struct {
	ID                   string        `json:"id"`
	PodID                string        `json:"pod_id"`
	UserID               string        `json:"user_id"`
	CheckInDate          string        `json:"check_in_date"`
	Note                 *string       `json:"note,omitempty"`
	CreatedAt            time.Time     `json:"created_at"`
	CurrentStreak        int           `json:"current_streak"`
	BestStreak           int           `json:"best_streak"`
	LastCheckInDate      *string       `json:"last_check_in_date"`
	CheckedInTodayByBoth bool          `json:"checked_in_today_by_both"`
	CheckIn              *CheckIn      `json:"check_in"`
	Streak               *StreakStatus `json:"streak"`
}

// CheckIn records a daily check-in for the authenticated member in the pod.
// Note: Today's date is calculated strictly using UTC ("YYYY-MM-DD") because pod members
// may reside in different timezones across the globe; using a uniform UTC date ensures
// unambiguous daily synchronization and streak calculations for both partners.
func (h *Handler) CheckIn(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	podID := chi.URLParam(r, "pod")
	if podID == "" {
		podID = chi.URLParam(r, "id")
	}
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	var req CheckInRequest
	if r.Body != nil {
		bodyBytes, err := io.ReadAll(io.LimitReader(r.Body, 1048576))
		if err == nil && len(strings.TrimSpace(string(bodyBytes))) > 0 {
			dec := json.NewDecoder(strings.NewReader(string(bodyBytes)))
			dec.DisallowUnknownFields()
			if err := dec.Decode(&req); err != nil {
				respondError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid json body: "+err.Error())
				return
			}
		}
	}

	var note *string
	if req.Note != nil {
		trimmed := strings.TrimSpace(*req.Note)
		if len(trimmed) > 500 {
			respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "note must not exceed 500 characters")
			return
		}
		if trimmed != "" {
			note = &trimmed
		}
	}

	checkIn, streak, bothCheckedIn, err := h.repo.RecordCheckIn(r.Context(), podID, user.ID, note, h.streakService)
	if err != nil {
		if errors.Is(err, ErrAlreadyCheckedIn) {
			respondError(w, http.StatusConflict, "CONFLICT", "already checked in for today")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to record check-in: "+err.Error())
		return
	}

	streakStatus := &StreakStatus{
		CurrentStreak:        streak.CurrentStreak,
		BestStreak:           streak.BestStreak,
		LastCheckInDate:      streak.LastCheckInDate,
		CheckedInTodayByBoth: bothCheckedIn,
	}

	result := &CheckInResult{
		ID:                   checkIn.ID,
		PodID:                checkIn.PodID,
		UserID:               checkIn.UserID,
		CheckInDate:          checkIn.CheckInDate,
		Note:                 checkIn.Note,
		CreatedAt:            checkIn.CreatedAt,
		CurrentStreak:        streak.CurrentStreak,
		BestStreak:           streak.BestStreak,
		LastCheckInDate:      streak.LastCheckInDate,
		CheckedInTodayByBoth: bothCheckedIn,
		CheckIn:              checkIn,
		Streak:               streakStatus,
	}

	// Trigger checkin_nudge to partner if partner has not yet checked in today
	if !bothCheckedIn && h.notifier != nil {
		partnerID, err := h.repo.GetPartnerID(r.Context(), podID, user.ID)
		if err == nil && partnerID != "" {
			payload := map[string]any{
				"type":   "checkin_nudge",
				"pod_id": podID,
				"title":  "Check-in Reminder",
				"body":   user.Name + " checked in! Don't forget your daily check-in.",
			}
			_ = h.notifier.Send(r.Context(), partnerID, "checkin_nudge", payload)
		}
	}

	respondJSON(w, http.StatusCreated, result)
}

// ListCheckIns returns recent daily check-in participation for the pod, most recent first.
func (h *Handler) ListCheckIns(w http.ResponseWriter, r *http.Request) {
	podID := chi.URLParam(r, "pod")
	if podID == "" {
		podID = chi.URLParam(r, "id")
	}
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	limit := 60
	if limitStr := r.URL.Query().Get("limit"); limitStr != "" {
		if parsed, err := strconv.Atoi(limitStr); err == nil && parsed > 0 {
			limit = parsed
		}
	}

	items, err := h.repo.ListPodCheckInsByDate(r.Context(), podID, limit)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list check-ins: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, items)
}

// GetStreak returns the streak metrics and today's check-in status for the pod.
func (h *Handler) GetStreak(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	podID := chi.URLParam(r, "pod")
	if podID == "" {
		podID = chi.URLParam(r, "id")
	}
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	details, err := h.repo.GetPodStreakDetails(r.Context(), podID, user.ID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to get pod streak: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, details)
}

// Nudge handles POST /api/v1/pods/{pod}/nudge.
// Member-only, rate limited to 1 per 6 hours per pod per sender. Returns 429 otherwise.
func (h *Handler) Nudge(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		respondError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	podID := chi.URLParam(r, "pod")
	if podID == "" {
		podID = chi.URLParam(r, "id")
	}
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	now := time.Now().UTC()
	key := podID + ":" + user.ID

	h.nudgeMu.Lock()
	if h.lastNudges == nil {
		h.lastNudges = make(map[string]time.Time)
	}
	lastTime, exists := h.lastNudges[key]
	if exists && now.Sub(lastTime) < 6*time.Hour {
		h.nudgeMu.Unlock()
		respondError(w, http.StatusTooManyRequests, "RATE_LIMITED", "you can only nudge your partner once every 6 hours")
		return
	}
	h.lastNudges[key] = now
	h.nudgeMu.Unlock()

	partnerID, err := h.repo.GetPartnerID(r.Context(), podID, user.ID)
	if err != nil || partnerID == "" {
		respondError(w, http.StatusNotFound, "NOT_FOUND", "partner not found in pod")
		return
	}

	if h.notifier != nil {
		payload := map[string]any{
			"type":   "checkin_nudge",
			"pod_id": podID,
			"title":  "Check-in Reminder",
			"body":   user.Name + " nudged you to complete your daily check-in!",
		}
		_ = h.notifier.Send(r.Context(), partnerID, "checkin_nudge", payload)
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"message": "nudge sent successfully",
	})
}

