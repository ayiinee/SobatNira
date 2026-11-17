-- Canonical sugar stock unit is kg; grams stay readable for old clients.
ALTER TABLE IF EXISTS sobatnira.sugar_stock_movements ADD COLUMN IF NOT EXISTS delta_kg numeric;
UPDATE sobatnira.sugar_stock_movements SET delta_kg = delta_grams / 1000.0 WHERE delta_kg IS NULL;
CREATE INDEX IF NOT EXISTS sugar_stock_kg_scope_idx ON sobatnira.sugar_stock_movements (tenant_id, factory_id, grade_id, occurred_at);

