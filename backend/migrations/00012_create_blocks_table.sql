-- +goose Up
CREATE TABLE blocks (
    id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    UNIQUE(user_id, blocked_user_id)
);

-- +goose Down
DROP TABLE IF EXISTS blocks;
