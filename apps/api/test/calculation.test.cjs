const assert = require('node:assert/strict');
const test = require('node:test');
const { calculateProductionPreview: calculate } = require('../dist/production/calculation');
const { calculateProductionRecapPreview: recap } = require('../dist/production/calculation');
const { createApplication } = require('../dist/application');
const { AccessRepository } = require('../dist/auth/access.repository');
const { SupabaseAuthService } = require('../dist/auth/supabase-auth.service');
const input = () => ({ caneNetKg: '1500', caneCostRupiah: '900000', operationalCostRupiah: '100000', ingredientCostRupiah: '20000', otherCostRupiah: '0', rounding: 'HALF_UP', grades: [
  { code: 'A', weightKg: '30', pricePerKgRupiah: '20000' },
  { code: 'B', weightKg: '30', pricePerKgRupiah: '18000' },
  { code: 'C', weightKg: '30', pricePerKgRupiah: '15000' },
] });
test('golden production calculation and negative margin use exact amounts', () => {
  const result = calculate(input());
  assert.equal(result.finalSugarKg, '90');
  assert.equal(result.rendemenPercent, '6.00');
  assert.equal(result.productionValueRupiah, '1590000');
  assert.equal(result.totalCostRupiah, '1020000');
  assert.equal(result.productionMarginRupiah, '570000');
  assert.equal(calculate({ ...input(), otherCostRupiah: '700000' }).productionMarginRupiah, '-130000');
  assert.equal(result.persisted, false);
});
test('fractional kg and money above JS safe integer are exact; round only the total', () => {
  const body = { ...input(), grades: [{ code: 'A', weightKg: '0.5', pricePerKgRupiah: '1' }, { code: 'B', weightKg: '0.5', pricePerKgRupiah: '1' }] };
  assert.equal(calculate(body).productionValueRupiah, '1');
  assert.equal(calculate({ ...body, grades: [{ code: 'A', weightKg: '1', pricePerKgRupiah: '9007199254740993' }] }).productionValueRupiah, '9007199254740993');
});
test('reject ambiguous inputs, extra fields, duplicate grades, zero denominator and excessive precision', () => {
  for (const changes of [{ caneNetKg: '0' }, { caneNetKg: 1500 }, { caneNetKg: '1,5' }, { caneNetKg: '1e3' }, { caneNetKg: '1.0000001' }, { caneCostRupiah: '-1' }, { rounding: undefined }, { tenantId: 'forged' }, { grades: [] }, { grades: [input().grades[0], { ...input().grades[0], code: 'a' }] }]) {
    assert.throws(() => calculate({ ...input(), ...changes }), error => error.getStatus() === 400);
  }
});
test('recap weights yield by cane, sums losses correctly and rejects duplicate lots', () => {
  const records = [
    { lotCode: 'K1', calculation: { ...input(), caneNetKg: '1000', grades: [{ code: 'A', weightKg: '100', pricePerKgRupiah: '20000' }] } },
    { lotCode: 'K2', calculation: { ...input(), caneNetKg: '9000', grades: [{ code: 'A', weightKg: '450', pricePerKgRupiah: '20000' }] } },
  ];
  const result = recap({ records });
  assert.equal(result.totals.caneNetKg, '10000');
  assert.equal(result.totals.finalSugarKg, '550');
  assert.equal(result.totals.rendemenPercent, '5.50');
  assert.equal(result.totals.productionValueRupiah, '11000000');
  assert.equal(result.totals.totalCostRupiah, '2040000');
  assert.equal(result.totals.productionMarginRupiah, '8960000');
  assert.throws(() => recap({ records: [records[0], records[0]] }), error => error.getStatus() === 400);
  assert.throws(() => recap({ records: [] }), error => error.getStatus() === 400);
});
test('preview HTTP enforces authentication and factory scope', async t => {
  const app = await createApplication({ envFile: false, env: { LOG_LEVEL: 'silent' } });
  t.after(() => app.close());
  const tenantId = '10000000-0000-4000-8000-000000000001';
  const factoryId = '20000000-0000-4000-8000-000000000001';
  app.get(SupabaseAuthService).verifyAccessToken = async () => ({ id: '30000000-0000-4000-8000-000000000001' });
  app.get(AccessRepository).findFactoryAccess = async (_user, tenant, factory) => tenant === tenantId && factory === factoryId ? { tenantId, factoryId, userId: _user, role: 'admin' } : undefined;
  await app.listen(0, '127.0.0.1');
  const url = `http://127.0.0.1:${app.getHttpServer().address().port}/tenants/${tenantId}/factories/${factoryId}/production/calculation-preview`;
  const send = (target, auth = true) => fetch(target, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(auth ? { Authorization: 'Bearer synthetic' } : {}) }, body: JSON.stringify(input()) });
  assert.equal((await send(url, false)).status, 401);
  assert.equal((await send(url.replace(factoryId, '20000000-0000-4000-8000-000000000002'))).status, 403);
  const response = await send(url);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).productionMarginRupiah, '570000');
  const recapUrl = url.replace('calculation-preview', 'recap-preview');
  const recapResponse = await fetch(recapUrl, { method: 'POST', headers: { Authorization: 'Bearer synthetic', 'Content-Type': 'application/json' }, body: JSON.stringify({ records: [{ lotCode: 'K1', calculation: input() }] }) });
  assert.equal(recapResponse.status, 200);
  assert.equal((await recapResponse.json()).totals.productionMarginRupiah, '570000');
});
