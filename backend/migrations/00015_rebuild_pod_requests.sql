-- +goose NO TRANSACTION
-- +goose Up
PRAGMA foreign_keys = OFF;

CREATE TABLE pod_requests_new (
    id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'proposed', 'matched', 'cancelled')),
    timezone_tolerance_hours INTEGER NOT NULL,
    language TEXT NOT NULL,
    pod_id TEXT REFERENCES pods(id) ON DELETE SET NULL,
    proposal_id TEXT REFERENCES match_proposals(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

INSERT INTO pod_requests_new (
    id, user_id, goal_id, status, timezone_tolerance_hours, language, pod_id, proposal_id, created_at, updated_at
)
SELECT id, user_id, goal_id, status, timezone_tolerance_hours, language, pod_id, NULL, created_at, updated_at
FROM pod_requests;

DROP TABLE pod_requests;

ALTER TABLE pod_requests_new RENAME TO pod_requests;

CREATE INDEX idx_pod_requests_status ON pod_requests(status);
CREATE INDEX idx_pod_requests_proposal_id ON pod_requests(proposal_id);

PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;

-- +goose Down
PRAGMA foreign_keys = OFF;

CREATE TABLE pod_requests_old (
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

INSERT INTO pod_requests_old (
    id, user_id, goal_id, status, timezone_tolerance_hours, language, pod_id, created_at, updated_at
)
SELECT id, user_id, goal_id,
       CASE WHEN status = 'proposed' THEN 'open' ELSE status END,
       timezone_tolerance_hours, language, pod_id, created_at, updated_at
FROM pod_requests;

DROP TABLE pod_requests;

ALTER TABLE pod_requests_old RENAME TO pod_requests;

CREATE INDEX idx_pod_requests_status ON pod_requests(status);

PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;
