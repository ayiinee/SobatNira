CREATE TABLE sobatnira.owner_agent_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  user_id uuid NOT NULL,
  phone_digest text NOT NULL CHECK (phone_digest ~ '^[0-9a-f]{64}$'),
  code_digest text NOT NULL UNIQUE CHECK (code_digest ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  bound_at timestamptz,
  revoked_at timestamptz,
  FOREIGN KEY (tenant_id, factory_id) REFERENCES sobatnira.factories (tenant_id, id),
  FOREIGN KEY (user_id) REFERENCES auth.users (id)
);
CREATE INDEX owner_agent_sessions_phone_idx
  ON sobatnira.owner_agent_sessions (phone_digest, bound_at DESC, id) WHERE bound_at IS NOT NULL;
ALTER TABLE sobatnira.owner_agent_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.owner_agent_sessions FROM PUBLIC, anon, authenticated;
