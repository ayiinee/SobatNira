CREATE TABLE sobatnira.cane_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES sobatnira.tenants(id),
  code text NOT NULL CHECK (code COLLATE "C" ~ '^[A-Z0-9_-]{1,40}$'),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 200),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);

ALTER TABLE sobatnira.cane_types ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.cane_types FROM PUBLIC, anon, authenticated;

ALTER TABLE sobatnira.production_audit_events
  DROP CONSTRAINT production_audit_events_entity_type_check,
  ADD CONSTRAINT production_audit_events_entity_type_check CHECK (entity_type IN ('supplier', 'lot', 'cane_type'));
