-- All application access goes through NestJS. Browser/API-key clients cannot
-- read or change memberships directly, including assigning their own role.
CREATE TABLE sobatnira.tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 200),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sobatnira.factories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES sobatnira.tenants(id),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 200),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id)
);

CREATE TABLE sobatnira.tenant_memberships (
  tenant_id uuid NOT NULL REFERENCES sobatnira.tenants(id),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, user_id)
);

CREATE TABLE sobatnira.factory_memberships (
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role text NOT NULL CHECK (role IN ('admin', 'owner')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, factory_id, user_id),
  FOREIGN KEY (tenant_id, factory_id) REFERENCES sobatnira.factories(tenant_id, id),
  FOREIGN KEY (tenant_id, user_id) REFERENCES sobatnira.tenant_memberships(tenant_id, user_id)
);

CREATE INDEX tenant_memberships_user_idx ON sobatnira.tenant_memberships(user_id, tenant_id);
CREATE INDEX factory_memberships_user_idx ON sobatnira.factory_memberships(user_id, tenant_id, factory_id);

ALTER TABLE sobatnira.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.factories ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.tenant_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.factory_memberships ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON SCHEMA sobatnira FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA sobatnira FROM PUBLIC, anon, authenticated;
