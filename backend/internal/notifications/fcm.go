package notifications

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

// ErrUnregisteredToken indicates that the FCM device registration token is no longer valid.
var ErrUnregisteredToken = errors.New("fcm: registration token is unregistered")

// IsUnregisteredToken reports whether the given error indicates an invalid/unregistered token.
func IsUnregisteredToken(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, ErrUnregisteredToken) {
		return true
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "unregistered") ||
		strings.Contains(msg, "registration-token-not-registered") ||
		strings.Contains(msg, "not_found")
}

// PushPayload contains data required to deliver a push notification to FCM.
type PushPayload struct {
	Token string            `json:"token"`
	Title string            `json:"title"`
	Body  string            `json:"body"`
	Data  map[string]string `json:"data,omitempty"`
}

// FCMClient defines the interface for delivering push notifications to devices.
type FCMClient interface {
	SendPush(ctx context.Context, push PushPayload) error
}

// GoogleFCMClient sends push notifications via the FCM HTTP v1 API using OAuth2 credentials.
type GoogleFCMClient struct {
	projectID   string
	tokenSource oauth2.TokenSource
	httpClient  *http.Client
}

// NewGoogleFCMClient creates a new GoogleFCMClient from a service account JSON file.
func NewGoogleFCMClient(ctx context.Context, projectID, credentialsPath string) (*GoogleFCMClient, error) {
	if projectID == "" {
		return nil, errors.New("fcm project id is required")
	}
	if credentialsPath == "" {
		return nil, errors.New("fcm credentials path is required")
	}

	data, err := os.ReadFile(credentialsPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read credentials file %s: %w", credentialsPath, err)
	}

	creds, err := google.CredentialsFromJSON(ctx, data, "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return nil, fmt.Errorf("failed to parse google credentials: %w", err)
	}

	return &GoogleFCMClient{
		projectID:   projectID,
		tokenSource: creds.TokenSource,
		httpClient:  &http.Client{Timeout: 10 * time.Second},
	}, nil
}

// SendPush sends a message to the FCM HTTP v1 API.
func (c *GoogleFCMClient) SendPush(ctx context.Context, push PushPayload) error {
	token, err := c.tokenSource.Token()
	if err != nil {
		return fmt.Errorf("failed to acquire oauth2 token: %w", err)
	}

	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", c.projectID)

	message := map[string]any{
		"token": push.Token,
		"notification": map[string]string{
			"title": push.Title,
			"body":  push.Body,
		},
		"data": push.Data,
	}

	reqBody := map[string]any{
		"message": message,
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("failed to marshal push request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return fmt.Errorf("failed to create http request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+token.AccessToken)
	req.Header.Set("Content-Type", "application/json; UTF-8")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("fcm http request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return nil
	}

	respBytes, _ := io.ReadAll(resp.Body)
	respStr := string(respBytes)

	if resp.StatusCode == http.StatusNotFound || strings.Contains(respStr, "UNREGISTERED") || strings.Contains(respStr, "NOT_FOUND") {
		return fmt.Errorf("%w: status %d body %s", ErrUnregisteredToken, resp.StatusCode, respStr)
	}

	return fmt.Errorf("fcm api error (status %d): %s", resp.StatusCode, respStr)
}

// FakeFCMClient is an in-memory test double for FCMClient.
type FakeFCMClient struct {
	mu            sync.Mutex
	sentPushes    []PushPayload
	unregistered  map[string]bool
	failWithError error
}

// NewFakeFCMClient creates a new FakeFCMClient.
func NewFakeFCMClient() *FakeFCMClient {
	return &FakeFCMClient{
		sentPushes:   make([]PushPayload, 0),
		unregistered: make(map[string]bool),
	}
}

// SetUnregistered configures the fake to return ErrUnregisteredToken for the given device token.
func (f *FakeFCMClient) SetUnregistered(token string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.unregistered[token] = true
}

// SetFailWithError configures the fake to return a specific error on subsequent calls.
func (f *FakeFCMClient) SetFailWithError(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.failWithError = err
}

// GetSentPushes returns a copy of all push payloads received by the fake.
func (f *FakeFCMClient) GetSentPushes() []PushPayload {
	f.mu.Lock()
	defer f.mu.Unlock()
	cp := make([]PushPayload, len(f.sentPushes))
	copy(cp, f.sentPushes)
	return cp
}

// SendPush records the push or returns a configured error.
func (f *FakeFCMClient) SendPush(ctx context.Context, push PushPayload) error {
	f.mu.Lock()
	defer f.mu.Unlock()

	if f.failWithError != nil {
		return f.failWithError
	}
	if f.unregistered[push.Token] {
		return ErrUnregisteredToken
	}

	f.sentPushes = append(f.sentPushes, push)
	return nil
}

// NoopFCMClient is a no-op implementation of FCMClient used when FCM credentials are not provided.
type NoopFCMClient struct{}

// NewNoopFCMClient creates a new NoopFCMClient.
func NewNoopFCMClient() *NoopFCMClient {
	return &NoopFCMClient{}
}

// SendPush logs and returns nil.
func (n *NoopFCMClient) SendPush(ctx context.Context, push PushPayload) error {
	slog.Debug("NoopFCMClient: push skipped (FCM not configured)", "token", push.Token, "title", push.Title)
	return nil
}
