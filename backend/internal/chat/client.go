package chat

import (
	"context"
	"sync"
	"time"

	"github.com/coder/websocket"
)

const (
	defaultSendBufferSize = 64
	writeTimeout          = 10 * time.Second
	pingTimeout           = 10 * time.Second
)

// Client represents a connected WebSocket user session for a pod.
type Client struct {
	hub       *Hub
	conn      *websocket.Conn
	podID     string
	userID    string
	send      chan []byte
	closeOnce sync.Once
}

// NewClient creates a new WebSocket Client.
func NewClient(hub *Hub, conn *websocket.Conn, podID, userID string) *Client {
	return &Client{
		hub:    hub,
		conn:   conn,
		podID:  podID,
		userID: userID,
		send:   make(chan []byte, defaultSendBufferSize),
	}
}

// Close gracefully closes the send channel and websocket connection once.
func (c *Client) Close() {
	c.closeOnce.Do(func() {
		close(c.send)
		if c.conn != nil {
			_ = c.conn.Close(websocket.StatusNormalClosure, "closed")
		}
	})
}

// writePump handles sending queued messages and periodic pings to the websocket.
func (c *Client) writePump(ctx context.Context, pingInterval time.Duration) {
	if pingInterval <= 0 {
		pingInterval = 30 * time.Second
	}
	ticker := time.NewTicker(pingInterval)
	defer func() {
		ticker.Stop()
		c.hub.Unregister(c)
	}()

	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-c.send:
			if !ok {
				_ = c.conn.Close(websocket.StatusNormalClosure, "closed")
				return
			}
			writeCtx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.conn.Write(writeCtx, websocket.MessageText, msg)
			cancel()
			if err != nil {
				return
			}
		case <-ticker.C:
			pingCtx, cancel := context.WithTimeout(ctx, pingTimeout)
			err := c.conn.Ping(pingCtx)
			cancel()
			if err != nil {
				// Missed pong or connection closed
				return
			}
		}
	}
}

// readPump reads incoming websocket messages until connection failure or closure.
func (c *Client) readPump(ctx context.Context) {
	defer c.hub.Unregister(c)

	for {
		_, _, err := c.conn.Read(ctx)
		if err != nil {
			break
		}
	}
}
