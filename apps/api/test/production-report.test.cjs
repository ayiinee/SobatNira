const test = require('node:test');
const assert = require('node:assert/strict');
const { contributionRanking, productionReport } = require('../dist/production/production-report');
const { Batches } = require('../dist/production/batches');
const { boundedReport, REPORT_MAX_BYTES } = require('../dist/production/report-limits');

test('report limits reject overlong periods, excessive rows and bytes without returning partial totals', async () => {
  const access = { userId:'user',tenantId:'tenant',factoryId:'factory' };
  let calls=0;
  const service=new Batches({query:async(sql)=>{if(sql.startsWith('WITH RECURSIVE')) return {rows:[]}; calls++;return {rows:Array.from({length:101},(_,n)=>lot(String(n)))}}},{});
  for (const query of [{from:'2024-01-01T00:00:00Z',before:'2026-01-01T00:00:00Z'},
    {view:'unknown'}, {limit:'1'}, {view:'page',limit:'0'}]) {
    await assert.rejects(service.productionReport(access,query),e=>e.getStatus()===400);
  }
  assert.equal(calls,0);
  await assert.rejects(service.productionReport(access,{}),e=>e.getStatus()===400 && /ekspor/.test(e.message));
  assert.throws(()=>boundedReport({text:'x'.repeat(REPORT_MAX_BYTES)}),e=>e.getStatus()===400);
  assert.equal(boundedReport({text:'valid'}).text,'valid');
  const dense=new Batches({query:async(sql)=>({rows:sql.startsWith('WITH RECURSIVE')?[]:[lot('dense',null,Array(1001).fill({}))]})},{});
  await assert.rejects(dense.productionReport(access,{}),e=>e.getStatus()===400 && /1000/.test(e.message));
  await assert.rejects(dense.report(access,{},true),e=>e.getStatus()===400 && /1000/.test(e.message));
});

const lot = (id, calculation = null, batches = []) => ({ lotId: id, code: 'DUPLICATE',
  supplier: 'Synthetic', receivedAt: '2026-11-19T00:00:00Z', caneNetKg: '1250.01',
  caneType: null, juiceLiters: null, calculation, batches });
const calculation = { finalSugarKg: '0.000001', productionValueRupiah: '9007199254740993',
  totalCostRupiah: '9007199254740994', productionMarginRupiah: '-1' };
const batch = { id: 'batch', code: 'B1', grades: [
  { code: 'A', weightKg: '0.000001', pricePerKgRupiah: '9007199254740993' },
] };

test('report keeps exact money, receipt-only lots, grade snapshot prices and unique lot identities', () => {
  const report = productionReport([lot('one', calculation, [batch]), lot('two')]);
  assert.equal(report.items.length, 2);
  assert.equal(report.totals.lotCount, 2);
  assert.equal(report.totals.producedLotCount, 1);
  assert.equal(report.totals.batchCount, 1);
  assert.equal(report.totals.caneNetKg, '2500.02');
  assert.equal(report.totals.finalSugarKg, '0.000001');
  assert.equal(report.totals.productionValueRupiah, '9007199254740993');
  assert.equal(report.totals.productionMarginRupiah, '-1');
  assert.equal(report.grades[0].exactValueRupiah, '9007199254.740993');
  assert.equal(report.items[0].batches[0].exactValueRupiah, '9007199254.740993');
  assert.equal(report.items[1].calculation, null);
  assert.equal(report.items[0].batches[0].productionMarginRupiah, undefined);
});

test('empty report has explicit zero totals and no fabricated results', () => {
  const result = productionReport([]);
  assert.equal(result.totals.productionMarginRupiah, '0');
  assert.equal(result.totals.finalSugarKg, '0');
  assert.deepEqual(result.items, []);
  assert.deepEqual(result.grades, []);
});

test('contribution ranking retains exact sums and ties, and withholds incomplete results', () => {
  const consumed = (originLotId, quantityMl) => ({ originLotId, lotCode: originLotId, quantityMl });
  const first = { ...batch, id: 'first', quantityMl: '0.3',
    consumedByOrigin: [consumed('A', '0.1'), consumed('B', '0.2')] };
  const second = { ...batch, id: 'second', quantityMl: '0.1', consumedByOrigin: [consumed('A', '0.1')] };
  const ranking = contributionRanking([lot('one', calculation, [first, second])]);
  assert.equal(ranking.status, 'complete');
  assert.equal(ranking.leadingCount, 2);
  assert.deepEqual(ranking.leaders, [consumed('A', '0.2'), consumed('B', '0.2')]);
  const incomplete = contributionRanking([lot('one', calculation, [first, { ...second, consumedByOrigin: [] }])]);
  assert.equal(incomplete.status, 'incomplete');
  assert.deepEqual(incomplete.incompleteBatchIds, ['second']);
  assert.deepEqual(incomplete.leaders, []);
  assert.equal(contributionRanking([lot('one')]).status, 'no_data');
});

test('report validates period and category before accessing database, and binds scope/time values', async () => {
  const calls = [];
  const service = new Batches({ query: async (sql, values) => {
    calls.push({ sql, values }); return { rows: [] };
  } }, {});
  const access = { userId: 'user', tenantId: 'tenant', factoryId: 'factory' };
  for (const query of [{ synthetic: 'yes' }, { from: '2026-11-20T00:00:00Z', before: '2026-11-19T00:00:00Z' }, { fake: true }]) {
    await assert.rejects(() => service.productionReport(access, query), e => e.getStatus() === 400);
  }
  assert.equal(calls.length, 0);
  const result = await service.productionReport(access, { synthetic: 'true', from: '2026-11-19T00:00:00+07:00', before: '2026-11-20T00:00:00+07:00' });
  assert.equal(result.synthetic, true);
  const reportCall=calls.find(c=>c.sql.includes('JOIN authorized_scope'));
  assert.deepEqual(reportCall.values.slice(0, 4), ['user', 'tenant', 'factory', true]);
  assert.match(reportCall.sql, /pb.status='approved'/);
  assert.match(reportCall.sql, /l.received_at < \$6/);
  assert.match(reportCall.sql, /JOIN authorized_scope/);
});
