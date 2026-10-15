package chat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/coder/websocket"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/auth"
	"github.com/abshwabu/pair/backend/internal/pods"
	"github.com/abshwabu/pair/backend/internal/storage"
)

// Notifier defines the interface for emitting notifications.
type Notifier interface {
	Send(ctx context.Context, userID, notificationType string, payload map[string]any) error
}

// PartnerResolver resolves the partner member ID for a user in a pod.
type PartnerResolver interface {
	GetPartnerID(ctx context.Context, podID, userID string) (string, error)
}

// Handler provides HTTP and WebSocket endpoints for chat.
type Handler struct {
	repo            *Repository
	hub             *Hub
	storageService  storage.StorageService
	notifier        Notifier
	partnerResolver PartnerResolver
}

// NewHandler creates a new chat Handler.
func NewHandler(repo *Repository, hub *Hub) *Handler {
	return &Handler{
		repo: repo,
		hub:  hub,
	}
}

// SetStorageService sets the storage service on the Handler.
func (h *Handler) SetStorageService(s storage.StorageService) {
	h.storageService = s
}

// SetNotifier sets the notification service and partner resolver on the Handler.
func (h *Handler) SetNotifier(n Notifier, pr PartnerResolver) {
	h.notifier = n
	h.partnerResolver = pr
}

// RegisterRoutes registers chat endpoints on a Chi router under /pods/{pod}.
func (h *Handler) RegisterRoutes(r chi.Router, authMW func(http.Handler) http.Handler) {
	r.Route("/pods/{pod}", func(r chi.Router) {
		r.Use(authMW)
		r.Use(pods.RequireMember())

		r.Get("/ws", h.ServeWS)
		r.Get("/messages", h.ListMessages)
		r.Post("/messages", h.SendMessage)
		r.Post("/typing", h.SendTyping)
		r.Post("/attachments", h.UploadAttachment)
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

// ServeWS handles GET /api/v1/pods/{pod}/ws.
// Upgrades HTTP connection to WebSocket, registers client with Hub, and runs read/write pumps.
func (h *Handler) ServeWS(w http.ResponseWriter, r *http.Request) {
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

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		InsecureSkipVerify: true,
	})
	if err != nil {
		return
	}

	client := NewClient(h.hub, conn, podID, user.ID)
	h.hub.Register(client)

	ctx := r.Context()
	go client.writePump(ctx, h.hub.pingInterval)
	client.readPump(ctx)
}

// ListMessages handles GET /api/v1/pods/{pod}/messages.
// Returns cursor-paginated messages oldest-to-newest within the page.
func (h *Handler) ListMessages(w http.ResponseWriter, r *http.Request) {
	podID := extractPodID(r)
	if podID == "" {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing pod id")
		return
	}

	var beforePtr *string
	if before := r.URL.Query().Get("before"); before != "" {
		beforePtr = &before
	}

	limit := 50
	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if l, err := strconv.Atoi(lStr); err == nil && l > 0 {
			limit = l
		}
	}

	messages, nextCursor, err := h.repo.ListMessages(r.Context(), podID, beforePtr, limit)
	if err != nil {
		if errors.Is(err, ErrMessageNotFound) {
			respondError(w, http.StatusNotFound, "NOT_FOUND", "cursor message not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list messages")
		return
	}

	respondJSON(w, http.StatusOK, messages, map[string]any{
		"next_cursor": nextCursor,
	})
}

// SendMessageRequest defines the input payload for POST /api/v1/pods/{pod}/messages.
type SendMessageRequest struct {
	Body          *string `json:"body"`
	AttachmentURL *string `json:"attachment_url"`
}

// SendMessage handles POST /api/v1/pods/{pod}/messages.
// Persists the message, broadcasts it to the pod over WebSocket, and returns the stored message.
func (h *Handler) SendMessage(w http.ResponseWriter, r *http.Request) {
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

	var req SendMessageRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	var bodyPtr *string
	if req.Body != nil {
		trimmed := strings.TrimSpace(*req.Body)
		if trimmed != "" {
			bodyPtr = &trimmed
		}
	}

	var attachPtr *string
	if req.AttachmentURL != nil {
		trimmed := strings.TrimSpace(*req.AttachmentURL)
		if trimmed != "" {
			attachPtr = &trimmed
		}
	}

	if bodyPtr == nil && attachPtr == nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "either body or attachment_url is required")
		return
	}

	if bodyPtr != nil && len(*bodyPtr) > 4000 {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "body exceeds 4000 characters")
		return
	}

	msg := &Message{
		ID:            uuid.NewString(),
		PodID:         podID,
		SenderID:      user.ID,
		Body:          bodyPtr,
		AttachmentURL: attachPtr,
		CreatedAt:     time.Now().UTC(),
	}

	if err := h.repo.Create(r.Context(), msg); err != nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to persist message")
		return
	}

	// Broadcast live message event to all connected sockets in the pod
	_ = h.hub.Broadcast(podID, Event{
		Type: "message",
		Data: msg,
	})

	// Notify the partner only if hub.IsViewing(podID, partnerID) is false
	if h.notifier != nil && h.partnerResolver != nil {
		partnerID, err := h.partnerResolver.GetPartnerID(r.Context(), podID, user.ID)
		if err == nil && partnerID != "" {
			if !h.hub.IsViewing(podID, partnerID) {
				bodyText := "Sent an attachment"
				if msg.Body != nil && *msg.Body != "" {
					bodyText = *msg.Body
				}
				title := "New message from " + user.Name
				payload := map[string]any{
					"type":   "new_message",
					"pod_id": podID,
					"title":  title,
					"body":   bodyText,
				}
				_ = h.notifier.Send(r.Context(), partnerID, "new_message", payload)
			}
		}
	}

	respondJSON(w, http.StatusCreated, msg, nil)
}


