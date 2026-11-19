-- Additive production records. Prices and costs are frozen by approval.
CREATE TABLE sobatnira.production_batches (
 id uuid PRIMARY KEY,
 tenant_id uuid NOT NULL,
 factory_id uuid NOT NULL,
 lot_id uuid NOT NULL,
 code text NOT NULL CHECK(length(btrim(code)) BETWEEN 1 AND 100),
 wok_number integer NOT NULL CHECK(wok_number>0),
 occurred_at timestamptz NOT NULL,
 quantity_ml numeric NOT NULL CHECK(quantity_ml>0 AND quantity_ml<'Infinity'::numeric),
 physical_weight_kg numeric NOT NULL CHECK(physical_weight_kg>0 AND physical_weight_kg<'Infinity'::numeric),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','approved','cancelled')),
 is_synthetic boolean NOT NULL DEFAULT false,
 input_hash text NOT NULL,
 created_by uuid NOT NULL,
 approved_by uuid,
 approved_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(tenant_id,factory_id,id),
 UNIQUE(tenant_id,factory_id,code),
 FOREIGN KEY(tenant_id,factory_id,lot_id) REFERENCES sobatnira.lots(tenant_id,factory_id,id),
 CHECK((status='approved')=(approved_at IS NOT NULL AND approved_by IS NOT NULL))
);
CREATE TABLE sobatnira.batch_grade_results (
 batch_id uuid NOT NULL REFERENCES sobatnira.production_batches(id),
 code text NOT NULL,
 weight_kg numeric NOT NULL CHECK(weight_kg>0 AND weight_kg<'Infinity'::numeric),
 price_per_kg_rupiah numeric NOT NULL CHECK(price_per_kg_rupiah>=0 AND price_per_kg_rupiah<'Infinity'::numeric AND scale(price_per_kg_rupiah)=0),
 PRIMARY KEY(batch_id,code)
);
CREATE TABLE sobatnira.lot_production_costs (
 tenant_id uuid NOT NULL,
 factory_id uuid NOT NULL,
 lot_id uuid NOT NULL,
 cane_rupiah numeric NOT NULL CHECK(cane_rupiah>=0 AND cane_rupiah<'Infinity'::numeric AND scale(cane_rupiah)=0),
 operational_rupiah numeric NOT NULL CHECK(operational_rupiah>=0 AND operational_rupiah<'Infinity'::numeric AND scale(operational_rupiah)=0),
 ingredient_rupiah numeric NOT NULL CHECK(ingredient_rupiah>=0 AND ingredient_rupiah<'Infinity'::numeric AND scale(ingredient_rupiah)=0),
 other_rupiah numeric NOT NULL CHECK(other_rupiah>=0 AND other_rupiah<'Infinity'::numeric AND scale(other_rupiah)=0),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,factory_id,lot_id),
 FOREIGN KEY(tenant_id,factory_id,lot_id) REFERENCES sobatnira.lots(tenant_id,factory_id,id)
);
CREATE TABLE sobatnira.production_calculation_snapshots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL,
 factory_id uuid NOT NULL,
 lot_id uuid NOT NULL,
 batch_id uuid NOT NULL REFERENCES sobatnira.production_batches(id),
 calculation_version text NOT NULL,
 input_snapshot jsonb NOT NULL,
 output_snapshot jsonb NOT NULL,
 is_synthetic boolean NOT NULL,
 approved_by uuid NOT NULL,
 approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(batch_id),
 FOREIGN KEY(tenant_id,factory_id,lot_id) REFERENCES sobatnira.lots(tenant_id,factory_id,id)
);
CREATE TABLE sobatnira.production_batch_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 batch_id uuid NOT NULL REFERENCES sobatnira.production_batches(id),
 action text NOT NULL CHECK(action IN ('created','approved','cancelled')),
 actor_id uuid NOT NULL,
 details jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX production_batches_lot_idx ON sobatnira.production_batches(tenant_id,factory_id,lot_id,status);
CREATE INDEX production_snapshots_report_idx ON sobatnira.production_calculation_snapshots(tenant_id,factory_id,is_synthetic,approved_at DESC,id);
ALTER TABLE sobatnira.production_batches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.production_batches FROM PUBLIC,anon,authenticated;
ALTER TABLE sobatnira.batch_grade_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.batch_grade_results FROM PUBLIC,anon,authenticated;
ALTER TABLE sobatnira.lot_production_costs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.lot_production_costs FROM PUBLIC,anon,authenticated;
ALTER TABLE sobatnira.production_calculation_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.production_calculation_snapshots FROM PUBLIC,anon,authenticated;
ALTER TABLE sobatnira.production_batch_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.production_batch_events FROM PUBLIC,anon,authenticated;
