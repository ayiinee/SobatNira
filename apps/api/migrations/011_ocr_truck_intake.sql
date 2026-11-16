-- Real receipts reference the approved OCR snapshot. Synthetic receipts retain their original FK.
ALTER TABLE sobatnira.intake_records
  ALTER COLUMN document_id DROP NOT NULL,
  ALTER COLUMN document_revision DROP NOT NULL,
  DROP CONSTRAINT intake_records_is_synthetic_check,
  ADD COLUMN ocr_document_id uuid,
  ADD COLUMN ocr_revision_id uuid,
  ADD CONSTRAINT intake_record_source_check CHECK (
    (is_synthetic AND document_id IS NOT NULL AND document_revision IS NOT NULL
      AND ocr_document_id IS NULL AND ocr_revision_id IS NULL)
    OR (NOT is_synthetic AND document_id IS NULL AND document_revision IS NULL
      AND ocr_document_id IS NOT NULL AND ocr_revision_id IS NOT NULL)
  ),
  ADD UNIQUE (ocr_document_id),
  ADD UNIQUE (ocr_revision_id),
  ADD CONSTRAINT intake_stock_source_type_key UNIQUE
    (tenant_id, factory_id, id, lot_id, net_weight_kg, is_synthetic);

ALTER TABLE sobatnira.sugarcane_stock_movements
  DROP CONSTRAINT sugarcane_stock_movements_is_synthetic_check,
  ADD CONSTRAINT sugarcane_milling_synthetic_check CHECK (movement_type <> 'milling' OR is_synthetic),
  ADD CONSTRAINT sugarcane_stock_intake_source_type_fk FOREIGN KEY
    (tenant_id, factory_id, intake_record_id, lot_id, quantity_delta_kg, is_synthetic)
    REFERENCES sobatnira.intake_records(tenant_id, factory_id, id, lot_id, net_weight_kg, is_synthetic);
