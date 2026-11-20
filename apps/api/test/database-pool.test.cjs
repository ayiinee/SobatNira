const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfiguration } = require('../dist/config/backend.config');
const { databasePoolOptions, PoolMeasurements } = require('../dist/database/pool');

test('pool config validates bounds and gives both pools explicit limits and server-owned timeout', () => {
  const config = loadConfiguration({ envFile: false, env: { DATABASE_URL: 'postgres://postgres@127.0.0.1/fixture',
    DB_POOL_BUSINESS_MAX: '2', DB_POOL_DOCUMENTS_MAX: '3', DB_STATEMENT_TIMEOUT_MS: '1000' } });
  const business = databasePoolOptions(config, 'business'), documents = databasePoolOptions(config, 'documents');
  assert.equal(business.max, 2); assert.equal(documents.max, 3);
  assert.equal(business.statement_timeout, 1000); assert.equal(business.query_timeout, 2000);
  assert.equal(business.application_name, 'sobatnira-business'); assert.equal(documents.application_name, 'sobatnira-documents');
  for (const env of [{ DB_POOL_BUSINESS_MAX: '0' }, { DB_POOL_DOCUMENTS_MAX: '101' },
    { DB_POOL_IDLE_MS: 'abc' }, { DB_POOL_CONNECT_MS: '99' }, { DB_STATEMENT_TIMEOUT_MS: '0' }]) {
    assert.throws(() => loadConfiguration({ envFile: false, env }), /Konfigurasi/);
  }
});

test('pool telemetry counts acquisition failures without leaking SQL or connection details', async () => {
  const m = new PoolMeasurements();
  await assert.rejects(m.connect({ connect: async () => { throw new Error('secret'); } }), /secret/);
  const stats = m.snapshot({ totalCount: 2, idleCount: 1, waitingCount: 3 });
  assert.equal(stats.acquisitionErrors, 1); assert.equal(stats.acquired, 0); assert.equal(stats.waiting, 3);
  assert.ok(stats.waitTotalMs >= 0); assert.ok(!JSON.stringify(stats).includes('secret'));
});
