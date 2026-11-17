-- An approved OCR revision may report several kloter. Each kloter keeps one milling record.
ALTER TABLE sobatnira.milling_records
  ALTER COLUMN document_id DROP NOT NULL,
  ALTER COLUMN document_revision DROP NOT NULL,
  DROP CONSTRAINT milling_records_is_synthetic_check,
  ADD COLUMN ocr_document_id uuid,
  ADD COLUMN ocr_revision_id uuid,
  ADD CONSTRAINT milling_record_source_check CHECK (
    (is_synthetic AND document_id IS NOT NULL AND document_revision IS NOT NULL
      AND ocr_document_id IS NULL AND ocr_revision_id IS NULL)
    OR (NOT is_synthetic AND document_id IS NULL AND document_revision IS NULL
      AND ocr_document_id IS NOT NULL AND ocr_revision_id IS NOT NULL)
  ),
  ADD UNIQUE (tenant_id, factory_id, ocr_document_id, lot_id),
  ADD CONSTRAINT milling_cane_source_type_key UNIQUE
    (tenant_id, factory_id, id, lot_id, cane_stock_delta_kg, is_synthetic),
  ADD CONSTRAINT milling_juice_source_type_key UNIQUE
    (tenant_id, factory_id, id, lot_id, juice_produced_liters, is_synthetic);

ALTER TABLE sobatnira.sugarcane_stock_movements
  DROP CONSTRAINT sugarcane_milling_synthetic_check,
  DROP CONSTRAINT sugarcane_milling_source_fk,
  ADD CONSTRAINT sugarcane_milling_source_fk FOREIGN KEY
    (tenant_id, factory_id, milling_record_id, lot_id, quantity_delta_kg, is_synthetic)
    REFERENCES sobatnira.milling_records(tenant_id, factory_id, id, lot_id, cane_stock_delta_kg, is_synthetic)
    DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE sobatnira.juice_stock_movements
  DROP CONSTRAINT juice_stock_movements_is_synthetic_check,
  ADD CONSTRAINT juice_milling_source_type_fk FOREIGN KEY
    (tenant_id, factory_id, milling_record_id, lot_id, quantity_delta_liters, is_synthetic)
    REFERENCES sobatnira.milling_records(tenant_id, factory_id, id, lot_id, juice_produced_liters, is_synthetic)
    DEFERRABLE INITIALLY IMMEDIATE;
