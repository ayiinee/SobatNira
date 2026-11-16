CREATE TABLE sobatnira.juice_reservations (
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  lot_id uuid NOT NULL,
  request_id uuid NOT NULL,
  batch_id uuid NOT NULL,
  quantity_ml numeric NOT NULL CHECK (quantity_ml > 0 AND quantity_ml < 'Infinity'::numeric),
  is_synthetic boolean NOT NULL,
  state text NOT NULL DEFAULT 'reserved' CHECK (state IN ('reserved', 'consumed', 'released')),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finalized_by uuid,
  finalized_at timestamptz,
  PRIMARY KEY (tenant_id, factory_id, request_id),
  FOREIGN KEY (tenant_id, factory_id, lot_id) REFERENCES sobatnira.lots(tenant_id, factory_id, id),
  CHECK ((finalized_by IS NULL) = (state = 'reserved') AND (finalized_at IS NULL) = (state = 'reserved'))
);
CREATE INDEX juice_reservations_lot_idx ON sobatnira.juice_reservations(tenant_id, factory_id, lot_id, is_synthetic);
ALTER TABLE sobatnira.juice_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.juice_reservations FROM PUBLIC, anon, authenticated;

CREATE VIEW sobatnira.juice_balance_entries AS
SELECT tenant_id, factory_id, lot_id, is_synthetic, quantity_delta_liters * 1000 AS on_hand_ml, 0::numeric AS reserved_ml
  FROM sobatnira.juice_stock_movements
UNION ALL
SELECT tenant_id, factory_id, lot_id, is_synthetic,
  CASE WHEN state = 'consumed' THEN -quantity_ml ELSE 0 END,
  CASE WHEN state = 'reserved' THEN quantity_ml ELSE 0 END
  FROM sobatnira.juice_reservations;
REVOKE ALL ON sobatnira.juice_balance_entries FROM PUBLIC, anon, authenticated;
