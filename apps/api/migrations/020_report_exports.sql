CREATE TABLE sobatnira.report_exports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  factory_id uuid NOT NULL,
  requested_by uuid NOT NULL REFERENCES auth.users (id),
  idempotency_key uuid NOT NULL,
  input_hash text NOT NULL,
  snapshot jsonb NOT NULL,
  status text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','PROCESSING','READY','FAILED')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  available_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  lease_until timestamptz,
  claim_token uuid,
  artifacts jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at timestamptz,
  FOREIGN KEY (tenant_id, factory_id) REFERENCES sobatnira.factories (tenant_id, id),
  UNIQUE (tenant_id, factory_id, requested_by, idempotency_key),
  CHECK ((status='READY')=(artifacts IS NOT NULL)),
  CHECK ((status='PROCESSING')=(claim_token IS NOT NULL AND lease_until IS NOT NULL))
);
CREATE INDEX report_exports_work_idx ON sobatnira.report_exports (available_at,lease_until,id)
  WHERE status IN ('QUEUED','PROCESSING');
ALTER TABLE sobatnira.report_exports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.report_exports FROM PUBLIC, anon, authenticated;
