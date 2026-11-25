ALTER TABLE sobatnira.production_batches
  ADD COLUMN source_document_id uuid,
  ADD COLUMN source_revision_id uuid,
  ADD COLUMN source_block text,
  ADD COLUMN source_row text,
  ADD CONSTRAINT batch_source_complete CHECK (
    (source_document_id IS NULL AND source_revision_id IS NULL AND source_block IS NULL AND source_row IS NULL)
    OR (source_document_id IS NOT NULL AND source_revision_id IS NOT NULL
      AND length(btrim(source_block)) > 0 AND length(btrim(source_row)) > 0));
CREATE UNIQUE INDEX production_batch_note_row_active ON sobatnira.production_batches
  (tenant_id,factory_id,source_document_id,source_block,source_row) WHERE status <> 'cancelled';
