const test = require('node:test');
const assert = require('node:assert/strict');
const { setTimeout: delay } = require('node:timers/promises');
const { loadConfiguration } = require('../../dist/config/backend.config');
const { DatabaseService } = require('../../dist/database/database.service');
const { Database } = require('../../dist/documents/database');

test('one-slot pools expose contention, release on rollback and recover after server statement timeout', async () => {
  assert.ok(process.env.TEST_DATABASE_URL, 'Use an explicitly configured synthetic database');
  const url = new URL(process.env.TEST_DATABASE_URL);
  assert.ok(['localhost', '127.0.0.1'].includes(url.hostname), 'Pool test is local only');
  const settings = { ...process.env, DATABASE_URL: process.env.TEST_DATABASE_URL, DB_POOL_BUSINESS_MAX: '1',
    DB_POOL_DOCUMENTS_MAX: '1', DB_STATEMENT_TIMEOUT_MS: '200', DB_POOL_CONNECT_MS: '1000' };
  const config = loadConfiguration({ envFile: false, env: settings });
  const business = new DatabaseService(config);
  const before = Object.fromEntries(Object.keys(settings).filter(key => key.startsWith('DB_') || key === 'DATABASE_URL').map(key => [key, process.env[key]]));
  for (const key of Object.keys(before)) process.env[key] = settings[key];
  const documents = new Database();
  try {
    for (const service of [business, documents]) {
      let unlock, held;
      const entered = new Promise(resolve => { held = resolve; });
      const gate = new Promise(resolve => { unlock = resolve; });
      const first = service.transaction(async db => { await db.query('SELECT 1', []); held(); await gate; throw new Error('fixture rollback'); });
      first.catch(() => {});
      await entered;
      const queued = service.query('SELECT 2 AS value', []);
      try {
        for (let n = 0; n < 50 && service.poolStatistics().waiting === 0; n++) await delay(5);
        assert.equal(service.poolStatistics().waiting, 1);
        assert.equal(service.poolStatistics().total, 1);
      } finally { unlock(); }
      await assert.rejects(first);
      assert.equal((await queued).rows[0].value, 2);
      await assert.rejects(service.query('SELECT pg_sleep(1)', []));
      assert.equal((await service.query('SELECT 3 AS value', [])).rows[0].value, 3);
      const stats = service.poolStatistics();
      assert.equal(stats.waiting, 0); assert.equal(stats.transactions, 1); assert.ok(stats.acquired >= 4);
      assert.ok(stats.waitTotalMs > 0); assert.ok(stats.transactionTotalMs > 0);
      assert.equal(stats.transactionFailures, 1); assert.equal(stats.directQueryErrors, 1);
      assert.equal(stats.directQueryDurationMs.count, 3); assert.equal(stats.transactionDurationMs.count, 1);
      assert.equal(stats.waitDurationMs.count, 4);
    }
  } finally {
    await business.onModuleDestroy(); await documents.onModuleDestroy();
    for (const [key, value] of Object.entries(before)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; }
  }
});
