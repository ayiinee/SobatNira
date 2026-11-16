-- OCR block and row references are positional. Use the reviewed cane label to
-- identify work already booked when a later photo changes the block order.
ALTER TABLE sobatnira.milling_records
  ADD COLUMN ocr_cane_label text,
  ADD CONSTRAINT milling_ocr_cane_label_check CHECK (
    ocr_cane_label IS NULL OR (NOT is_synthetic AND length(btrim(ocr_cane_label)) BETWEEN 1 AND 300)
  ),
  ADD UNIQUE (tenant_id, factory_id, ocr_document_id, ocr_cane_label);
