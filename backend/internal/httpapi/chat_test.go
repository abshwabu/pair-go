package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/abshwabu/pair/backend/internal/chat"
	"github.com/abshwabu/pair/backend/internal/config"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/httpapi"
)

func setupChatTestServer(t *testing.T) (*httptest.Server, *db.DB, *chat.Hub) {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "chat_http_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	cfg := &config.Config{
		Port:   "8080",
		DBPath: dbPath,
	}

	chatHub := chat.NewHub()
	router := httpapi.NewRouterWithWorker(cfg, database, nil, nil, chatHub)
	server := httptest.NewServer(router)

	t.Cleanup(func() {
		server.Close()
		_ = database.Close()
	})

	return server, database, chatHub
}

func TestChatAPI_NonMemberCannotOpenWebSocket(t *testing.T) {
	server, database, _ := setupChatTestServer(t)

	u1Token, u1ID := registerUser(t, server.Config.Handler, "Alice", "alice@example.com")
	_, u2ID := registerUser(t, server.Config.Handler, "Bob", "bob@example.com")
	u3Token, _ := registerUser(t, server.Config.Handler, "Charlie", "charlie@example.com")

	podID := createPodWithMembers(t, database, u1ID, u2ID)

	wsBaseURL := "ws" + strings.TrimPrefix(server.URL, "http")

	// Case 1: Non-member Charlie attempts to connect with Bearer header -> 403 Forbidden
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	wsURL := wsBaseURL + "/api/v1/pods/" + podID + "/ws"
	_, resp, err := websocket.Dial(ctx, wsURL, &websocket.DialOptions{
		HTTPHeader: http.Header{
			"Authorization": []string{"Bearer " + u3Token},
		},
	})
	if err == nil {
		t.Fatalf("expected error when non-member connects to websocket, but got nil")
	}
	if resp == nil || resp.StatusCode != http.StatusForbidden {
		status := 0
		if resp != nil {
			status = resp.StatusCode
		}
		t.Errorf("expected status 403 Forbidden before upgrade, got %d", status)
	}

	// Case 2: Non-member Charlie attempts to connect with ?token= query param -> 403 Forbidden
	ctx2, cancel2 := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel2()

	_, resp2, err2 := websocket.Dial(ctx2, wsURL+"?token="+u3Token, nil)
	if err2 == nil {
		t.Fatalf("expected error when non-member connects with query token, got nil")
	}
	if resp2 == nil || resp2.StatusCode != http.StatusForbidden {
		status := 0
		if resp2 != nil {
			status = resp2.StatusCode
		}
		t.Errorf("expected status 403 Forbidden with query token, got %d", status)
	}

	// Case 3: Unauthenticated request (no token) -> 401 Unauthorized
	ctx3, cancel3 := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel3()

	_, resp3, err3 := websocket.Dial(ctx3, wsURL, nil)
	if err3 == nil {
		t.Fatalf("expected error for unauthenticated websocket connection, got nil")
	}
	if resp3 == nil || resp3.StatusCode != http.StatusUnauthorized {
		status := 0
		if resp3 != nil {
			status = resp3.StatusCode
		}
		t.Errorf("expected status 401 Unauthorized, got %d", status)
	}

	// Case 4: Active member Alice CAN connect successfully
	ctx4, cancel4 := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel4()

	conn, resp4, err4 := websocket.Dial(ctx4, wsURL, &websocket.DialOptions{
		HTTPHeader: http.Header{
			"Authorization": []string{"Bearer " + u1Token},
		},
	})
	if err4 != nil {
		t.Fatalf("expected member Alice to connect, got error: %v", err4)
	}
	if resp4.StatusCode != http.StatusSwitchingProtocols {
		t.Errorf("expected 101 Switching Protocols, got %d", resp4.StatusCode)
	}
	_ = conn.Close(websocket.StatusNormalClosure, "done")
}

