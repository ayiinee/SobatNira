CREATE TABLE sobatnira.lot_closures (
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  lot_id uuid NOT NULL,
  is_synthetic boolean NOT NULL,
  closed_by uuid NOT NULL,
  closed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (tenant_id, factory_id, lot_id, is_synthetic),
  FOREIGN KEY (tenant_id, factory_id, lot_id) REFERENCES sobatnira.lots(tenant_id, factory_id, id)
);
ALTER TABLE sobatnira.lot_closures ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.lot_closures FROM PUBLIC, anon, authenticated;
