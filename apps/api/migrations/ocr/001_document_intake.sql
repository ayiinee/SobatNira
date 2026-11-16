CREATE TABLE operator_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  factory_id uuid NOT NULL,
  display_name text NOT NULL,
  phone_e164 text NOT NULL UNIQUE CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE review_memberships (
  user_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  role text NOT NULL CHECK (role IN ('ADMIN', 'OWNER')),
  active boolean NOT NULL DEFAULT true,
  PRIMARY KEY (user_id, factory_id)
);

CREATE TABLE whatsapp_inbound_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id uuid NOT NULL REFERENCES operator_contacts,
  provider_message_id text NOT NULL UNIQUE,
  event jsonb NOT NULL,
  fingerprint text NOT NULL,
  outcome jsonb,
  received_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX whatsapp_inbound_operator_window ON whatsapp_inbound_messages (operator_id, received_at);

CREATE TABLE media_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  factory_id uuid NOT NULL,
  object_key text NOT NULL UNIQUE,
  mime_type text NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png')),
  size_bytes integer NOT NULL CHECK (size_bytes > 0),
  sha256 text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE source_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  factory_id uuid NOT NULL,
  document_type text NOT NULL DEFAULT 'UNKNOWN'
    CHECK (document_type IN ('UNKNOWN', 'TRUCK_ARRIVAL_NOTE', 'PRODUCTION_NOTE')),
  current_revision_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX source_documents_factory_type ON source_documents (factory_id, document_type);

CREATE TABLE document_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL REFERENCES source_documents,
  inbound_message_id uuid NOT NULL UNIQUE REFERENCES whatsapp_inbound_messages,
  media_asset_id uuid NOT NULL UNIQUE REFERENCES media_assets,
  explicit_new boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (document_id, id)
);

CREATE TABLE document_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL REFERENCES source_documents,
  submission_id uuid NOT NULL,
  parent_revision_id uuid,
  version integer NOT NULL CHECK (version > 0),
  schema_version text NOT NULL DEFAULT '1.0.0',
  processing_status text NOT NULL DEFAULT 'QUEUED' CHECK (processing_status IN (
    'QUEUED', 'PROCESSING', 'EXTRACTED', 'NEEDS_CLARIFICATION', 'MANUAL_REVIEW_REQUIRED', 'FAILED_FINAL'
  )),
  operator_status text NOT NULL DEFAULT 'NOT_REQUESTED' CHECK (operator_status IN (
    'NOT_REQUESTED', 'PENDING', 'CONFIRMED'
  )),
  extraction jsonb,
  issues jsonb NOT NULL DEFAULT '[]',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (document_id, version),
  UNIQUE (document_id, id),
  FOREIGN KEY (document_id, submission_id) REFERENCES document_submissions (document_id, id),
  FOREIGN KEY (document_id, parent_revision_id) REFERENCES document_revisions (document_id, id)
);
ALTER TABLE source_documents ADD FOREIGN KEY (id, current_revision_id)
  REFERENCES document_revisions (document_id, id);

CREATE TABLE document_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  revision_id uuid NOT NULL UNIQUE REFERENCES document_revisions,
  status text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED')),
  attempts integer NOT NULL DEFAULT 0,
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_until timestamptz,
  claim_token uuid
);
CREATE INDEX document_jobs_claim ON document_jobs (available_at) WHERE status IN ('QUEUED', 'PROCESSING');

CREATE TABLE extraction_attempts (
  id uuid PRIMARY KEY,
  job_id uuid NOT NULL REFERENCES document_jobs,
  attempt integer NOT NULL CHECK (attempt > 0),
  envelope jsonb,
  error_code text,
  completed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_id, attempt),
  CHECK ((envelope IS NULL) <> (error_code IS NULL))
);

CREATE TABLE clarification_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  revision_id uuid NOT NULL REFERENCES document_revisions,
  issue_code text NOT NULL,
  field_path text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE operator_confirmations (
  revision_id uuid PRIMARY KEY REFERENCES document_revisions,
  operator_id uuid NOT NULL REFERENCES operator_contacts,
  inbound_message_id uuid NOT NULL UNIQUE REFERENCES whatsapp_inbound_messages,
  confirmed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE admin_review_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL REFERENCES source_documents,
  revision_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'PENDING_VALIDATION' CHECK (status IN (
    'PENDING_VALIDATION', 'RETURNED_FOR_CORRECTION', 'VALIDATED', 'SUPERSEDED', 'MANUAL_REVIEW_REQUIRED'
  )),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (document_id, revision_id) REFERENCES document_revisions (document_id, id)
);
CREATE UNIQUE INDEX one_pending_review_per_document ON admin_review_tasks (document_id)
  WHERE status = 'PENDING_VALIDATION';

CREATE TABLE document_approvals (
  document_id uuid NOT NULL,
  revision_id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  note text,
  approved_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (document_id, revision_id) REFERENCES document_revisions (document_id, id)
);

CREATE TABLE mobile_review_actions (
  user_id uuid NOT NULL,
  idempotency_key text NOT NULL,
  fingerprint text NOT NULL,
  outcome jsonb NOT NULL,
  PRIMARY KEY (user_id, idempotency_key)
);

CREATE TABLE audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  action text NOT NULL,
  actor_id uuid,
  details jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (document_id, revision_id) REFERENCES document_revisions (document_id, id)
);
CREATE INDEX audit_events_document ON audit_events (document_id, created_at);

-- These tables are queried by the NestJS database principal. No policies grant
-- direct access through the public Supabase client roles.
ALTER TABLE operator_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_inbound_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE source_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE extraction_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE clarification_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_review_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobile_review_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;
