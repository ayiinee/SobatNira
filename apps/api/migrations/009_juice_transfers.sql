ALTER TABLE sobatnira.juice_reservations ADD COLUMN origin_lot_id uuid;
UPDATE sobatnira.juice_reservations SET origin_lot_id = lot_id;
ALTER TABLE sobatnira.juice_reservations ALTER COLUMN origin_lot_id SET NOT NULL,
  ADD FOREIGN KEY (tenant_id, factory_id, origin_lot_id) REFERENCES sobatnira.lots(tenant_id, factory_id, id);

CREATE TABLE sobatnira.juice_transfers (
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  request_id uuid NOT NULL,
  from_lot_id uuid NOT NULL,
  to_lot_id uuid NOT NULL,
  origin_lot_id uuid NOT NULL,
  quantity_ml numeric NOT NULL CHECK (quantity_ml > 0 AND quantity_ml < 'Infinity'::numeric),
  is_synthetic boolean NOT NULL,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (tenant_id, factory_id, request_id),
  CHECK (from_lot_id <> to_lot_id),
  FOREIGN KEY (tenant_id, factory_id, from_lot_id) REFERENCES sobatnira.lots(tenant_id, factory_id, id),
  FOREIGN KEY (tenant_id, factory_id, to_lot_id) REFERENCES sobatnira.lots(tenant_id, factory_id, id),
  FOREIGN KEY (tenant_id, factory_id, origin_lot_id) REFERENCES sobatnira.lots(tenant_id, factory_id, id)
);
CREATE INDEX juice_transfers_from_idx ON sobatnira.juice_transfers(tenant_id, factory_id, from_lot_id, is_synthetic);
CREATE INDEX juice_transfers_to_idx ON sobatnira.juice_transfers(tenant_id, factory_id, to_lot_id, is_synthetic);
ALTER TABLE sobatnira.juice_transfers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.juice_transfers FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE VIEW sobatnira.juice_balance_entries AS
SELECT tenant_id, factory_id, lot_id, is_synthetic, quantity_delta_liters * 1000 AS on_hand_ml,
  0::numeric AS reserved_ml, lot_id AS origin_lot_id FROM sobatnira.juice_stock_movements
UNION ALL
SELECT tenant_id, factory_id, lot_id, is_synthetic,
  CASE WHEN state = 'consumed' THEN -quantity_ml ELSE 0 END,
  CASE WHEN state = 'reserved' THEN quantity_ml ELSE 0 END, origin_lot_id FROM sobatnira.juice_reservations
UNION ALL
SELECT tenant_id, factory_id, from_lot_id, is_synthetic, -quantity_ml, 0::numeric, origin_lot_id FROM sobatnira.juice_transfers
UNION ALL
SELECT tenant_id, factory_id, to_lot_id, is_synthetic, quantity_ml, 0::numeric, origin_lot_id FROM sobatnira.juice_transfers;
