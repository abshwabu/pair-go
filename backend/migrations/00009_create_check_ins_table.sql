-- +goose Up
CREATE TABLE check_ins (
    id TEXT PRIMARY KEY NOT NULL,
    pod_id TEXT NOT NULL REFERENCES pods(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    check_in_date TEXT NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL,
    UNIQUE(pod_id, user_id, check_in_date)
);

CREATE INDEX idx_check_ins_pod_id_check_in_date ON check_ins(pod_id, check_in_date);

-- +goose Down
DROP TABLE IF EXISTS check_ins;
