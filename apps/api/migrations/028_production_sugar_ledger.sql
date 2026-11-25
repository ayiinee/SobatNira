CREATE TABLE sobatnira.production_inventory_state (
 tenant_id uuid NOT NULL, factory_id uuid NOT NULL, is_synthetic boolean NOT NULL,
 activated_at timestamptz NOT NULL DEFAULT clock_timestamp(), version integer NOT NULL DEFAULT 1 CHECK(version>0),
 PRIMARY KEY(tenant_id,factory_id,is_synthetic),
 FOREIGN KEY(tenant_id,factory_id) REFERENCES sobatnira.factories(tenant_id,id)
);
CREATE TABLE sobatnira.production_inventory_requests (
 tenant_id uuid NOT NULL, factory_id uuid NOT NULL, is_synthetic boolean NOT NULL,
 request_id uuid NOT NULL, input_hash text NOT NULL, result jsonb NOT NULL,
 actor_id uuid NOT NULL, reason text NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,factory_id,request_id),
 FOREIGN KEY(tenant_id,factory_id) REFERENCES sobatnira.factories(tenant_id,id)
);
CREATE TABLE sobatnira.production_sugar_sources (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, factory_id uuid NOT NULL,
 is_synthetic boolean NOT NULL, batch_id uuid, origin_lot_id uuid, grade_code text NOT NULL,
 quality text NOT NULL CHECK(quality IN ('good','failed')),
 on_hand_kg numeric NOT NULL DEFAULT 0 CHECK(on_hand_kg>=0 AND on_hand_kg<'Infinity'::numeric AND scale(on_hand_kg)<=6),
 reserved_kg numeric NOT NULL DEFAULT 0 CHECK(reserved_kg>=0 AND reserved_kg<=on_hand_kg),
 opening_request_id uuid, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(tenant_id,factory_id,id), UNIQUE(tenant_id,factory_id,is_synthetic,batch_id,origin_lot_id,grade_code,quality),
 FOREIGN KEY(tenant_id,factory_id,batch_id) REFERENCES sobatnira.production_batches(tenant_id,factory_id,id),
 FOREIGN KEY(tenant_id,factory_id,origin_lot_id) REFERENCES sobatnira.lots(tenant_id,factory_id,id),
 FOREIGN KEY(tenant_id,factory_id) REFERENCES sobatnira.factories(tenant_id,id)
);
CREATE TABLE sobatnira.production_sugar_entries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, factory_id uuid NOT NULL,
 source_id uuid NOT NULL, quantity_delta_kg numeric NOT NULL CHECK(quantity_delta_kg<>0 AND abs(quantity_delta_kg)<'Infinity'::numeric AND scale(quantity_delta_kg)<=6),
 kind text NOT NULL CHECK(kind IN ('opening','production','correction','adjustment','quality','rework')),
 event_id uuid NOT NULL, actor_id uuid NOT NULL, reason text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(tenant_id,factory_id,source_id) REFERENCES sobatnira.production_sugar_sources(tenant_id,factory_id,id),
 UNIQUE(source_id,kind,event_id)
);
CREATE TABLE sobatnira.production_output_allocations (
 tenant_id uuid NOT NULL,factory_id uuid NOT NULL,batch_id uuid NOT NULL,event_id uuid NOT NULL,
 version integer NOT NULL,origin_lot_id uuid NOT NULL,grade_code text NOT NULL,
 weight_kg numeric NOT NULL CHECK(weight_kg>=0 AND weight_kg<'Infinity'::numeric AND scale(weight_kg)<=6),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(batch_id,event_id,origin_lot_id,grade_code),
 FOREIGN KEY(tenant_id,factory_id,batch_id) REFERENCES sobatnira.production_batches(tenant_id,factory_id,id),
 FOREIGN KEY(tenant_id,factory_id,origin_lot_id) REFERENCES sobatnira.lots(tenant_id,factory_id,id)
);
CREATE INDEX production_sugar_balances ON sobatnira.production_sugar_sources(tenant_id,factory_id,is_synthetic,grade_code,quality);
CREATE INDEX production_sugar_history ON sobatnira.production_sugar_entries(source_id,created_at,id);
ALTER TABLE sobatnira.production_inventory_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.production_inventory_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.production_sugar_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.production_sugar_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.production_output_allocations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.production_inventory_state,sobatnira.production_inventory_requests,
 sobatnira.production_sugar_sources,sobatnira.production_sugar_entries,sobatnira.production_output_allocations FROM PUBLIC,anon,authenticated;
