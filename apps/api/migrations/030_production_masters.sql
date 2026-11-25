CREATE TABLE sobatnira.production_master_versions (
 tenant_id uuid NOT NULL, factory_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('wok','grade')), code text NOT NULL,
 version integer NOT NULL CHECK(version>0), name text NOT NULL,
 capacity_liters numeric CHECK(capacity_liters>0 AND capacity_liters<'Infinity'::numeric),
 active boolean NOT NULL, actor_id uuid NOT NULL, reason text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,factory_id,kind,code,version),
 FOREIGN KEY(tenant_id,factory_id) REFERENCES sobatnira.factories(tenant_id,id),
 CHECK((kind='wok' AND capacity_liters IS NOT NULL) OR (kind='grade' AND capacity_liters IS NULL))
);
CREATE TABLE sobatnira.production_master_requests (
 tenant_id uuid NOT NULL, factory_id uuid NOT NULL, request_id uuid NOT NULL,
 input_hash text NOT NULL, result jsonb NOT NULL,
 PRIMARY KEY(tenant_id,factory_id,request_id),
 FOREIGN KEY(tenant_id,factory_id) REFERENCES sobatnira.factories(tenant_id,id)
);
ALTER TABLE sobatnira.production_batches ADD COLUMN master_references jsonb;
ALTER TABLE sobatnira.production_master_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sobatnira.production_master_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.production_master_versions,sobatnira.production_master_requests FROM PUBLIC,anon,authenticated;
