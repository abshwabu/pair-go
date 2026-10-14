package chat

import (
	"encoding/json"
	"fmt"
	"sync"
	"time"
)

// Event represents a WebSocket event sent to clients.
type Event struct {
	Type string `json:"type"`
	Data any    `json:"data"`
}

// HubOption allows configuring Hub properties.
type HubOption func(*Hub)

// WithPingInterval overrides the default WebSocket ping interval.
func WithPingInterval(d time.Duration) HubOption {
	return func(h *Hub) {
		if d > 0 {
			h.pingInterval = d
		}
	}
}

// Hub is an in-memory registry mapping pod IDs to connected WebSocket clients.
// Safe for concurrent use.
type Hub struct {
	mu           sync.RWMutex
	clients      map[string]map[*Client]bool
	presence     map[string]map[string]int
	pingInterval time.Duration
}

// NewHub creates a new in-memory WebSocket Hub.
func NewHub(opts ...HubOption) *Hub {
	h := &Hub{
		clients:      make(map[string]map[*Client]bool),
		presence:     make(map[string]map[string]int),
		pingInterval: 30 * time.Second,
	}
	for _, opt := range opts {
		opt(h)
	}
	return h
}

// Register adds a client to the pod's connected set and tracks presence.
func (h *Hub) Register(c *Client) {
	h.mu.Lock()
	podClients, ok := h.clients[c.podID]
	if !ok {
		podClients = make(map[*Client]bool)
		h.clients[c.podID] = podClients
	}
	podClients[c] = true

	podUsers, ok := h.presence[c.podID]
	if !ok {
		podUsers = make(map[string]int)
		h.presence[c.podID] = podUsers
	}
	wasOnline := podUsers[c.userID] > 0
	podUsers[c.userID]++
	h.mu.Unlock()

	// If this user was not previously connected to this pod, broadcast presence
	if !wasOnline {
		_ = h.Broadcast(c.podID, Event{
			Type: "presence",
			Data: map[string]any{
				"user_id": c.userID,
				"status":  "online",
			},
		})
	}
}

// Unregister removes a client and tracks presence drop.
func (h *Hub) Unregister(c *Client) {
	h.mu.Lock()
	isNowOffline := false
	if podClients, ok := h.clients[c.podID]; ok {
		if podClients[c] {
			delete(podClients, c)
			if len(podClients) == 0 {
				delete(h.clients, c.podID)
			}

			if podUsers, ok := h.presence[c.podID]; ok {
				podUsers[c.userID]--
				if podUsers[c.userID] <= 0 {
					delete(podUsers, c.userID)
					if len(podUsers) == 0 {
						delete(h.presence, c.podID)
					}
					isNowOffline = true
				}
			}
		}
	}
	h.mu.Unlock()

	c.Close()

	if isNowOffline {
		_ = h.Broadcast(c.podID, Event{
			Type: "presence",
			Data: map[string]any{
				"user_id": c.userID,
				"status":  "offline",
			},
		})
	}
}

// Broadcast sends an event to every client connected to the given pod.
func (h *Hub) Broadcast(podID string, event any) error {
	return h.BroadcastFilter(podID, event, "")
}

// BroadcastFilter sends an event to clients in the given pod, excluding excludeUserID if non-empty.
func (h *Hub) BroadcastFilter(podID string, event any, excludeUserID string) error {
	msgBytes, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	h.mu.RLock()
	var targets []*Client
	if podClients, ok := h.clients[podID]; ok {
		targets = make([]*Client, 0, len(podClients))
		for c := range podClients {
			if excludeUserID != "" && c.userID == excludeUserID {
				continue
			}
			targets = append(targets, c)
		}
	}
	h.mu.RUnlock()

	var toDrop []*Client
	for _, c := range targets {
		select {
		case c.send <- msgBytes:
		default:
			// Buffer full: drop slow/unresponsive client
			toDrop = append(toDrop, c)
		}
	}

	for _, c := range toDrop {
		h.Unregister(c)
	}

	return nil
}

// IsViewing reports whether the given user is currently connected to the pod.
func (h *Hub) IsViewing(podID, userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()

	podUsers, ok := h.presence[podID]
	if !ok {
		return false
	}
	return podUsers[userID] > 0
}

// ConnectedClients returns the number of connected clients in a pod.
func (h *Hub) ConnectedClients(podID string) int {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if podClients, ok := h.clients[podID]; ok {
		return len(podClients)
	}
	return 0
}
