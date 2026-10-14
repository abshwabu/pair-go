package httpapi

import (
	"errors"
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/auth"
	"github.com/abshwabu/pair/backend/internal/users"
)

// AuthHandler handles authentication HTTP requests.
type AuthHandler struct {
	authRepo  *auth.Repository
	usersRepo *users.Repository
}

// NewAuthHandler creates a new AuthHandler.
func NewAuthHandler(authRepo *auth.Repository, usersRepo *users.Repository) *AuthHandler {
	return &AuthHandler{
		authRepo:  authRepo,
		usersRepo: usersRepo,
	}
}

// RegisterRequest represents the JSON payload for registration.
type RegisterRequest struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"`
	Timezone string `json:"timezone"`
}

// AuthResponse represents the success payload returned for register and login.
type AuthResponse struct {
	Token string      `json:"token"`
	User  *users.User `json:"user"`
}

// Register handles POST /api/v1/auth/register.
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req RegisterRequest
	if err := DecodeJSON(r, &req); err != nil {
		ValidationError(w, err.Error())
		return
	}

	// Validate inputs
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		ValidationError(w, "name is required")
		return
	}

	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if !isValidEmail(req.Email) {
		ValidationError(w, "invalid email address format")
		return
	}

	if len(req.Password) < 8 {
		ValidationError(w, "password must be at least 8 characters long")
		return
	}

	req.Timezone = strings.TrimSpace(req.Timezone)
	if _, err := time.LoadLocation(req.Timezone); err != nil || req.Timezone == "" {
		ValidationError(w, "invalid IANA timezone name")
		return
	}

	// Check if user already exists
	existing, err := h.usersRepo.GetByEmail(r.Context(), req.Email)
	if err == nil && existing != nil {
		Fail(w, http.StatusConflict, "EMAIL_EXISTS", "a user with this email already exists")
		return
	} else if err != nil && !errors.Is(err, users.ErrUserNotFound) {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check existing user")
		return
	}

	// Hash password
	passwordHash, err := auth.HashPassword(req.Password)
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to hash password")
		return
	}

	now := time.Now().UTC()
	user := &users.User{
		ID:           uuid.NewString(),
		Name:         req.Name,
		Email:        req.Email,
		PasswordHash: passwordHash,
		Timezone:     req.Timezone,
		Language:     "en",
		IsAdmin:      false,
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	if err := h.usersRepo.Create(r.Context(), user); err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create user account")
		return
	}

	// Issue token
	rawToken, err := auth.GenerateRawToken()
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to generate session token")
		return
	}

	token := &auth.AuthToken{
		ID:        uuid.NewString(),
		UserID:    user.ID,
		TokenHash: auth.HashToken(rawToken),
		CreatedAt: now,
	}
	if err := h.authRepo.Create(r.Context(), token); err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create session token")
		return
	}

	OK(w, http.StatusCreated, AuthResponse{
		Token: rawToken,
		User:  user,
	})
}

// LoginRequest represents the JSON payload for logging in.
type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// Login handles POST /api/v1/auth/login.
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req LoginRequest
	if err := DecodeJSON(r, &req); err != nil {
		ValidationError(w, err.Error())
		return
	}

	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if req.Email == "" || req.Password == "" {
		ValidationError(w, "email and password are required")
		return
	}

	user, err := h.usersRepo.GetByEmail(r.Context(), req.Email)
	if err != nil || user.DeletedAt != nil {
		Fail(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "invalid email or password")
		return
	}

	if !auth.CheckPassword(req.Password, user.PasswordHash) {
		Fail(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "invalid email or password")
		return
	}

	// Issue token
	rawToken, err := auth.GenerateRawToken()
	if err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to generate session token")
		return
	}

	now := time.Now().UTC()
	token := &auth.AuthToken{
		ID:        uuid.NewString(),
		UserID:    user.ID,
		TokenHash: auth.HashToken(rawToken),
		CreatedAt: now,
	}
	if err := h.authRepo.Create(r.Context(), token); err != nil {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create session token")
		return
	}

	OK(w, http.StatusOK, AuthResponse{
		Token: rawToken,
		User:  user,
	})
}

// Logout handles POST /api/v1/auth/logout.
func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	tokenHash, ok := auth.TokenHashFromContext(r.Context())
	if !ok || tokenHash == "" {
		Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing active session")
		return
	}

	if err := h.authRepo.DeleteByHash(r.Context(), tokenHash); err != nil && !errors.Is(err, auth.ErrTokenNotFound) {
		Fail(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to terminate session")
		return
	}

	OK(w, http.StatusOK, map[string]string{
		"message": "logged out successfully",
	})
}

// Me handles GET /api/v1/auth/me.
func (h *AuthHandler) Me(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok || user == nil {
		Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not authenticated")
		return
	}

	OK(w, http.StatusOK, user)
}

func isValidEmail(email string) bool {
	if email == "" {
		return false
	}
	addr, err := mail.ParseAddress(email)
	if err != nil || addr.Address != email {
		return false
	}
	parts := strings.Split(email, "@")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return false
	}
	return strings.Contains(parts[1], ".")
}
