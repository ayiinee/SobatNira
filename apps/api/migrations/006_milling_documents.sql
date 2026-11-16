CREATE TABLE sobatnira.milling_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  lot_id uuid NOT NULL,
  source text NOT NULL CHECK (source = 'synthetic'),
  source_request_id uuid NOT NULL,
  source_payload_hash text NOT NULL,
  source_payload jsonb NOT NULL,
  is_synthetic boolean NOT NULL DEFAULT true CHECK (is_synthetic),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'awaiting_validation', 'approved')),
  current_revision integer NOT NULL DEFAULT 1 CHECK (current_revision > 0),
  confirmed_revision integer,
  confirmed_by uuid,
  confirmed_at timestamptz,
  confirmation_source text CHECK (confirmation_source IS NULL OR confirmation_source = 'synthetic_admin'),
  approved_revision integer,
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (tenant_id, factory_id, id),
  UNIQUE (tenant_id, factory_id, source, source_request_id),
  FOREIGN KEY (tenant_id, factory_id, lot_id) REFERENCES sobatnira.lots(tenant_id, factory_id, id),
  CHECK (
    (status = 'draft' AND confirmed_revision IS NULL AND confirmed_by IS NULL AND confirmed_at IS NULL AND confirmation_source IS NULL
      AND approved_revision IS NULL AND approved_by IS NULL AND approved_at IS NULL)
    OR (status = 'awaiting_validation' AND confirmed_revision IS NOT NULL AND confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL AND confirmation_source IS NOT NULL
      AND approved_revision IS NULL AND approved_by IS NULL AND approved_at IS NULL)
    OR (status = 'approved' AND confirmed_revision IS NOT NULL AND confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL AND confirmation_source IS NOT NULL
      AND approved_revision IS NOT NULL AND approved_revision = current_revision AND approved_by IS NOT NULL AND approved_at IS NOT NULL)
  ),
  CHECK (confirmed_revision <= current_revision)
);

CREATE TABLE sobatnira.milling_document_revisions (
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  document_id uuid NOT NULL,
  revision integer NOT NULL CHECK (revision > 0),
  fields jsonb NOT NULL,
  origin text NOT NULL CHECK (origin IN ('synthetic_extraction', 'admin_correction')),
  actor_id uuid NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (tenant_id, factory_id, document_id, revision),
  FOREIGN KEY (tenant_id, factory_id, document_id) REFERENCES sobatnira.milling_documents(tenant_id, factory_id, id)
);
ALTER TABLE sobatnira.milling_documents
  ADD CONSTRAINT milling_current_revision_fk FOREIGN KEY (tenant_id, factory_id, id, current_revision)
    REFERENCES sobatnira.milling_document_revisions(tenant_id, factory_id, document_id, revision) DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT milling_confirmed_revision_fk FOREIGN KEY (tenant_id, factory_id, id, confirmed_revision)
    REFERENCES sobatnira.milling_document_revisions(tenant_id, factory_id, document_id, revision) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sobatnira.intake_records ADD CONSTRAINT intake_milling_source_key
  UNIQUE (tenant_id, factory_id, id, lot_id, is_synthetic);

CREATE TABLE sobatnira.milling_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  lot_id uuid NOT NULL,
  intake_record_id uuid NOT NULL,
  document_id uuid NOT NULL,
  document_revision integer NOT NULL,
  cane_consumed_kg numeric NOT NULL CHECK (cane_consumed_kg > 0 AND cane_consumed_kg NOT IN ('NaN'::numeric, 'Infinity'::numeric)),
  juice_produced_liters numeric NOT NULL CHECK (juice_produced_liters >= 0 AND juice_produced_liters NOT IN ('NaN'::numeric, 'Infinity'::numeric)),
  cane_stock_delta_kg numeric GENERATED ALWAYS AS (-cane_consumed_kg) STORED,
  occurred_at timestamptz NOT NULL,
  approved_by uuid NOT NULL,
  approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  is_synthetic boolean NOT NULL CHECK (is_synthetic),
  UNIQUE (tenant_id, factory_id, document_id),
  UNIQUE (tenant_id, factory_id, id, lot_id, cane_stock_delta_kg),
  UNIQUE (tenant_id, factory_id, id, lot_id, juice_produced_liters),
  FOREIGN KEY (tenant_id, factory_id, lot_id) REFERENCES sobatnira.lots(tenant_id, factory_id, id),
  FOREIGN KEY (tenant_id, factory_id, intake_record_id, lot_id, is_synthetic)
    REFERENCES sobatnira.intake_records(tenant_id, factory_id, id, lot_id, is_synthetic),
  FOREIGN KEY (tenant_id, factory_id, document_id, document_revision)
    REFERENCES sobatnira.milling_document_revisions(tenant_id, factory_id, document_id, revision)
);

