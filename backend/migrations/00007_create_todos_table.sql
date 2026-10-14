-- +goose Up
CREATE TABLE todos (
    id TEXT PRIMARY KEY NOT NULL,
    pod_id TEXT NOT NULL REFERENCES pods(id) ON DELETE CASCADE,
    created_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assigned_to TEXT REFERENCES users(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    notes TEXT,
    due_date TEXT,
    is_done INTEGER NOT NULL DEFAULT 0 CHECK (is_done IN (0, 1)),
    completed_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_todos_pod_id ON todos(pod_id);

-- +goose Down
DROP TABLE IF EXISTS todos;
