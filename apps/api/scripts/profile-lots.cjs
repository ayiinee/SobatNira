// Local, disposable, synthetic data only. Every inserted row is rolled back.
const { mkdir, writeFile } = require('node:fs/promises');
const { resolve } = require('node:path');
const { intakeFixture } = require('../test/integration/intake-fixture.cjs');
const { LotsRepository } = require('../dist/lots/lots.repository');

async function main() {
  const url = new URL(process.env.PERF_DATABASE_URL ?? '');
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
    !/^\/sobatnira_perf_[a-z0-9_]+$/.test(url.pathname)) {
    throw new Error('PERF_DATABASE_URL must name a disposable local sobatnira_perf_* database.');
  }
  const count = Number(process.env.PERF_LOTS ?? 20000);
  if (!Number.isSafeInteger(count) || count < 1000 || count > 100000) throw new Error('PERF_LOTS must be 1000..100000.');
  process.env.DATABASE_URL = url.toString();
  process.env.NODE_ENV = 'test';
  process.env.DOCUMENT_WORKER_ENABLED = 'false';
  process.env.REPORT_EXPORT_ENABLED = 'false';
  const fixture = await intakeFixture();
  try {
    const { client, ids } = fixture;
    await client.query(`INSERT INTO sobatnira.lots(tenant_id,factory_id,supplier_id,display_code,received_at)
      SELECT $1,$2,$3,'SYNTHETIC-PERF-'||n, timestamptz '2026-01-01T00:00:00Z'+n*interval '1 second'
      FROM generate_series(1,$4::int) n`, [ids.tenant, ids.factory, ids.supplier, count]);
    await client.query('ANALYZE sobatnira.lots');
    const offset = Math.floor(count * 0.8);
    const { rows: [boundary] } = await client.query(`SELECT id,
      to_char(received_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS time
      FROM sobatnira.lots WHERE tenant_id=$1 AND factory_id=$2
      ORDER BY received_at DESC,id LIMIT 1 OFFSET $3`, [ids.tenant, ids.factory, offset - 1]);
    const access = { userId: ids.admin, tenantId: ids.tenant, factoryId: ids.factory, role: 'admin' };
    const results = [];
    for (const [name, query] of [
      ['offset-first', { offset: 0 }], ['offset-deep', { offset }],
      ['cursor-first', { pagination: 'cursor' }],
      ['cursor-deep', { pagination: 'cursor', after: { receivedAt: boundary.time, id: boundary.id } }],
    ]) {
      let captured;
      const repository = new LotsRepository({ async query(sql, values) {
        captured = { sql, values }; return client.query(sql, values);
      } });
      const page = await repository.list(access, { limit: 50, offset: 0, includeSummary: true, ...query });
      const samples = [];
      let plan;
      for (let repeat = 0; repeat < 5; repeat++) {
        const result = await client.query('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + captured.sql, captured.values);
        plan = result.rows[0]['QUERY PLAN'][0];
        samples.push(plan['Execution Time']);
      }
      const sorted = [...samples].sort((a, b) => a - b);
      results.push({ name, returned: page.items.length, firstId: page.items[0]?.id,
        executionMs: samples, medianMs: sorted[2], plan });
    }
    if (results[1].firstId !== results[3].firstId) throw new Error('Deep page boundaries disagree.');
    const directory = resolve(__dirname, '../../../.tmp/performance');
    await mkdir(directory, { recursive: true });
    const file = resolve(directory, 'lots-query-profile.json');
    await writeFile(file, JSON.stringify({ synthetic: true, createdAt: new Date().toISOString(), count,
      note: 'Single client, five warm-query samples; excludes HTTP, auth network and realistic receipt/batch density.', results }, null, 2));
    for (const result of results) console.log(`${result.name}: median ${result.medianMs} ms; rows ${result.returned}`);
    console.log(`Plans: ${file}`);
  } finally { await fixture.close(); }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