ALTER TABLE sobatnira.sugarcane_stock_movements ALTER COLUMN intake_record_id DROP NOT NULL;
ALTER TABLE sobatnira.sugarcane_stock_movements ADD COLUMN milling_record_id uuid;
ALTER TABLE sobatnira.sugarcane_stock_movements DROP CONSTRAINT sugarcane_stock_movements_movement_type_check;
ALTER TABLE sobatnira.sugarcane_stock_movements DROP CONSTRAINT sugarcane_stock_movements_quantity_delta_kg_check;
ALTER TABLE sobatnira.sugarcane_stock_movements
  ADD CONSTRAINT sugarcane_movement_type_check CHECK (movement_type IN ('intake', 'milling')),
  ADD CONSTRAINT sugarcane_finite_quantity_check CHECK (quantity_delta_kg <> 0 AND quantity_delta_kg NOT IN ('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)),
  ADD CONSTRAINT sugarcane_source_direction_check CHECK (
    (movement_type = 'intake' AND intake_record_id IS NOT NULL AND milling_record_id IS NULL AND quantity_delta_kg > 0)
    OR (movement_type = 'milling' AND intake_record_id IS NULL AND milling_record_id IS NOT NULL AND quantity_delta_kg < 0)
  ),
  ADD CONSTRAINT sugarcane_milling_once_key UNIQUE (tenant_id, factory_id, milling_record_id),
  ADD CONSTRAINT sugarcane_milling_source_fk FOREIGN KEY (tenant_id, factory_id, milling_record_id, lot_id, quantity_delta_kg)
    REFERENCES sobatnira.milling_records(tenant_id, factory_id, id, lot_id, cane_stock_delta_kg) DEFERRABLE INITIALLY IMMEDIATE;

CREATE TABLE sobatnira.juice_stock_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  lot_id uuid NOT NULL,
  milling_record_id uuid NOT NULL,
  movement_type text NOT NULL CHECK (movement_type = 'milling'),
  quantity_delta_liters numeric NOT NULL CHECK (quantity_delta_liters >= 0 AND quantity_delta_liters NOT IN ('NaN'::numeric, 'Infinity'::numeric)),
  occurred_at timestamptz NOT NULL,
  is_synthetic boolean NOT NULL CHECK (is_synthetic),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (tenant_id, factory_id, milling_record_id),
  FOREIGN KEY (tenant_id, factory_id, milling_record_id, lot_id, quantity_delta_liters)
    REFERENCES sobatnira.milling_records(tenant_id, factory_id, id, lot_id, juice_produced_liters) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE TABLE sobatnira.milling_document_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  document_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('created', 'draft_updated', 'confirmed', 'approved')),
  actor_id uuid NOT NULL,
  before_data jsonb,
  after_data jsonb NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (tenant_id, factory_id, document_id) REFERENCES sobatnira.milling_documents(tenant_id, factory_id, id)
);

CREATE INDEX milling_documents_queue_idx ON sobatnira.milling_documents(tenant_id, factory_id, status, created_at DESC, id);
CREATE INDEX milling_records_lot_idx ON sobatnira.milling_records(tenant_id, factory_id, lot_id, occurred_at, id);
CREATE INDEX milling_events_idx ON sobatnira.milling_document_events(tenant_id, factory_id, document_id, occurred_at DESC, id);
CREATE INDEX juice_stock_lot_idx ON sobatnira.juice_stock_movements(tenant_id, factory_id, is_synthetic, lot_id);
ALTER TABLE sobatnira.milling_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.milling_document_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.milling_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.juice_stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.milling_document_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.milling_documents, sobatnira.milling_document_revisions, sobatnira.milling_records,
  sobatnira.juice_stock_movements, sobatnira.milling_document_events FROM PUBLIC, anon, authenticated;
