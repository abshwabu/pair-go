-- +goose Up
CREATE TABLE streaks (
    id TEXT PRIMARY KEY NOT NULL,
    pod_id TEXT UNIQUE NOT NULL REFERENCES pods(id) ON DELETE CASCADE,
    current_streak INTEGER NOT NULL DEFAULT 0,
    best_streak INTEGER NOT NULL DEFAULT 0,
    last_check_in_date TEXT,
    updated_at TEXT NOT NULL
);

-- +goose Down
DROP TABLE IF EXISTS streaks;
