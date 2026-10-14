-- +goose Up
CREATE TABLE auth_tokens (
    id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT UNIQUE NOT NULL,
    last_used_at TEXT,
    created_at TEXT NOT NULL
);

-- +goose Down
DROP TABLE IF EXISTS auth_tokens;
