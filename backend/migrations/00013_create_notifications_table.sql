-- +goose Up
CREATE TABLE notifications (
    id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    payload TEXT NOT NULL,
    sent_at TEXT,
    read_at TEXT,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_notifications_user_id_created_at ON notifications(user_id, created_at);

-- +goose Down
DROP TABLE IF EXISTS notifications;
