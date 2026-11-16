const assert = require('node:assert/strict');
const test = require('node:test');
const { NestFactory } = require('@nestjs/core');
const { AppModule } = require('../dist/app.module.js');

const headers = { 'x-dev-user-id': 'u1', 'x-dev-tenant-id': 'tenant-demo', 'x-dev-factory-id': 'factory-demo', 'x-dev-role': 'owner' };
let app;
let url;
test.before(async () => { app = await NestFactory.create(AppModule, { logger: false }); await app.listen(0, '127.0.0.1'); url = await app.getUrl(); });
test.after(async () => app.close());
const request = (path, init = {}) => fetch(`${url}${path}`, { ...init, headers: { ...headers, ...(init.headers ?? {}) } });
const json = (value) => ({ headers: { 'content-type': 'application/json' }, body: JSON.stringify(value) });

test('lists synthetic normal and mixed batches with traceability proportions', async () => {
  const list = await request('/batches');
  assert.equal(list.status, 200);
  assert.equal((await list.json()).length, 5);
  const trace = await request('/batches/batch-mixed/traceability');
  assert.equal(trace.status, 200);
  assert.deepEqual((await trace.json()).sources.map((source) => source.proportion), [0.2, 0.8]);
});

test('enforces 115L cap, stage order, duplicate grading and rework separation', async () => {
  let response = await request('/batches/batch-normal/contributions', { method: 'POST', ...json({ kloterId: 'kloter-extra', volumeMl: 20000 }), headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' } });
  assert.equal(response.status, 422);
  response = await request('/batches/batch-mixed/grading', { method: 'POST', ...json({ gradeCode: 'A' }), headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' } });
  assert.equal(response.status, 409);
  response = await request('/batches/batch-graded/grading', { method: 'POST', ...json({ gradeCode: 'B' }), headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' } });
  assert.equal(response.status, 409);
  response = await request('/batches/batch-rework/traceability');
  assert.equal(response.status, 200);
  assert.equal((await response.json()).official.sugarWeightGrams, 900000);
});

test('rejects cross-factory access and idempotency replay', async () => {
  let response = await request('/batches/batch-normal', { headers: { 'x-dev-factory-id': 'other-factory' } });
  assert.equal(response.status, 403);
  const body = json({ factoryId: 'factory-demo', kloterId: 'kloter-new', panId: 'pan-01', occurredAt: new Date().toISOString() });
  response = await request('/batches', { method: 'POST', ...body, headers: { ...body.headers, 'idempotency-key': 'create-once', 'x-dev-role': 'admin' } });
  assert.equal(response.status, 201);
  response = await request('/batches', { method: 'POST', ...body, headers: { ...body.headers, 'idempotency-key': 'create-once', 'x-dev-role': 'admin' } });
  assert.equal(response.status, 409);
});

test('exposes production masters, nira contract and closure check', async () => {
  let response = await request('/production-masters/grades');
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).map((item) => item.code), ['A', 'B']);
  response = await request('/production-masters/prices');
  assert.equal(response.status, 200);
  assert.equal((await response.json())[0].prices.A, 10000);
  response = await request('/production-masters/pans', { method: 'POST', headers: { 'content-type': 'application/json', 'x-dev-role': 'owner' }, body: JSON.stringify({ code: 'PAN-OWNER', name: 'Tidak boleh' }) });
  assert.equal(response.status, 403);
  response = await request('/batches/nira/kloter-999/availability');
  assert.equal(response.status, 200);
  assert.equal((await response.json()).synthetic, true);
  response = await request('/batches/closure-check/kloter-101');
  assert.equal(response.status, 200);
  assert.equal((await response.json()).ready, false);
});

test('nira reservation rejects reuse beyond synthetic source balance', async () => {
  const create = await request('/batches', { method: 'POST', headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' }, body: JSON.stringify({ factoryId: 'factory-demo', kloterId: 'kloter-reserve', panId: 'pan-01', occurredAt: new Date().toISOString() }) });
  assert.equal(create.status, 201);
  const batch = await create.json();
  let response = await request(`/batches/${batch.id}/contributions`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' }, body: JSON.stringify({ kloterId: 'kloter-reserve', volumeMl: 100000 }) });
  assert.equal(response.status, 201);
  const secondCreate = await request('/batches', { method: 'POST', headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' }, body: JSON.stringify({ factoryId: 'factory-demo', kloterId: 'kloter-reserve-2', panId: 'pan-01', occurredAt: new Date().toISOString() }) });
  const secondBatch = await secondCreate.json();
  response = await request(`/batches/${secondBatch.id}/contributions`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' }, body: JSON.stringify({ kloterId: 'kloter-reserve', volumeMl: 20000 }) });
  assert.equal(response.status, 409);
});

test('accepts Backend A lotId alias for batch nira contribution', async () => {
  const response = await request('/batches/batch-mixed/contributions', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' },
    body: JSON.stringify({ lotId: 'lot-a-alias', volumeMl: 1000 }),
  });
  assert.equal(response.status, 201);
  assert.equal((await response.json()).contributions.at(-1).kloterId, 'lot-a-alias');
});

test('tracks sugar stock and allocates mixed economics with exact rupiah totals', async () => {
  let response = await request('/stock/sugar?grade=A');
  assert.equal(response.status, 200);
  assert.equal((await response.json()).balances[0].weightGrams, 1200000);
  response = await request('/stock/sugar/movements', { method: 'POST', headers: { 'content-type': 'application/json', 'x-dev-role': 'admin', 'idempotency-key': 'stock-add-1' }, body: JSON.stringify({ gradeCode: 'A', deltaGrams: -100000, reason: 'BATCH_SALE', batchId: 'batch-graded' }) });
  assert.equal(response.status, 201);
  response = await request('/stock/sugar/movements', { method: 'POST', headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' }, body: JSON.stringify({ gradeCode: 'A', deltaGrams: -2000000, reason: 'OVERDRAW' }) });
  assert.equal(response.status, 409);
  response = await request('/batches/batch-graded/economics/allocation', { method: 'POST', headers: { 'content-type': 'application/json', 'x-dev-role': 'admin' }, body: JSON.stringify({ totalCostRupiah: 100001, totalRevenueRupiah: 150001 }) });
  assert.equal(response.status, 201);
  const result = await response.json();
  assert.equal(result.totals.marginRupiah, 50000);
  assert.equal(result.allocations.reduce((sum, item) => sum + item.costRupiah, 0), 100001);
});

test('serves scoped dashboard, analytics and CSV export', async () => {
  let response = await request('/dashboard/production');
  assert.equal(response.status, 200);
  const dashboard = await response.json();
  assert.equal(dashboard.batchCount >= 5, true);
  assert.equal(dashboard.officialSugarWeightGrams >= 1200000, true);
  response = await request('/analytics/production');
  assert.equal(response.status, 200);
  assert.equal((await response.json()).points.length >= 1, true);
  response = await request('/exports/batches.csv');
  assert.equal(response.status, 200);
  assert.match(await response.text(), /^batch_id,status,occurred_at,total_nira_ml,sugar_weight_grams,grade_code/);
});

test('records stock correction as separate audited movement', async () => {
  const headersWithKey = { 'content-type': 'application/json', 'x-dev-role': 'admin', 'idempotency-key': 'correction-1' };
  let response = await request('/stock/sugar/movements', { method: 'POST', headers: headersWithKey, body: JSON.stringify({ gradeCode: 'B', deltaGrams: -50000, reason: 'SALE' }) });
  assert.equal(response.status, 201);
  const original = await response.json();
  response = await request('/stock/sugar/corrections', { method: 'POST', headers: { ...headersWithKey, 'idempotency-key': 'correction-2' }, body: JSON.stringify({ gradeCode: 'B', deltaGrams: 50000, reason: 'FIX_SOURCE_DOC', correctionOfMovementId: original.movement.id }) });
  assert.equal(response.status, 201);
  assert.equal((await response.json()).movement.reason, 'CORRECTION_FIX_SOURCE_DOC');
});
