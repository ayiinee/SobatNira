const test = require('node:test');
const assert = require('node:assert/strict');
const { contributionRanking, productionReport } = require('../dist/production/production-report');
const { Batches } = require('../dist/production/batches');

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
  assert.deepEqual(calls[0].values.slice(0, 4), ['user', 'tenant', 'factory', true]);
  assert.match(calls[0].sql, /pb.status='approved'/);
  assert.match(calls[0].sql, /l.received_at < \$6/);
  assert.match(calls[0].sql, /JOIN authorized_scope/);
});
