ALTER TABLE sobatnira.report_exports ADD COLUMN delivery_target text;

CREATE TABLE sobatnira.report_export_notices (
  report_id uuid PRIMARY KEY REFERENCES sobatnira.report_exports (id),
  status text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','PROCESSING','SENT','FAILED')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  available_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  claim_token uuid,
  lease_until timestamptz,
  provider_receipt text,
  CHECK ((status='PROCESSING')=(claim_token IS NOT NULL AND lease_until IS NOT NULL)),
  CHECK ((status='SENT')=(provider_receipt IS NOT NULL))
);
CREATE INDEX report_export_notices_work_idx ON sobatnira.report_export_notices (available_at,lease_until)
  WHERE status IN ('QUEUED','PROCESSING');
ALTER TABLE sobatnira.report_export_notices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.report_export_notices FROM PUBLIC, anon, authenticated;
