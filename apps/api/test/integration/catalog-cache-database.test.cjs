const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { setTimeout: delay } = require('node:timers/promises');
const { intakeFixture } = require('./intake-fixture.cjs');
const { redisFixture } = require('../helpers/redis-fixture.cjs');
const { CatalogCache } = require('../../dist/cache/catalog-cache');

test('catalog cache wire protocol, committed invalidation, rollback, isolation and Redis recovery keep HTTP results current', async () => {
  const redis = await redisFixture();
  const f = await intakeFixture(true, { CATALOG_CACHE_ENABLED: 'true', REDIS_URL: redis.url,
    CATALOG_CACHE_TTL_SECONDS: '1', CATALOG_CACHE_TIMEOUT_MS: '1000' });
  const version = async (catalog = 'suppliers') => (await f.client.query(
    'SELECT generation FROM sobatnira.catalog_cache_versions WHERE tenant_id=$1 AND catalog=$2', [f.ids.tenant, catalog])).rows[0]?.generation;
  try {
    const cache = f.app.get(CatalogCache), path = f.root + '/suppliers?limit=20';
    const first = await f.request(path); assert.equal(first.status, 200, JSON.stringify(first.body));
    assert.deepEqual((await f.request(path)).body, first.body); assert.ok(cache.statistics().hit > 0);
    const generation = await version();
    await f.client.query('BEGIN');
    await f.client.query("UPDATE sobatnira.suppliers SET name='Not committed' WHERE id=$1", [f.ids.supplier]);
    const inside = await version(); assert.notEqual(inside, generation);
    // HTTP uses a separate pool connection and must not see the uncommitted generation.
    assert.deepEqual((await f.request(path)).body, first.body);
    await f.client.query('ROLLBACK'); assert.equal(await version(), generation);
    const updated = await f.request(f.root + '/suppliers/' + f.ids.supplier, 'PATCH', { name: 'Committed synthetic' });
    assert.equal(updated.status, 200); assert.notEqual(await version(), generation);
    assert.ok((await f.request(path)).body.items.some(item => item.name === 'Committed synthetic'));

    const created = await f.request(f.root + '/cane-types', 'POST', { code: 'CACHE_TEST', name: 'Synthetic cane' });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const canePath = f.root + '/cane-types?limit=20';
    const cane = await f.request(canePath); assert.equal(cane.status, 200);
    await f.request(canePath); const caneVersion = await version('cane_types');
    assert.equal((await f.request(f.root + '/cane-types/' + created.body.id, 'PATCH', { isActive: false })).status, 200);
    assert.notEqual(await version('cane_types'), caneVersion);
    assert.equal((await f.request(canePath)).body.items.find(item => item.id === created.body.id).isActive, false);

    const own = (await f.request(path)).body;
    const other = (await f.request(f.otherRoot + '/suppliers?limit=20')).body;
    assert.ok(other.items.every(item => item.tenantId === f.ids.otherTenant)); assert.notDeepEqual(other, own);
    assert.equal((await f.request(path, 'GET', undefined, null)).status, 401);
    await f.client.query('UPDATE sobatnira.factory_memberships SET is_active=false WHERE user_id=$1 AND factory_id=$2', [f.ids.admin, f.ids.factory]);
    assert.equal((await f.request(path)).status, 403);
    await f.client.query('UPDATE sobatnira.factory_memberships SET is_active=true WHERE user_id=$1 AND factory_id=$2', [f.ids.admin, f.ids.factory]);

    // Invalidate while storage is unavailable; reconnect must never reuse the old generation.
    redis.state.unavailable = true;
    assert.equal((await f.request(f.root + '/suppliers/' + f.ids.supplier, 'PATCH', { name: 'Changed during outage' })).status, 200);
    assert.ok((await f.request(path)).body.items.some(item => item.name === 'Changed during outage'));
    redis.state.unavailable = false;
    for (let n = 0; n < 30 && cache.client.status !== 'ready'; n++) await delay(100);
    assert.ok((await f.request(path)).body.items.some(item => item.name === 'Changed during outage'));
    const misses = cache.statistics().miss; await delay(1100); await f.request(path);
    assert.ok(cache.statistics().miss > misses); // TTL expiration, no stale fallback.

    // A statement-level truncate hook can be tested on an empty local temp table.
    const beforeTruncate = await version();
    await f.client.query('CREATE TEMP TABLE cache_truncate_probe (tenant_id uuid)');
    await f.client.query(`CREATE TRIGGER cache_truncate_test AFTER TRUNCATE ON cache_truncate_probe
      FOR EACH STATEMENT EXECUTE FUNCTION sobatnira.bump_catalog_cache_truncate('suppliers')`);
    await f.client.query('TRUNCATE cache_truncate_probe'); assert.notEqual(await version(), beforeTruncate);
    const disposableSupplier = randomUUID();
    await f.client.query("INSERT INTO sobatnira.suppliers(id,tenant_id,name) VALUES($1,$2,'Disposable synthetic')", [disposableSupplier, f.ids.tenant]);
    const beforeDelete = await version();
    await f.client.query('DELETE FROM sobatnira.suppliers WHERE id=$1', [disposableSupplier]);
    assert.notEqual(await version(), beforeDelete);
    assert.ok(redis.calls.some(call => call.command === 'SET'));
    assert.ok(cache.statistics().error > 0);
  } finally {
    // Fixture cleanup predates the cane catalog; remove only this fixture's tenant rows.
    await f.client.query('DELETE FROM sobatnira.cane_types WHERE tenant_id IN ($1,$2)', [f.ids.tenant, f.ids.otherTenant]);
    await f.close(); await redis.close();
  }
});
