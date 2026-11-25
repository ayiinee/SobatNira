-- Strengthen the original CHECK: SQL NULL must not permit a partial row identity.
ALTER TABLE sobatnira.production_batches ADD CONSTRAINT batch_source_identity_not_null CHECK (
 source_document_id IS NULL OR (source_block IS NOT NULL AND source_row IS NOT NULL)
);
