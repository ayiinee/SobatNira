CREATE TABLE sobatnira.intake_evidence (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  document_id uuid NOT NULL,
  request_id uuid NOT NULL,
  request_hash text NOT NULL,
  object_key text NOT NULL UNIQUE,
  content_type text NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp')),
  byte_size integer NOT NULL CHECK (byte_size BETWEEN 1 AND 8388608),
  sha256 text NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
  width integer NOT NULL CHECK (width > 0),
  height integer NOT NULL CHECK (height > 0),
  uploaded_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (tenant_id, factory_id, document_id, id),
  UNIQUE (tenant_id, factory_id, document_id, request_id),
  FOREIGN KEY (tenant_id, factory_id, document_id) REFERENCES sobatnira.intake_documents(tenant_id, factory_id, id),
  CHECK (width::bigint * height::bigint <= 20000000)
);

ALTER TABLE sobatnira.intake_documents ADD COLUMN evidence_id uuid;
ALTER TABLE sobatnira.intake_documents ADD CONSTRAINT intake_current_evidence_fk
  FOREIGN KEY (tenant_id, factory_id, id, evidence_id)
  REFERENCES sobatnira.intake_evidence(tenant_id, factory_id, document_id, id)
  DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sobatnira.intake_document_revisions ADD COLUMN evidence_id uuid;
ALTER TABLE sobatnira.intake_document_revisions ADD CONSTRAINT intake_revision_evidence_fk
  FOREIGN KEY (tenant_id, factory_id, document_id, evidence_id)
  REFERENCES sobatnira.intake_evidence(tenant_id, factory_id, document_id, id)
  DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE sobatnira.intake_document_revisions DROP CONSTRAINT intake_document_revisions_origin_check;
ALTER TABLE sobatnira.intake_document_revisions ADD CONSTRAINT intake_document_revisions_origin_check
  CHECK (origin IN ('synthetic_extraction', 'admin_correction', 'evidence_attachment'));

ALTER TABLE sobatnira.intake_document_events DROP CONSTRAINT intake_document_events_action_check;
ALTER TABLE sobatnira.intake_document_events ADD CONSTRAINT intake_document_events_action_check
  CHECK (action IN ('created', 'draft_updated', 'confirmed', 'approved', 'evidence_attached'));

CREATE INDEX intake_evidence_document_idx ON sobatnira.intake_evidence(tenant_id, factory_id, document_id, created_at DESC, id);
ALTER TABLE sobatnira.intake_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.intake_evidence FROM PUBLIC, anon, authenticated;
