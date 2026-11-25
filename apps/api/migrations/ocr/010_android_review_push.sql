CREATE TABLE review_push_installations (
  installation_id text PRIMARY KEY CHECK (installation_id ~ '^[A-Za-z0-9_-]{22}$'),
  user_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  registration_id uuid NOT NULL,
  refreshed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX review_push_installations_scope ON review_push_installations (factory_id, user_id, refreshed_at);

CREATE TABLE review_push_deliveries (
  installation_id text NOT NULL REFERENCES review_push_installations ON DELETE CASCADE,
  user_id uuid NOT NULL,
  task_id uuid NOT NULL,
  registration_id uuid NOT NULL,
  attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  status text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','SENDING','SENT','FAILED','SKIPPED')),
  available_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '15 minutes',
  claim_id uuid,
  PRIMARY KEY (installation_id, user_id, task_id),
  FOREIGN KEY (user_id, task_id) REFERENCES admin_review_notifications ON DELETE CASCADE
);

CREATE INDEX review_push_deliveries_ready ON review_push_deliveries (available_at)
  WHERE status IN ('QUEUED','SENDING');

ALTER TABLE review_push_installations ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_push_deliveries ENABLE ROW LEVEL SECURITY;
