ALTER TABLE sobatnira.factories
  ADD COLUMN display_code text CHECK (length(btrim(display_code)) BETWEEN 1 AND 60),
  ADD COLUMN branch_name text CHECK (length(btrim(branch_name)) BETWEEN 1 AND 120),
  ADD COLUMN support_phone_e164 text CHECK (support_phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  ADD COLUMN profile_version integer NOT NULL DEFAULT 1 CHECK (profile_version > 0);

CREATE TABLE sobatnira.factory_admin_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  target_user_id uuid,
  action text NOT NULL CHECK (action IN ('profile_updated','admin_added','admin_activated','admin_deactivated')),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (tenant_id,factory_id) REFERENCES sobatnira.factories(tenant_id,id)
);

ALTER TABLE sobatnira.factory_admin_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.factory_admin_events FROM PUBLIC,anon,authenticated;
