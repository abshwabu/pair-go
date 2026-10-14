-- +goose Up
CREATE TABLE pod_requests (
    id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'matched', 'cancelled')),
    timezone_tolerance_hours INTEGER NOT NULL,
    language TEXT NOT NULL,
    pod_id TEXT REFERENCES pods(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_pod_requests_status ON pod_requests(status);

-- +goose Down
DROP TABLE IF EXISTS pod_requests;
