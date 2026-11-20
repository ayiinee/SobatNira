CREATE INDEX production_snapshots_lot_latest_idx
  ON sobatnira.production_calculation_snapshots
    (tenant_id, factory_id, is_synthetic, lot_id, approved_at DESC, id DESC);