func TestChatAPI_MessageBroadcastToWebSocket(t *testing.T) {
	server, database, hub := setupChatTestServer(t)

	u1Token, u1ID := registerUser(t, server.Config.Handler, "Alice", "alice@example.com")
	u2Token, u2ID := registerUser(t, server.Config.Handler, "Bob", "bob@example.com")

	podID := createPodWithMembers(t, database, u1ID, u2ID)

	wsBaseURL := "ws" + strings.TrimPrefix(server.URL, "http")
	wsURL := wsBaseURL + "/api/v1/pods/" + podID + "/ws"

	// Bob connects to the pod's WebSocket using ?token= query parameter fallback
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	bobConn, _, err := websocket.Dial(ctx, wsURL+"?token="+u2Token, nil)
	if err != nil {
		t.Fatalf("failed to dial websocket for Bob: %v", err)
	}
	defer bobConn.Close(websocket.StatusNormalClosure, "test-close")

	// Wait briefly for registration and verify presence
	time.Sleep(50 * time.Millisecond)
	if !hub.IsViewing(podID, u2ID) {
		t.Errorf("expected Bob (u2) to be marked as viewing the pod")
	}

	// Alice POSTs a message via REST
	msgPayload := map[string]any{
		"body":           "Hello Bob, let's finish the book!",
		"attachment_url": "https://s3.example.com/attachments/note.png",
	}
	bodyBytes, _ := json.Marshal(msgPayload)
	postReq, _ := http.NewRequest(http.MethodPost, server.URL+"/api/v1/pods/"+podID+"/messages", bytes.NewReader(bodyBytes))
	postReq.Header.Set("Authorization", "Bearer "+u1Token)
	postReq.Header.Set("Content-Type", "application/json")

	postResp, err := http.DefaultClient.Do(postReq)
	if err != nil {
		t.Fatalf("failed to post message: %v", err)
	}
	defer postResp.Body.Close()

	if postResp.StatusCode != http.StatusCreated {
		t.Fatalf("expected 201 Created from POST /messages, got %d", postResp.StatusCode)
	}

	var createdResp httpapi.Response
	_ = json.NewDecoder(postResp.Body).Decode(&createdResp)
	createdData := createdResp.Data.(map[string]any)
	msgID := createdData["id"].(string)

	// Verify message was persisted in SQLite
	var dbBody, dbSender string
	err = database.Read.QueryRow("SELECT body, sender_id FROM messages WHERE id = ?;", msgID).Scan(&dbBody, &dbSender)
	if err != nil {
		t.Fatalf("message was not persisted in database: %v", err)
	}
	if dbBody != "Hello Bob, let's finish the book!" || dbSender != u1ID {
		t.Errorf("persisted message does not match posted data")
	}

	// Read from Bob's WebSocket socket to verify live delivery
	readCtx, readCancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer readCancel()

	// Bob might receive a presence event first when connecting, read until "message" event arrives
	var receivedEvent chat.Event
	for {
		_, msgData, readErr := bobConn.Read(readCtx)
		if readErr != nil {
			t.Fatalf("Bob failed to receive message event over websocket: %v", readErr)
		}
		var ev chat.Event
		if err := json.Unmarshal(msgData, &ev); err != nil {
			t.Fatalf("failed to parse websocket event JSON: %v", err)
		}
		if ev.Type == "message" {
			receivedEvent = ev
			break
		}
	}

	eventData := receivedEvent.Data.(map[string]any)
	if eventData["id"] != msgID {
		t.Errorf("expected received event message id %s, got %v", msgID, eventData["id"])
	}
	if eventData["body"] != "Hello Bob, let's finish the book!" {
		t.Errorf("expected received event body 'Hello Bob, let's finish the book!', got %v", eventData["body"])
	}
	if eventData["sender_id"] != u1ID {
		t.Errorf("expected received event sender_id %s, got %v", u1ID, eventData["sender_id"])
	}
}

