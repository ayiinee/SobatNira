-- Durable invalidation: new keys become visible only when catalog changes commit.
CREATE TABLE sobatnira.catalog_cache_versions (
  tenant_id uuid NOT NULL REFERENCES sobatnira.tenants(id) ON DELETE CASCADE,
  catalog text NOT NULL CHECK(catalog IN ('suppliers','cane_types')),
  generation uuid NOT NULL DEFAULT gen_random_uuid(),
  PRIMARY KEY(tenant_id,catalog)
);
ALTER TABLE sobatnira.catalog_cache_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sobatnira.catalog_cache_versions FROM PUBLIC,anon,authenticated;

CREATE FUNCTION sobatnira.bump_catalog_cache_version() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,sobatnira AS $$
BEGIN
  -- One generation per affected tenant/statement, including bulk imports.
  IF TG_OP='INSERT' THEN
    INSERT INTO sobatnira.catalog_cache_versions(tenant_id,catalog)
      SELECT DISTINCT tenant_id,TG_ARGV[0] FROM new_catalog_rows
    ON CONFLICT(tenant_id,catalog) DO UPDATE SET generation=gen_random_uuid();
  ELSIF TG_OP='DELETE' THEN
    INSERT INTO sobatnira.catalog_cache_versions(tenant_id,catalog)
      SELECT DISTINCT tenant_id,TG_ARGV[0] FROM old_catalog_rows
    ON CONFLICT(tenant_id,catalog) DO UPDATE SET generation=gen_random_uuid();
  ELSE
    INSERT INTO sobatnira.catalog_cache_versions(tenant_id,catalog)
      SELECT tenant_id,TG_ARGV[0] FROM (
        SELECT tenant_id FROM old_catalog_rows UNION SELECT tenant_id FROM new_catalog_rows
      ) affected
    ON CONFLICT(tenant_id,catalog) DO UPDATE SET generation=gen_random_uuid();
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION sobatnira.bump_catalog_cache_version() FROM PUBLIC,anon,authenticated;

CREATE TRIGGER suppliers_cache_insert AFTER INSERT ON sobatnira.suppliers
REFERENCING NEW TABLE AS new_catalog_rows FOR EACH STATEMENT EXECUTE FUNCTION sobatnira.bump_catalog_cache_version('suppliers');
CREATE TRIGGER suppliers_cache_update AFTER UPDATE ON sobatnira.suppliers
REFERENCING OLD TABLE AS old_catalog_rows NEW TABLE AS new_catalog_rows FOR EACH STATEMENT EXECUTE FUNCTION sobatnira.bump_catalog_cache_version('suppliers');
CREATE TRIGGER suppliers_cache_delete AFTER DELETE ON sobatnira.suppliers
REFERENCING OLD TABLE AS old_catalog_rows FOR EACH STATEMENT EXECUTE FUNCTION sobatnira.bump_catalog_cache_version('suppliers');
CREATE TRIGGER cane_types_cache_insert AFTER INSERT ON sobatnira.cane_types
REFERENCING NEW TABLE AS new_catalog_rows FOR EACH STATEMENT EXECUTE FUNCTION sobatnira.bump_catalog_cache_version('cane_types');
CREATE TRIGGER cane_types_cache_update AFTER UPDATE ON sobatnira.cane_types
REFERENCING OLD TABLE AS old_catalog_rows NEW TABLE AS new_catalog_rows FOR EACH STATEMENT EXECUTE FUNCTION sobatnira.bump_catalog_cache_version('cane_types');
CREATE TRIGGER cane_types_cache_delete AFTER DELETE ON sobatnira.cane_types
REFERENCING OLD TABLE AS old_catalog_rows FOR EACH STATEMENT EXECUTE FUNCTION sobatnira.bump_catalog_cache_version('cane_types');

CREATE FUNCTION sobatnira.bump_catalog_cache_truncate() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,sobatnira AS $$
BEGIN
  UPDATE sobatnira.catalog_cache_versions SET generation=gen_random_uuid() WHERE catalog=TG_ARGV[0];
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION sobatnira.bump_catalog_cache_truncate() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER suppliers_cache_truncate AFTER TRUNCATE ON sobatnira.suppliers
FOR EACH STATEMENT EXECUTE FUNCTION sobatnira.bump_catalog_cache_truncate('suppliers');
CREATE TRIGGER cane_types_cache_truncate AFTER TRUNCATE ON sobatnira.cane_types
FOR EACH STATEMENT EXECUTE FUNCTION sobatnira.bump_catalog_cache_truncate('cane_types');
INSERT INTO sobatnira.catalog_cache_versions(tenant_id,catalog)
  SELECT DISTINCT tenant_id,'suppliers' FROM sobatnira.suppliers;
INSERT INTO sobatnira.catalog_cache_versions(tenant_id,catalog)
  SELECT DISTINCT tenant_id,'cane_types' FROM sobatnira.cane_types;
