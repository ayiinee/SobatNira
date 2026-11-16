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