// SendTyping handles POST /api/v1/pods/{pod}/typing.
// Broadcasts a typing event to the pod excluding the sender without persisting to SQLite.
func (h *Handler) SendTyping(w http.ResponseWriter, r *http.Request) {
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

	// Broadcast typing event excluding sender
	_ = h.hub.BroadcastFilter(podID, Event{
		Type: "typing",
		Data: map[string]string{
			"user_id": user.ID,
		},
	}, user.ID)

	respondJSON(w, http.StatusOK, map[string]bool{"ok": true}, nil)
}

// UploadAttachment handles POST /api/v1/pods/{pod}/attachments.
// Multipart field "file", member-only, image types only (jpeg, png, webp, gif), max 5MB.
// S3 key: attachments/{pod_id}/{uuid}.{ext}
// Returns { "url": publicURL }.
func (h *Handler) UploadAttachment(w http.ResponseWriter, r *http.Request) {
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

	if h.storageService == nil {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "storage service unavailable")
		return
	}

	const maxFileSize = 5 * 1024 * 1024 // 5MB
	r.Body = http.MaxBytesReader(w, r.Body, maxFileSize+(1<<20))

	if err := r.ParseMultipartForm(maxFileSize + (1 << 20)); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) || strings.Contains(err.Error(), "request body too large") {
			respondError(w, http.StatusBadRequest, "FILE_TOO_LARGE", "file exceeds maximum allowed size of 5MB")
			return
		}
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", fmt.Sprintf("failed to parse multipart form: %v", err))
		return
	}

	file, fileHeader, err := r.FormFile("file")
	if err != nil {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "missing required file field 'file'")
		return
	}
	defer file.Close()

	if fileHeader.Size > maxFileSize {
		respondError(w, http.StatusBadRequest, "FILE_TOO_LARGE", "file exceeds maximum allowed size of 5MB")
		return
	}

	buf := make([]byte, 512)
	n, err := file.Read(buf)
	if err != nil && !errors.Is(err, io.EOF) {
		respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to read uploaded file")
		return
	}
	if n == 0 {
		respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", "file cannot be empty")
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
	case "image/gif":
		ext = "gif"
	default:
		respondError(w, http.StatusBadRequest, "INVALID_FILE_TYPE", "invalid file type: only image types are allowed")
		return
	}

	if seeker, ok := file.(io.Seeker); ok {
		if _, err := seeker.Seek(0, io.SeekStart); err != nil {
			respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to rewind file stream")
			return
		}
	}

	key := fmt.Sprintf("attachments/%s/%s.%s", podID, uuid.NewString(), ext)
	publicURL, err := h.storageService.Upload(r.Context(), key, file, contentType)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "STORAGE_ERROR", "failed to upload attachment")
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"url": publicURL}, nil)
}
