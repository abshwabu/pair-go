package httpapi

import (
	"database/sql"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/auth"
	"github.com/abshwabu/pair/backend/internal/chat"
	"github.com/abshwabu/pair/backend/internal/pods"
	"github.com/abshwabu/pair/backend/internal/storage"
	"github.com/abshwabu/pair/backend/internal/users"
)

// ProfileHandler handles user profile endpoints.
type ProfileHandler struct {
	usersRepo      *users.Repository
	authRepo       *auth.Repository
	podsRepo       *pods.Repository
	chatHub        *chat.Hub
	writeDB        *sql.DB
	storageService storage.StorageService
}

// NewProfileHandler creates a new ProfileHandler instance.
func NewProfileHandler(
	usersRepo *users.Repository,
	authRepo *auth.Repository,
	podsRepo *pods.Repository,
	chatHub *chat.Hub,
	writeDB *sql.DB,
	storageService storage.StorageService,
) *ProfileHandler {
	return &ProfileHandler{
		usersRepo:      usersRepo,
		authRepo:       authRepo,
		podsRepo:       podsRepo,
		chatHub:        chatHub,
		writeDB:        writeDB,
		storageService: storageService,
	}
}

// UpdateProfileRequest represents the request payload for updating profile fields.
type UpdateProfileRequest struct {
	Name     *string `json:"name"`
	Timezone *string `json:"timezone"`
	Language *string `json:"language"`
}

// GetProfile handles GET /api/v1/profile (returns authenticated user profile).
func (h *ProfileHandler) GetProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	// Refetch from database to ensure fresh state
	freshUser, err := h.usersRepo.GetByID(r.Context(), user.ID)
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to load user profile")
		return
	}

	OK(w, http.StatusOK, freshUser)
}

// UpdateProfile handles PATCH /api/v1/profile (partial updates to name, timezone, language).
func (h *ProfileHandler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	var req UpdateProfileRequest
	if err := DecodeJSON(r, &req); err != nil {
		ValidationError(w, err.Error())
		return
	}

	if req.Name == nil && req.Timezone == nil && req.Language == nil {
		ValidationError(w, "at least one field (name, timezone, language) must be provided")
		return
	}

	if req.Name != nil {
		trimmedName := strings.TrimSpace(*req.Name)
		if trimmedName == "" {
			ValidationError(w, "name cannot be empty")
			return
		}
		req.Name = &trimmedName
	}

	if req.Timezone != nil {
		trimmedTZ := strings.TrimSpace(*req.Timezone)
		if trimmedTZ == "" {
			ValidationError(w, "invalid IANA timezone name")
			return
		}
		if _, err := time.LoadLocation(trimmedTZ); err != nil {
			ValidationError(w, "invalid IANA timezone name")
			return
		}
		req.Timezone = &trimmedTZ
	}

	if req.Language != nil {
		trimmedLang := strings.TrimSpace(*req.Language)
		if trimmedLang == "" {
			ValidationError(w, "language cannot be empty")
			return
		}
		req.Language = &trimmedLang
	}

	updatedUser, err := h.usersRepo.UpdateProfile(r.Context(), user.ID, users.UpdateProfileParams{
		Name:     req.Name,
		Timezone: req.Timezone,
		Language: req.Language,
	})
	if err != nil {
		if errors.Is(err, users.ErrUserNotFound) {
			Fail(w, http.StatusNotFound, "USER_NOT_FOUND", "user not found")
			return
		}
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update user profile")
		return
	}

	OK(w, http.StatusOK, updatedUser)
}

// UploadAvatar handles POST /api/v1/profile/avatar (multipart upload field "file", max 5MB).
func (h *ProfileHandler) UploadAvatar(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	const maxFileSize = 5 * 1024 * 1024 // 5MB

	// Enforce body limit slightly larger than 5MB to accommodate multipart boundaries/headers
	r.Body = http.MaxBytesReader(w, r.Body, maxFileSize+(1<<20))

	if err := r.ParseMultipartForm(maxFileSize + (1 << 20)); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) || strings.Contains(err.Error(), "request body too large") {
			Fail(w, http.StatusBadRequest, "FILE_TOO_LARGE", "file exceeds maximum allowed size of 5MB")
			return
		}
		ValidationError(w, fmt.Sprintf("failed to parse multipart form: %v", err))
		return
	}

	file, fileHeader, err := r.FormFile("file")
	if err != nil {
		ValidationError(w, "missing required file field 'file'")
		return
	}
	defer file.Close()

	if fileHeader.Size > maxFileSize {
		Fail(w, http.StatusBadRequest, "FILE_TOO_LARGE", "file exceeds maximum allowed size of 5MB")
		return
	}

	// Sniff content type using the first 512 bytes
	buf := make([]byte, 512)
	n, err := file.Read(buf)
	if err != nil && !errors.Is(err, io.EOF) {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to read uploaded file")
		return
	}
	if n == 0 {
		ValidationError(w, "file cannot be empty")
		return
	}

	contentType := http.DetectContentType(buf[:n])

	var ext string
	switch contentType {
	case "image/jpeg":
		ext = "jpg"
	case "image/png":
		ext = "png"
	case "image/webp":
		ext = "webp"
	default:
		Fail(w, http.StatusBadRequest, "INVALID_FILE_TYPE", "invalid file type: only image/jpeg, image/png, and image/webp are allowed")
		return
	}

	// Rewind file to beginning
	if seeker, ok := file.(io.Seeker); ok {
		if _, err := seeker.Seek(0, io.SeekStart); err != nil {
			Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to rewind file stream")
			return
		}
	}

	key := fmt.Sprintf("avatars/%s/%s.%s", user.ID, uuid.NewString(), ext)

	publicURL, err := h.storageService.Upload(r.Context(), key, file, contentType)
	if err != nil {
		Fail(w, http.StatusInternalServerError, "STORAGE_ERROR", "failed to upload avatar")
		return
	}

	updatedUser, err := h.usersRepo.UpdateAvatarURL(r.Context(), user.ID, publicURL)
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update user avatar")
		return
	}

	OK(w, http.StatusOK, updatedUser)
}

