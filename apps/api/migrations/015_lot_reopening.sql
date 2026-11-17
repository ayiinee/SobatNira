ALTER TABLE sobatnira.lot_closures
  ADD COLUMN id uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN reopened_at timestamptz,
  ADD COLUMN reopened_by uuid,
  ADD COLUMN reopen_reason text,
  DROP CONSTRAINT lot_closures_pkey,
  ADD PRIMARY KEY (id),
  ADD CONSTRAINT lot_closures_reopening_fields CHECK (
    (reopened_at IS NULL AND reopened_by IS NULL AND reopen_reason IS NULL)
    OR (reopened_at IS NOT NULL AND reopened_by IS NOT NULL AND reopen_reason IS NOT NULL
      AND length(btrim(reopen_reason)) BETWEEN 1 AND 500)
  );

CREATE UNIQUE INDEX lot_closures_active_idx
  ON sobatnira.lot_closures (tenant_id, factory_id, lot_id, is_synthetic)
  WHERE reopened_at IS NULL;

CREATE INDEX lot_closures_history_idx
  ON sobatnira.lot_closures (tenant_id, factory_id, lot_id, is_synthetic, closed_at DESC, id);
