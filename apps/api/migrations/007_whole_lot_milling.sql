-- The second, combined production-result note reports a completed lot's milling.
-- Keep 006 immutable: it has already been installed on the development database.
ALTER TABLE sobatnira.intake_records ADD CONSTRAINT intake_milling_weight_key
  UNIQUE (tenant_id, factory_id, id, lot_id, net_weight_kg, is_synthetic);
ALTER TABLE sobatnira.milling_records
  ADD CONSTRAINT milling_whole_lot_once_key UNIQUE (tenant_id, factory_id, lot_id),
  ADD CONSTRAINT milling_intake_weight_fk FOREIGN KEY
    (tenant_id, factory_id, intake_record_id, lot_id, cane_consumed_kg, is_synthetic)
    REFERENCES sobatnira.intake_records(tenant_id, factory_id, id, lot_id, net_weight_kg, is_synthetic),
  ADD COLUMN reported_batches jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(reported_batches) = 'array'),
  ADD COLUMN reported_batch_count integer GENERATED ALWAYS AS (jsonb_array_length(reported_batches)) STORED;
