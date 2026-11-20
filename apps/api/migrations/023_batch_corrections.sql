CREATE TABLE sobatnira.production_batch_corrections (
  id uuid PRIMARY KEY,
  batch_id uuid NOT NULL REFERENCES sobatnira.production_batches(id),
  reason text NOT NULL,
  before_data jsonb NOT NULL,
  proposed_data jsonb NOT NULL,
  version integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','discarded')),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE UNIQUE INDEX production_batch_one_correction
  ON sobatnira.production_batch_corrections(batch_id) WHERE status='draft';
ALTER TABLE sobatnira.production_batch_corrections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.production_batch_corrections FROM PUBLIC,anon,authenticated;

ALTER TABLE sobatnira.production_calculation_snapshots
  DROP CONSTRAINT production_calculation_snapshots_batch_id_key,
  ADD COLUMN correction_id uuid UNIQUE REFERENCES sobatnira.production_batch_corrections(id);
CREATE UNIQUE INDEX production_batch_initial_snapshot
  ON sobatnira.production_calculation_snapshots(batch_id) WHERE correction_id IS NULL;