func TestChatAPI_TypingEvent(t *testing.T) {
	server, database, _ := setupChatTestServer(t)

	u1Token, u1ID := registerUser(t, server.Config.Handler, "Alice", "alice@example.com")
	u2Token, u2ID := registerUser(t, server.Config.Handler, "Bob", "bob@example.com")

	podID := createPodWithMembers(t, database, u1ID, u2ID)

	wsBaseURL := "ws" + strings.TrimPrefix(server.URL, "http")
	wsURL := wsBaseURL + "/api/v1/pods/" + podID + "/ws"

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	bobConn, _, err := websocket.Dial(ctx, wsURL, &websocket.DialOptions{
		HTTPHeader: http.Header{
			"Authorization": []string{"Bearer " + u2Token},
		},
	})
	if err != nil {
		t.Fatalf("failed to connect Bob: %v", err)
	}
	defer bobConn.Close(websocket.StatusNormalClosure, "done")

	time.Sleep(50 * time.Millisecond)

	// Alice sends typing notification
	typingReq, _ := http.NewRequest(http.MethodPost, server.URL+"/api/v1/pods/"+podID+"/typing", nil)
	typingReq.Header.Set("Authorization", "Bearer "+u1Token)

	typingResp, err := http.DefaultClient.Do(typingReq)
	if err != nil {
		t.Fatalf("failed to send typing request: %v", err)
	}
	defer typingResp.Body.Close()

	if typingResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from POST /typing, got %d", typingResp.StatusCode)
	}

	// Bob should receive typing event
	readCtx, readCancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer readCancel()

	var receivedTyping chat.Event
	for {
		_, msgData, readErr := bobConn.Read(readCtx)
		if readErr != nil {
			t.Fatalf("failed to read typing event from socket: %v", readErr)
		}
		var ev chat.Event
		_ = json.Unmarshal(msgData, &ev)
		if ev.Type == "typing" {
			receivedTyping = ev
			break
		}
	}

	typingData := receivedTyping.Data.(map[string]any)
	if typingData["user_id"] != u1ID {
		t.Errorf("expected typing user_id %s, got %v", u1ID, typingData["user_id"])
	}

	// Verify that typing events are NOT persisted in the messages table
	var messageCount int
	_ = database.Read.QueryRow("SELECT COUNT(*) FROM messages WHERE pod_id = ?;", podID).Scan(&messageCount)
	if messageCount != 0 {
		t.Errorf("expected 0 messages in DB for typing event, got %d", messageCount)
	}
}

func TestChatAPI_HistoryPagination(t *testing.T) {
	server, database, _ := setupChatTestServer(t)

	u1Token, u1ID := registerUser(t, server.Config.Handler, "Alice", "alice@example.com")
	_, u2ID := registerUser(t, server.Config.Handler, "Bob", "bob@example.com")

	podID := createPodWithMembers(t, database, u1ID, u2ID)

	// Post 4 messages sequentially
	var postedIDs []string
	for i := 1; i <= 4; i++ {
		text := string(rune('A' - 1 + i))
		payload, _ := json.Marshal(map[string]any{"body": "Msg " + text})
		req, _ := http.NewRequest(http.MethodPost, server.URL+"/api/v1/pods/"+podID+"/messages", bytes.NewReader(payload))
		req.Header.Set("Authorization", "Bearer "+u1Token)
		req.Header.Set("Content-Type", "application/json")
		resp, err := http.DefaultClient.Do(req)
		if err != nil || resp.StatusCode != http.StatusCreated {
			t.Fatalf("failed to post message: %v", err)
		}
		var r httpapi.Response
		_ = json.NewDecoder(resp.Body).Decode(&r)
		_ = resp.Body.Close()
		postedIDs = append(postedIDs, r.Data.(map[string]any)["id"].(string))
		time.Sleep(10 * time.Millisecond)
	}

	// 1. Fetch newest page with limit 2: should return Msg C, Msg D (oldest to newest within page)
	req1, _ := http.NewRequest(http.MethodGet, server.URL+"/api/v1/pods/"+podID+"/messages?limit=2", nil)
	req1.Header.Set("Authorization", "Bearer "+u1Token)
	resp1, err := http.DefaultClient.Do(req1)
	if err != nil {
		t.Fatalf("failed to get messages page 1: %v", err)
	}
	defer resp1.Body.Close()

	var r1 httpapi.Response
	_ = json.NewDecoder(resp1.Body).Decode(&r1)
	page1 := r1.Data.([]any)
	if len(page1) != 2 {
		t.Fatalf("expected 2 messages in page 1, got %d", len(page1))
	}
	if page1[0].(map[string]any)["id"] != postedIDs[2] || page1[1].(map[string]any)["id"] != postedIDs[3] {
		t.Errorf("expected [Msg C, Msg D], got [%v, %v]", page1[0].(map[string]any)["body"], page1[1].(map[string]any)["body"])
	}
	meta1 := r1.Meta.(map[string]any)
	nextCursor, ok := meta1["next_cursor"].(string)
	if !ok || nextCursor != postedIDs[2] {
		t.Fatalf("expected next_cursor %s, got %v", postedIDs[2], meta1["next_cursor"])
	}

	// 2. Fetch older page with before=nextCursor: should return Msg A, Msg B
	req2, _ := http.NewRequest(http.MethodGet, server.URL+"/api/v1/pods/"+podID+"/messages?before="+nextCursor+"&limit=2", nil)
	req2.Header.Set("Authorization", "Bearer "+u1Token)
	resp2, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("failed to get messages page 2: %v", err)
	}
	defer resp2.Body.Close()

	var r2 httpapi.Response
	_ = json.NewDecoder(resp2.Body).Decode(&r2)
	page2 := r2.Data.([]any)
	if len(page2) != 2 {
		t.Fatalf("expected 2 messages in page 2, got %d", len(page2))
	}
	if page2[0].(map[string]any)["id"] != postedIDs[0] || page2[1].(map[string]any)["id"] != postedIDs[1] {
		t.Errorf("expected [Msg A, Msg B], got [%v, %v]", page2[0].(map[string]any)["body"], page2[1].(map[string]any)["body"])
	}
	meta2 := r2.Meta.(map[string]any)
	if meta2["next_cursor"] != nil {
		t.Errorf("expected next_cursor to be null when exhausted, got %v", meta2["next_cursor"])
	}
}

