-- +goose Up
CREATE TABLE goals (
    id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category TEXT NOT NULL CHECK (category IN ('read', 'watch', 'fitness', 'habit', 'custom')),
    title TEXT NOT NULL,
    target_description TEXT NOT NULL,
    pace TEXT NOT NULL CHECK (pace IN ('relaxed', 'steady', 'intense')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- +goose Down
DROP TABLE IF EXISTS goals;
