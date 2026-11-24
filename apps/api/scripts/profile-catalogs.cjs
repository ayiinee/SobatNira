const { mkdir, writeFile } = require('node:fs/promises');
const { resolve } = require('node:path');
const { performance } = require('node:perf_hooks');
const assert = require('node:assert/strict');
const { intakeFixture } = require('../test/integration/intake-fixture.cjs');
const { redisFixture } = require('../test/helpers/redis-fixture.cjs');
const { SuppliersRepository } = require('../dist/suppliers/suppliers.repository');
const { DatabaseService } = require('../dist/database/database.service');
const { CatalogCache } = require('../dist/cache/catalog-cache');
const { loadConfiguration } = require('../dist/config/backend.config');

async function main() {
  const url = new URL(process.env.PERF_DATABASE_URL ?? '');
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || !['127.0.0.1', 'localhost'].includes(url.hostname) ||
    !/^\/sobatnira_perf_[a-z0-9_]+$/.test(url.pathname)) throw new Error('Use a disposable local sobatnira_perf_* database');
  const count = Number(process.env.PERF_CATALOG_ROWS ?? 20000);
  if (!Number.isSafeInteger(count) || count < 1000 || count > 100000) throw new Error('PERF_CATALOG_ROWS must be 1000..100000');
  process.env.DATABASE_URL = url.href; process.env.NODE_ENV = 'test';
  process.env.DOCUMENT_WORKER_ENABLED = 'false'; process.env.REPORT_EXPORT_ENABLED = 'false';
  const redis = await redisFixture(); const f = await intakeFixture(); let cache;
  try {
    const db = f.client;
    await db.query(`INSERT INTO sobatnira.suppliers(tenant_id,name)
      SELECT $1,'Benchmark supplier '||lpad(n::text,6,'0') FROM generate_series(1,$2) n`, [f.ids.tenant, count]);
    await db.query("INSERT INTO sobatnira.suppliers(tenant_id,name) VALUES($1,'Synthetic !_% percent')", [f.ids.tenant]);
    await db.query('ANALYZE sobatnira.suppliers');
    let captured;
    const capture = { query: async (sql, args) => { captured = { sql, args }; return db.query(sql, args); } };
    const repository = new SuppliersRepository(capture);
    const access = { userId: f.ids.admin, tenantId: f.ids.tenant, factoryId: f.ids.factory, role: 'admin' };
    const queries = [];
    for (const q of ['Benchmark supplier', '019999', '%', '_', '!']) {
      await repository.list(access, { q, limit: 20, offset: 0 }); queries.push({ name: q, ...captured });
    }
    const literal = `lower(s.name) LIKE ('%'||replace(replace(replace(lower($4),'!','!!'),'%','!%'),'_','!_')||'%') ESCAPE '!'`;
    const rewritten = queries.map(query => ({ ...query, sql: query.sql.replace('strpos(lower(s.name), lower($4)) > 0', literal) }));
    assert.notEqual(rewritten[0].sql, queries[0].sql);
    for (let n = 0; n < queries.length; n++) assert.deepEqual((await db.query(queries[n].sql, queries[n].args)).rows,
      (await db.query(rewritten[n].sql, rewritten[n].args)).rows);
    const results = [];
    async function sample(phase, choices) {
      for (const query of choices) {
        const timings = []; let plan;
        for (let n = 0; n < 5; n++) { const start = performance.now(); await db.query(query.sql, query.args); timings.push(performance.now() - start); }
        plan = (await db.query('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + query.sql, query.args)).rows[0]['QUERY PLAN'];
        timings.sort((a, b) => a - b); results.push({ phase, name: query.name, medianMs: timings[2], timings, plan });
      }
    }
    const writes = [
      { name: 'insert_500', sql: `INSERT INTO sobatnira.suppliers(tenant_id,name) SELECT $1,'Benchmark write '||n FROM generate_series(1,500) n`, args: [f.ids.tenant] },
      { name: 'update_500', sql: `UPDATE sobatnira.suppliers SET updated_at=clock_timestamp() WHERE id IN
        (SELECT id FROM sobatnira.suppliers WHERE tenant_id=$1 ORDER BY id LIMIT 500)`, args: [f.ids.tenant] },
    ];
    async function sampleWrites(phase) {
      for (const query of writes) {
        const timings = [];
        for (let n = 0; n < 5; n++) {
          await db.query('SAVEPOINT catalog_write'); const start = performance.now(); await db.query(query.sql, query.args); timings.push(performance.now() - start);
          await db.query('ROLLBACK TO SAVEPOINT catalog_write'); await db.query('RELEASE SAVEPOINT catalog_write');
        }
        timings.sort((a, b) => a - b); results.push({ phase, name: query.name, medianMs: timings[2], timings });
      }
    }
    await sample('strpos', queries); await sampleWrites('without_gin');
    await sample('literal_like', rewritten);
    await db.query('CREATE EXTENSION IF NOT EXISTS pg_trgm');
    await db.query('CREATE INDEX perf_suppliers_trgm_idx ON sobatnira.suppliers USING gin(lower(name) gin_trgm_ops)');
    const indexBytes = (await db.query("SELECT pg_relation_size('sobatnira.perf_suppliers_trgm_idx') AS bytes")).rows[0].bytes;
    await sample('literal_like_gin', rewritten); await sampleWrites('with_gin');

    cache = new CatalogCache(loadConfiguration({ envFile: false, env: { NODE_ENV: 'test', DATABASE_URL: url.href,
      REDIS_URL: redis.url, CATALOG_CACHE_ENABLED: 'true', CATALOG_CACHE_TIMEOUT_MS: '1000' } }), f.app.get(DatabaseService));
    const catalog = f.app.get(SuppliersRepository), query = { q: 'Benchmark supplier', limit: 20, offset: 0 };
    const start = performance.now(); const cold = await cache.read(access, 'suppliers', query, () => catalog.list(access, query));
    const coldMs = performance.now() - start, warm = [];
    for (let n = 0; n < 5; n++) {
      const started = performance.now(); const value = await cache.read(access, 'suppliers', query, () => catalog.list(access, query)); warm.push(performance.now() - started);
      assert.deepEqual(JSON.parse(JSON.stringify(value)), JSON.parse(JSON.stringify(cold)));
    }
    warm.sort((a, b) => a - b);
    const output = resolve(__dirname, '../../../.tmp/performance/catalog-query-profile.json');
    await mkdir(resolve(output, '..'), { recursive: true });
    const summary = { synthetic: true, rows: count, indexBytes,
      note: 'Five warm single-client samples. Redis is a local protocol fixture, not a real server/provider. Data, extension and candidate index rolled back. No HTTP/Auth/network p95.',
      cache: { coldMs, warmMedianMs: warm[2], warm, stats: cache.statistics() }, results };
    await writeFile(output, JSON.stringify(summary, null, 2));
    console.log(JSON.stringify({ output, rows: count, indexBytes, cache: summary.cache,
      results: results.map(({ phase, name, medianMs }) => ({ phase, name, medianMs })) }));
  } finally { await cache?.onModuleDestroy(); await f.close(); await redis.close(); }
}
main().catch(() => { console.error('Catalog profiling failed; inspect disposable database, migrations, extension support and connectivity.'); process.exitCode = 1; });
