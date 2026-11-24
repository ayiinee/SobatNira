const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfiguration } = require('../dist/config/backend.config');
const { CatalogCache } = require('../dist/cache/catalog-cache');
const { redisFixture } = require('./helpers/redis-fixture.cjs');
const access = { userId: 'user', tenantId: 'tenant', factoryId: 'factory', role: 'admin' };
const query = { limit: 20, offset: 0 };
const page = (name = 'Synthetic', tenantId = 'tenant') => ({ items: [{ id: 'supplier', tenantId, name, isActive: true }], total: 1, ...query });

class FakeRedis {
  status = 'ready'; entries = new Map(); clock = 0; failed = false; gets = 0;
  async get(key) { this.gets++; if (this.failed) throw new Error('private connection'); const item = this.entries.get(key); return item && item.expires > this.clock ? item.value : null; }
  async set(key, value, unit, duration, condition) {
    if (this.failed) throw new Error('private connection');
    const current = this.entries.get(key);
    if (condition === 'NX' && current && current.expires > this.clock) return null;
    this.entries.set(key, { value, expires: this.clock + duration * (unit === 'EX' ? 1000 : 1) }); return 'OK';
  }
  disconnect() {}
}
function fixture() {
  const state = { generation: 'generation-1', role: 'admin', allowed: true };
  const db = { query: async () => ({ rows: state.allowed ? [{ generation: state.generation, role: state.role }] : [] }) };
  const config = loadConfiguration({ envFile: false, env: { REDIS_URL: 'redis://127.0.0.1:6379',
    DATABASE_URL: 'postgres://postgres@127.0.0.1/cache_unit', CATALOG_CACHE_ENABLED: 'true' } });
  const cache = new CatalogCache(config, db), redis = new FakeRedis(); cache.client = redis;
  return { state, cache, redis, config, db };
}

test('catalog cache misses, hits, expires and isolates filters, actor, factory, role and tenant', async () => {
  const f = fixture(); let loads = 0;
  const load = async () => { loads++; return page(); };
  assert.deepEqual(await f.cache.read(access, 'suppliers', query, load), page());
  await f.cache.read(access, 'suppliers', query, load); assert.equal(loads, 1);
  for (const other of [{ ...access, userId: 'another' }, { ...access, factoryId: 'another' }]) await f.cache.read(other, 'suppliers', query, load);
  f.state.role = 'owner'; await f.cache.read(access, 'suppliers', query, load);
  await f.cache.read(access, 'suppliers', { ...query, q: 'other' }, load);
  await f.cache.read({ ...access, tenantId: 'other' }, 'suppliers', query, async () => { loads++; return page('Other', 'other'); });
  assert.equal(loads, 6);
  f.redis.clock += 301000; await f.cache.read(access, 'suppliers', query, load); assert.equal(loads, 7);
  assert.ok(f.cache.statistics().hit >= 1); await f.cache.onModuleDestroy();
});

test('durable generation invalidates across Redis outage and authorization is checked before every hit', async () => {
  const f = fixture(); let name = 'Old', loads = 0;
  const load = async () => { loads++; return page(name); };
  await f.cache.read(access, 'suppliers', query, load);
  f.redis.failed = true; f.state.generation = 'generation-2'; name = 'New';
  assert.equal((await f.cache.read(access, 'suppliers', query, load)).items[0].name, 'New');
  f.redis.failed = false;
  assert.equal((await f.cache.read(access, 'suppliers', query, load)).items[0].name, 'New');
  await f.cache.read(access, 'suppliers', query, load); assert.equal(loads, 3);
  const before = f.redis.gets; f.state.allowed = false;
  await assert.rejects(f.cache.read(access, 'suppliers', query, load), error => error.getStatus() === 403);
  assert.equal(f.redis.gets, before); await f.cache.onModuleDestroy();
});

test('local single flight and cross-instance fill lock share a result; corrupt or foreign payloads miss safely', async () => {
  const f = fixture(); let loads = 0;
  const load = async () => { loads++; await new Promise(resolve => setTimeout(resolve, 40)); return page(); };
  const other = new CatalogCache(f.config, f.db); other.client = f.redis;
  await Promise.all([f.cache.read(access, 'suppliers', query, load), other.read(access, 'suppliers', query, load),
    ...Array.from({ length: 5 }, () => f.cache.read(access, 'suppliers', query, load))]);
  assert.equal(loads, 1); assert.equal(f.cache.statistics().coalesced, 5); assert.ok(other.statistics().lockWait > 0);
  const key = [...f.redis.entries.keys()].find(key => !key.endsWith(':fill'));
  const envelope = JSON.parse(f.redis.entries.get(key).value);
  envelope.data.items[0].tenantId = 'foreign'; f.redis.entries.get(key).value = JSON.stringify(envelope);
  await f.cache.read(access, 'suppliers', query, load);
  assert.equal(loads, 2); assert.ok(f.cache.statistics().invalid > 0);
  await f.cache.onModuleDestroy(); await other.onModuleDestroy();
});

test('disabled cache bypasses Redis/version queries and database failures are not cached', async () => {
  const config = loadConfiguration({ envFile: false, env: {} });
  const off = new CatalogCache(config, { query: () => { throw new Error('must not query version'); } });
  assert.deepEqual(await off.read(access, 'suppliers', query, async () => page()), page());
  const f = fixture();
  await assert.rejects(f.cache.read(access, 'suppliers', query, async () => { throw new Error('DB failure'); }), /DB failure/);
  assert.ok([...f.redis.entries.keys()].every(key => key.endsWith(':fill')));
  for (const env of [{ CATALOG_CACHE_ENABLED: 'yes' }, { CATALOG_CACHE_TTL_SECONDS: '0' }, { CATALOG_CACHE_TIMEOUT_MS: '10' }]) assert.throws(() => loadConfiguration({ envFile: false, env }));
  await f.cache.onModuleDestroy(); await off.onModuleDestroy();
});

test('ioredis command timeout falls back to current database data without waiting for a stalled server', { timeout: 10000 }, async () => {
  const redis = await redisFixture(); let generation = 'v1';
  const config = loadConfiguration({ envFile: false, env: { REDIS_URL: redis.url,
    CATALOG_CACHE_ENABLED: 'true', CATALOG_CACHE_TIMEOUT_MS: '200' } });
  const cache = new CatalogCache(config, { query: async () => ({ rows: [{ generation, role: 'admin' }] }) });
  try {
    await cache.read(access, 'suppliers', query, async () => page('Old'));
    assert.equal(cache.statistics().error, 0);
    generation = 'v2'; redis.state.delayMs = 60000;
    const result = await cache.read(access, 'suppliers', query, async () => page('Current'));
    assert.equal(result.items[0].name, 'Current'); assert.ok(cache.statistics().error > 0);
  } finally { await cache.onModuleDestroy(); await redis.close(); }
});