// UpdateFCMTokenRequest represents the request payload for PATCH /api/v1/profile/fcm-token.
type UpdateFCMTokenRequest struct {
	FCMToken string `json:"fcm_token"`
}

// UpdateFCMToken handles PATCH /api/v1/profile/fcm-token.
func (h *ProfileHandler) UpdateFCMToken(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	var req UpdateFCMTokenRequest
	if err := DecodeJSON(r, &req); err != nil {
		ValidationError(w, err.Error())
		return
	}

	trimmed := strings.TrimSpace(req.FCMToken)
	if trimmed == "" {
		ValidationError(w, "fcm_token cannot be empty")
		return
	}

	if err := h.usersRepo.UpdateFCMToken(r.Context(), user.ID, &trimmed); err != nil {
		if errors.Is(err, users.ErrUserNotFound) {
			Fail(w, http.StatusNotFound, "USER_NOT_FOUND", "user not found")
			return
		}
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update fcm token")
		return
	}

	freshUser, err := h.usersRepo.GetByID(r.Context(), user.ID)
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to load updated profile")
		return
	}

	OK(w, http.StatusOK, freshUser)
}

// ChangePasswordRequest represents the request payload for PATCH /api/v1/profile/password.
type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

// ChangePassword handles PATCH /api/v1/profile/password.
func (h *ProfileHandler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	var req ChangePasswordRequest
	if err := DecodeJSON(r, &req); err != nil {
		ValidationError(w, err.Error())
		return
	}

	if req.CurrentPassword == "" {
		ValidationError(w, "current_password is required")
		return
	}
	if len(req.NewPassword) < 8 {
		ValidationError(w, "new_password must be at least 8 characters")
		return
	}

	// Refetch fresh user to obtain current password hash
	freshUser, err := h.usersRepo.GetByID(r.Context(), user.ID)
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to load user")
		return
	}

	if !auth.CheckPassword(req.CurrentPassword, freshUser.PasswordHash) {
		Fail(w, http.StatusBadRequest, "INVALID_PASSWORD", "current password is incorrect")
		return
	}

	newHash, err := auth.HashPassword(req.NewPassword)
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to hash new password")
		return
	}

	if err := h.usersRepo.UpdatePasswordHash(r.Context(), user.ID, newHash); err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update password")
		return
	}

	// Revoke all other tokens for the user, retaining only the current token
	if currentTokenHash, ok := auth.TokenHashFromContext(r.Context()); ok && currentTokenHash != "" {
		if h.authRepo != nil {
			_ = h.authRepo.DeleteAllExcept(r.Context(), user.ID, currentTokenHash)
		}
	}

	OK(w, http.StatusOK, map[string]string{
		"message": "password updated successfully",
	})
}

// DeleteAccount handles DELETE /api/v1/profile.
func (h *ProfileHandler) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	tx, err := h.writeDB.BeginTx(r.Context(), nil)
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to start deletion transaction")
		return
	}
	defer tx.Rollback()

	// 1. Find all active pods for user
	activePodsQuery := `
		SELECT p.id
		FROM pods p
		JOIN pod_members pm ON p.id = pm.pod_id AND pm.user_id = ? AND (pm.left_at IS NULL OR pm.left_at = '')
		WHERE p.status = 'active';
	`
	rows, err := tx.QueryContext(r.Context(), activePodsQuery, user.ID)
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to query user pods: "+err.Error())
		return
	}
	var podIDs []string
	for rows.Next() {
		var pid string
		if err := rows.Scan(&pid); err == nil {
			podIDs = append(podIDs, pid)
		}
	}
	rows.Close()

	// 2. Leave and dissolve active pods
	for _, pid := range podIDs {
		if h.podsRepo != nil {
			_ = h.podsRepo.LeaveUserTx(r.Context(), tx, pid, user.ID)
		} else {
			_ = pods.LeaveUserTx(r.Context(), tx, pid, user.ID)
		}
	}

	// 3. Anonymize user record and set deleted_at
	if err := h.usersRepo.AnonymizeAndDeleteTx(r.Context(), tx, user.ID); err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to anonymize user: "+err.Error())
		return
	}

	// 4. Delete all auth tokens
	if h.authRepo != nil {
		if err := h.authRepo.DeleteAllForUserTx(r.Context(), tx, user.ID); err != nil {
			Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to delete auth tokens: "+err.Error())
			return
		}
	} else {
		_, _ = tx.ExecContext(r.Context(), `DELETE FROM auth_tokens WHERE user_id = ?;`, user.ID)
	}

	if err := tx.Commit(); err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to commit account deletion: "+err.Error())
		return
	}

	// 5. Close live sockets for all affected pods
	if h.chatHub != nil {
		for _, pid := range podIDs {
			h.chatHub.ClosePod(pid)
		}
	}

	OK(w, http.StatusOK, map[string]string{
		"message": "account deleted successfully",
	})
}

