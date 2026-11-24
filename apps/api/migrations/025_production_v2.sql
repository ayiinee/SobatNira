ALTER TABLE sobatnira.lot_production_costs
  ADD COLUMN version integer NOT NULL DEFAULT 1 CHECK(version > 0),
  ADD COLUMN updated_by uuid,
  ADD COLUMN updated_at timestamptz;

ALTER TABLE sobatnira.production_audit_events
 DROP CONSTRAINT production_audit_events_entity_type_check,
 ADD CONSTRAINT production_audit_events_entity_type_check
 CHECK(entity_type IN ('supplier','lot','cane_type','lot_costs'));

CREATE TABLE sobatnira.production_cost_corrections (
 id uuid PRIMARY KEY,
 tenant_id uuid NOT NULL,
 factory_id uuid NOT NULL,
 lot_id uuid NOT NULL,
 expected_version integer NOT NULL CHECK(expected_version > 0),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 500),
 proposed_data jsonb NOT NULL,
 input_hash text NOT NULL,
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','approved')),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 approved_by uuid,
 approved_at timestamptz,
 FOREIGN KEY(tenant_id,factory_id,lot_id) REFERENCES sobatnira.lots(tenant_id,factory_id,id),
 CHECK((status='approved')=(approved_by IS NOT NULL AND approved_at IS NOT NULL))
);
ALTER TABLE sobatnira.production_cost_corrections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.production_cost_corrections FROM PUBLIC,anon,authenticated;

ALTER TABLE sobatnira.production_calculation_snapshots
  DROP CONSTRAINT production_calculation_snapshots_correction_id_key,
  ADD COLUMN cost_correction_id uuid REFERENCES sobatnira.production_cost_corrections(id);
DROP INDEX sobatnira.production_batch_initial_snapshot;
CREATE UNIQUE INDEX production_batch_initial_snapshot
 ON sobatnira.production_calculation_snapshots(batch_id,lot_id)
 WHERE correction_id IS NULL AND cost_correction_id IS NULL;
CREATE UNIQUE INDEX production_batch_correction_snapshot
 ON sobatnira.production_calculation_snapshots(correction_id,lot_id) WHERE correction_id IS NOT NULL;
CREATE UNIQUE INDEX production_cost_correction_snapshot
 ON sobatnira.production_calculation_snapshots(cost_correction_id,lot_id,is_synthetic) WHERE cost_correction_id IS NOT NULL;

-- Audit every cost update, including requests from older clients without versions.
CREATE FUNCTION sobatnira.audit_production_cost() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO sobatnira.production_audit_events
 (tenant_id,factory_id,entity_type,entity_id,action,actor_id,before_data,after_data)
 VALUES(NEW.tenant_id,NEW.factory_id,'lot_costs',NEW.lot_id,
 CASE WHEN TG_OP='INSERT' THEN 'created' ELSE 'updated' END,
 COALESCE(NEW.updated_by,NEW.created_by),
 CASE WHEN TG_OP='UPDATE' THEN to_jsonb(OLD) ELSE NULL END,to_jsonb(NEW));
 RETURN NEW;
END $$;
CREATE TRIGGER production_cost_audit AFTER INSERT OR UPDATE ON sobatnira.lot_production_costs
 FOR EACH ROW EXECUTE FUNCTION sobatnira.audit_production_cost();
