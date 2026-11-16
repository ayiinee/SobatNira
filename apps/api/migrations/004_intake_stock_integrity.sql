-- Keep the source lot/supplier and exact incoming quantity consistent even if
-- another backend module later writes to these tables.
ALTER TABLE sobatnira.lots ADD CONSTRAINT lots_intake_supplier_key
  UNIQUE (tenant_id, factory_id, id, supplier_id);

ALTER TABLE sobatnira.intake_records ADD CONSTRAINT intake_supplier_matches_lot_fk
  FOREIGN KEY (tenant_id, factory_id, lot_id, supplier_id)
  REFERENCES sobatnira.lots(tenant_id, factory_id, id, supplier_id)
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE sobatnira.intake_records ADD CONSTRAINT intake_stock_reference_key
  UNIQUE (tenant_id, factory_id, id, lot_id, net_weight_kg);

ALTER TABLE sobatnira.sugarcane_stock_movements ADD CONSTRAINT sugarcane_stock_matches_intake_fk
  FOREIGN KEY (tenant_id, factory_id, intake_record_id, lot_id, quantity_delta_kg)
  REFERENCES sobatnira.intake_records(tenant_id, factory_id, id, lot_id, net_weight_kg)
  DEFERRABLE INITIALLY IMMEDIATE;
