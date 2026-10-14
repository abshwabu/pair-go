package httpapi

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/abshwabu/pair/backend/internal/auth"
	"github.com/abshwabu/pair/backend/internal/users"
)

// ExtractBearerToken extracts the bearer token from the Authorization header,
// falling back to the ?token= query parameter.
func ExtractBearerToken(r *http.Request) string {
	authHeader := r.Header.Get("Authorization")
	if authHeader != "" {
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
			return strings.TrimSpace(parts[1])
		}
	}
	if qToken := r.URL.Query().Get("token"); qToken != "" {
		return strings.TrimSpace(qToken)
	}
	return ""
}

// AuthMiddleware creates a Chi-compatible middleware that validates bearer tokens,
// verifies the user account status, updates last_used_at, and injects the user into context.
func AuthMiddleware(authRepo *auth.Repository, usersRepo *users.Repository) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			rawToken := ExtractBearerToken(r)
			if rawToken == "" {
				Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing or invalid authorization header")
				return
			}

			tokenHash := auth.HashToken(rawToken)
			token, err := authRepo.GetByHash(r.Context(), tokenHash)
			if err != nil {
				Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "invalid or expired token")
				return
			}

			user, err := usersRepo.GetByID(r.Context(), token.UserID)
			if err != nil {
				Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not found")
				return
			}

			if user.DeletedAt != nil {
				Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "user account is deactivated")
				return
			}

			// Update token last_used_at timestamp
			_ = authRepo.UpdateLastUsedAt(r.Context(), tokenHash, time.Now().UTC())

			// Inject user and token hash into context
			ctx := auth.WithUser(r.Context(), user)
			ctx = auth.WithTokenHash(ctx, tokenHash)

			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// UserIDFromContext retrieves the user ID from the context if present.
func UserIDFromContext(ctx context.Context) (string, bool) {
	if u, ok := auth.UserFromContext(ctx); ok && u != nil {
		return u.ID, true
	}
	return "", false
}

// RequireAdmin creates a Chi-compatible middleware that ensures the authenticated user is an administrator.
func RequireAdmin() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			user, ok := auth.UserFromContext(r.Context())
			if !ok || user == nil {
				Fail(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
				return
			}
			if !user.IsAdmin {
				Fail(w, http.StatusForbidden, "FORBIDDEN", "admin privileges required")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
