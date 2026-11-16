CREATE TABLE whatsapp_notices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  revision_id uuid NOT NULL REFERENCES document_revisions,
  kind text NOT NULL CHECK (kind IN ('OCR_RESULT', 'ADMIN_RETURNED')),
  status text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','SENDING','SENT','FAILED','CANCELLED')),
  available_at timestamptz NOT NULL DEFAULT now(),
  attempts integer NOT NULL DEFAULT 0,
  claim_token uuid,
  lease_until timestamptz,
  provider_message_id text,
  UNIQUE (revision_id, kind)
);
CREATE INDEX whatsapp_notices_queue ON whatsapp_notices (available_at)
  WHERE status IN ('QUEUED','SENDING');
ALTER TABLE whatsapp_notices ENABLE ROW LEVEL SECURITY;
