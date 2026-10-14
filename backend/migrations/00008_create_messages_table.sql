-- +goose Up
CREATE TABLE messages (
    id TEXT PRIMARY KEY NOT NULL,
    pod_id TEXT NOT NULL REFERENCES pods(id) ON DELETE CASCADE,
    sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT,
    attachment_url TEXT,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_messages_pod_id_created_at ON messages(pod_id, created_at);

-- +goose Down
DROP TABLE IF EXISTS messages;
