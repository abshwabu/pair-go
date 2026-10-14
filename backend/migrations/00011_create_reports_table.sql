-- +goose Up
CREATE TABLE reports (
    id TEXT PRIMARY KEY NOT NULL,
    reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pod_id TEXT REFERENCES pods(id) ON DELETE SET NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewed', 'dismissed')),
    created_at TEXT NOT NULL
);

-- +goose Down
DROP TABLE IF EXISTS reports;