func TestChatAPI_Validation(t *testing.T) {
	server, database, _ := setupChatTestServer(t)

	u1Token, u1ID := registerUser(t, server.Config.Handler, "Alice", "alice@example.com")
	_, u2ID := registerUser(t, server.Config.Handler, "Bob", "bob@example.com")
	u3Token, _ := registerUser(t, server.Config.Handler, "Charlie", "charlie@example.com")

	podID := createPodWithMembers(t, database, u1ID, u2ID)

	// Case 1: Empty body and attachment -> 400 Bad Request
	emptyPayload, _ := json.Marshal(map[string]any{"body": "  ", "attachment_url": nil})
	req, _ := http.NewRequest(http.MethodPost, server.URL+"/api/v1/pods/"+podID+"/messages", bytes.NewReader(emptyPayload))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	resp, _ := http.DefaultClient.Do(req)
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400 Bad Request for empty message, got %d", resp.StatusCode)
	}
	_ = resp.Body.Close()

	// Case 2: Body > 4000 chars -> 400 Bad Request
	hugeBody := strings.Repeat("A", 4001)
	hugePayload, _ := json.Marshal(map[string]any{"body": hugeBody})
	req, _ = http.NewRequest(http.MethodPost, server.URL+"/api/v1/pods/"+podID+"/messages", bytes.NewReader(hugePayload))
	req.Header.Set("Authorization", "Bearer "+u1Token)
	req.Header.Set("Content-Type", "application/json")
	resp, _ = http.DefaultClient.Do(req)
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400 Bad Request for oversized body, got %d", resp.StatusCode)
	}
	_ = resp.Body.Close()

	// Case 3: Non-member (Charlie) cannot post message -> 403 Forbidden
	validPayload, _ := json.Marshal(map[string]any{"body": "Valid text"})
	req, _ = http.NewRequest(http.MethodPost, server.URL+"/api/v1/pods/"+podID+"/messages", bytes.NewReader(validPayload))
	req.Header.Set("Authorization", "Bearer "+u3Token)
	req.Header.Set("Content-Type", "application/json")
	resp, _ = http.DefaultClient.Do(req)
	if resp.StatusCode != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden for non-member, got %d", resp.StatusCode)
	}
	_ = resp.Body.Close()
}
