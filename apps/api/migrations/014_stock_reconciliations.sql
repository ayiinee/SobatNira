-- The initial credit remains immutable. Corrections update the effective receipt
-- weight and append a delta while the FK continues to verify the initial credit.
ALTER TABLE sobatnira.intake_records
  ADD COLUMN posted_net_weight_kg numeric CHECK (posted_net_weight_kg > 0 AND posted_net_weight_kg < 'Infinity'::numeric),
  ADD COLUMN initial_net_weight_kg numeric GENERATED ALWAYS AS (COALESCE(posted_net_weight_kg, net_weight_kg)) STORED,
  ADD CONSTRAINT intake_initial_credit_key UNIQUE (tenant_id, factory_id, id, lot_id, initial_net_weight_kg, is_synthetic),
  ADD CONSTRAINT intake_reconciliation_lot_key UNIQUE (tenant_id, factory_id, id, lot_id);

ALTER TABLE sobatnira.sugarcane_stock_movements
  DROP CONSTRAINT sugarcane_stock_matches_intake_fk,
  DROP CONSTRAINT sugarcane_stock_intake_source_type_fk,
  ADD CONSTRAINT sugarcane_stock_matches_intake_fk FOREIGN KEY
    (tenant_id, factory_id, intake_record_id, lot_id, quantity_delta_kg, is_synthetic)
    REFERENCES sobatnira.intake_records(tenant_id, factory_id, id, lot_id, initial_net_weight_kg, is_synthetic)
    DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE sobatnira.intake_records
  DROP CONSTRAINT intake_stock_reference_key,
  DROP CONSTRAINT intake_stock_source_type_key;

ALTER TABLE sobatnira.milling_records
  ADD CONSTRAINT milling_reconciliation_lot_key UNIQUE (tenant_id, factory_id, id, lot_id);

CREATE TABLE sobatnira.stock_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  lot_id uuid NOT NULL,
  material text NOT NULL CHECK (material IN ('sugarcane', 'juice')),
  intake_record_id uuid,
  milling_record_id uuid,
  document_id uuid NOT NULL,
  previous_revision_id uuid NOT NULL,
  revision_id uuid NOT NULL UNIQUE CHECK (revision_id <> previous_revision_id),
  revision_version integer NOT NULL CHECK (revision_version > 1),
  quantity_before numeric NOT NULL CHECK (quantity_before >= 0 AND quantity_before < 'Infinity'::numeric),
  quantity_after numeric NOT NULL CHECK (quantity_after >= 0 AND quantity_after < 'Infinity'::numeric),
  quantity_delta numeric GENERATED ALWAYS AS (quantity_after - quantity_before) STORED,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 500),
  actor_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (quantity_before <> quantity_after),
  CHECK (
    (material = 'sugarcane' AND intake_record_id IS NOT NULL AND milling_record_id IS NULL
      AND quantity_before > 0 AND quantity_after > 0)
    OR (material = 'juice' AND milling_record_id IS NOT NULL AND intake_record_id IS NULL)
  ),
  FOREIGN KEY (tenant_id, factory_id, intake_record_id, lot_id) REFERENCES sobatnira.intake_records(tenant_id, factory_id, id, lot_id),
  FOREIGN KEY (tenant_id, factory_id, milling_record_id, lot_id) REFERENCES sobatnira.milling_records(tenant_id, factory_id, id, lot_id)
);
CREATE INDEX stock_reconciliations_lot_idx ON sobatnira.stock_reconciliations(tenant_id, factory_id, lot_id, material, revision_version DESC);
CREATE INDEX stock_reconciliations_document_idx ON sobatnira.stock_reconciliations(factory_id, document_id, revision_version);
CREATE INDEX stock_reconciliations_intake_idx ON sobatnira.stock_reconciliations(intake_record_id, revision_version DESC)
  WHERE intake_record_id IS NOT NULL;
CREATE INDEX stock_reconciliations_milling_idx ON sobatnira.stock_reconciliations(milling_record_id, revision_version DESC)
  WHERE milling_record_id IS NOT NULL;
ALTER TABLE sobatnira.stock_reconciliations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.stock_reconciliations FROM PUBLIC, anon, authenticated;

CREATE VIEW sobatnira.cane_stock_entries AS
SELECT tenant_id, factory_id, lot_id, is_synthetic, quantity_delta_kg FROM sobatnira.sugarcane_stock_movements
UNION ALL
SELECT tenant_id, factory_id, lot_id, false, quantity_delta FROM sobatnira.stock_reconciliations WHERE material = 'sugarcane';

CREATE VIEW sobatnira.juice_produced_entries AS
SELECT tenant_id, factory_id, lot_id, is_synthetic, quantity_delta_liters FROM sobatnira.juice_stock_movements
UNION ALL
SELECT tenant_id, factory_id, lot_id, false, quantity_delta FROM sobatnira.stock_reconciliations WHERE material = 'juice';
REVOKE ALL ON sobatnira.cane_stock_entries, sobatnira.juice_produced_entries FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE VIEW sobatnira.juice_balance_entries AS
SELECT tenant_id, factory_id, lot_id, is_synthetic, quantity_delta_liters * 1000 AS on_hand_ml,
  0::numeric AS reserved_ml, lot_id AS origin_lot_id FROM sobatnira.juice_produced_entries
UNION ALL
SELECT tenant_id, factory_id, lot_id, is_synthetic,
  CASE WHEN state = 'consumed' THEN -quantity_ml ELSE 0 END,
  CASE WHEN state = 'reserved' THEN quantity_ml ELSE 0 END, origin_lot_id FROM sobatnira.juice_reservations
UNION ALL
SELECT tenant_id, factory_id, from_lot_id, is_synthetic, -quantity_ml, 0::numeric, origin_lot_id FROM sobatnira.juice_transfers
UNION ALL
SELECT tenant_id, factory_id, to_lot_id, is_synthetic, quantity_ml, 0::numeric, origin_lot_id FROM sobatnira.juice_transfers;
