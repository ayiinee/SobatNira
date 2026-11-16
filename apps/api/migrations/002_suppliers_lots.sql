CREATE TABLE sobatnira.suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES sobatnira.tenants(id),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 200),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id)
);

-- Basic lot identity only. Stock, document approval and closing rules belong to
-- subsequent production modules. Display codes are not official identifiers.
CREATE TABLE sobatnira.lots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  supplier_id uuid NOT NULL,
  display_code text CHECK (display_code IS NULL OR length(btrim(display_code)) BETWEEN 1 AND 100),
  received_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (tenant_id, factory_id) REFERENCES sobatnira.factories(tenant_id, id),
  FOREIGN KEY (tenant_id, supplier_id) REFERENCES sobatnira.suppliers(tenant_id, id),
  UNIQUE (tenant_id, factory_id, id)
);

CREATE TABLE sobatnira.production_audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  entity_type text NOT NULL CHECK (entity_type IN ('supplier', 'lot')),
  entity_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('created', 'updated')),
  actor_id uuid NOT NULL,
  before_data jsonb,
  after_data jsonb NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (tenant_id, factory_id) REFERENCES sobatnira.factories(tenant_id, id)
);

CREATE INDEX suppliers_tenant_name_idx ON sobatnira.suppliers(tenant_id, name, id);
CREATE INDEX lots_factory_received_idx ON sobatnira.lots(tenant_id, factory_id, received_at DESC, id);
CREATE INDEX lots_supplier_idx ON sobatnira.lots(tenant_id, supplier_id);
CREATE INDEX production_audit_entity_idx ON sobatnira.production_audit_events
  (tenant_id, factory_id, entity_type, entity_id, occurred_at DESC, id);

ALTER TABLE sobatnira.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.production_audit_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.suppliers, sobatnira.lots, sobatnira.production_audit_events
  FROM PUBLIC, anon, authenticated;
