-- +goose Up
CREATE TABLE pod_members (
    id TEXT PRIMARY KEY NOT NULL,
    pod_id TEXT NOT NULL REFERENCES pods(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
    joined_at TEXT NOT NULL,
    left_at TEXT
);

CREATE INDEX idx_pod_members_user_id ON pod_members(user_id);
CREATE INDEX idx_pod_members_pod_id ON pod_members(pod_id);

-- +goose Down
DROP TABLE IF EXISTS pod_members;
