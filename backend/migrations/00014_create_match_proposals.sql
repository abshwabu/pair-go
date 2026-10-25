-- +goose Up
CREATE TABLE match_proposals (
    id TEXT PRIMARY KEY NOT NULL,
    request_a_id TEXT NOT NULL REFERENCES pod_requests(id) ON DELETE CASCADE,
    request_b_id TEXT NOT NULL REFERENCES pod_requests(id) ON DELETE CASCADE,
    user_a_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_a_response TEXT NOT NULL CHECK (user_a_response IN ('pending', 'accepted', 'rejected')) DEFAULT 'pending',
    user_b_response TEXT NOT NULL CHECK (user_b_response IN ('pending', 'accepted', 'rejected')) DEFAULT 'pending',
    status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'rejected', 'expired', 'cancelled')) DEFAULT 'pending',
    pod_id TEXT REFERENCES pods(id) ON DELETE SET NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_match_proposals_user_a_id ON match_proposals(user_a_id);
CREATE INDEX idx_match_proposals_user_b_id ON match_proposals(user_b_id);
CREATE INDEX idx_match_proposals_status_expires_at ON match_proposals(status, expires_at);

-- +goose Down
DROP TABLE IF EXISTS match_proposals;
