ALTER TABLE sobatnira.production_batches ADD COLUMN kind text NOT NULL DEFAULT 'normal' CHECK(kind IN ('normal','rework'));
ALTER TABLE sobatnira.production_inventory_state ADD COLUMN rework_enabled boolean NOT NULL DEFAULT false;
CREATE TABLE sobatnira.production_rework_reservations (
 tenant_id uuid NOT NULL,factory_id uuid NOT NULL,is_synthetic boolean NOT NULL,
 request_id uuid NOT NULL, batch_id uuid NOT NULL,source_id uuid NOT NULL,
 weight_kg numeric NOT NULL CHECK(weight_kg>0 AND weight_kg<'Infinity'::numeric AND scale(weight_kg)<=6),
 state text NOT NULL DEFAULT 'reserved' CHECK(state IN ('reserved','consumed','released')),
 actor_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),finalized_at timestamptz,
 PRIMARY KEY(tenant_id,factory_id,request_id),
 FOREIGN KEY(tenant_id,factory_id,batch_id) REFERENCES sobatnira.production_batches(tenant_id,factory_id,id),
 FOREIGN KEY(tenant_id,factory_id,source_id) REFERENCES sobatnira.production_sugar_sources(tenant_id,factory_id,id)
);
CREATE INDEX production_rework_by_batch ON sobatnira.production_rework_reservations(batch_id,state);
CREATE INDEX production_rework_by_source ON sobatnira.production_rework_reservations(source_id,state);
ALTER TABLE sobatnira.production_rework_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.production_rework_reservations FROM PUBLIC,anon,authenticated;
