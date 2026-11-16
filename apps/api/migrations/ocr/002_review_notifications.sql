CREATE TABLE admin_review_notifications (
  task_id uuid NOT NULL REFERENCES admin_review_tasks,
  user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  PRIMARY KEY (user_id, task_id)
);

CREATE INDEX admin_review_notifications_unread ON admin_review_notifications (user_id, task_id)
  WHERE read_at IS NULL;

ALTER TABLE admin_review_notifications ENABLE ROW LEVEL SECURITY;
