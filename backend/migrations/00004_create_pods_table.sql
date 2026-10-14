-- +goose Up
CREATE TABLE pods (
    id TEXT PRIMARY KEY NOT NULL,
    goal_category TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'active', 'completed', 'dissolved')),
    capacity INTEGER NOT NULL DEFAULT 2,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- +goose Down
DROP TABLE IF EXISTS pods;
