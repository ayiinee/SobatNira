const assert = require('node:assert/strict');
const test = require('node:test');
const { BadRequestException } = require('@nestjs/common');
const { parseMillingUpdate, completeMillingFields } = require('../dist/milling/milling.dto');
const { syntheticMilling } = require('../dist/milling/synthetic-milling.fixture');
const { sumDecimals } = require('../dist/production/decimal');
const lotId = '40000000-0000-4000-8000-000000000001';
const fixture = () => syntheticMilling({ id: lotId, receivedAt: new Date('2026-11-16T01:00:00Z') });
const update = (changes) => parseMillingUpdate({ expectedRevision: 1, reason: 'Synthetic correction', changes });

test('combined result quantities remain exact and never accept a client-supplied cane debit', () => {
  assert.equal(update({ juiceProducedLiters: '250.000000000000000001' }).changes.juiceProducedLiters, '250.000000000000000001');
  assert.equal(sumDecimals(['0.000000000000000001', '114.999999999999999999', '115']), '230');
});

test('milling rejects forged scope, invalid units and any supplied cane consumption', () => {
  for (const changes of [{}, { tenantId: lotId }, { supplierId: lotId }, { quantityKg: '1000' },
    { caneConsumedKg: '1000' }, { caneConsumedKg: '-1' }, { caneConsumedKg: 1000 },
    { juiceProducedLiters: '-1' }, { juiceProducedLiters: '1e2' }]) {
    assert.throws(() => parseMillingUpdate({ expectedRevision: 1, reason: 'Synthetic', changes }), BadRequestException);
  }
  assert.throws(() => parseMillingUpdate({ expectedRevision: 1, changes: { caneConsumedKg: '1' } }), BadRequestException);
});

test('milling can preserve incomplete extraction while confirmation requires complete measured fields', () => {
  assert.equal(parseMillingUpdate({ expectedRevision: 1, reason: 'Unknown volume', changes: { juiceProducedLiters: null } }).changes.juiceProducedLiters, null);
  const fields = syntheticMilling({ id: lotId, receivedAt: new Date('2026-11-16T01:00:00Z') });
  for (const key of ['occurredAt', 'reportedBatches', 'juiceProducedLiters']) {
    assert.throws(() => completeMillingFields({ ...fields, [key]: null }), BadRequestException);
  }
  assert.throws(() => completeMillingFields({ ...fields, juiceProducedLiters: '229.999999999999999999' }), BadRequestException);
  assert.equal(completeMillingFields({ ...fields, juiceProducedLiters: '0', reportedBatches: [] }).juiceProducedLiters, '0');
});

test('synthetic milling declares illustrative input and output without deriving a yield formula', () => {
  const fields = syntheticMilling({ id: lotId, receivedAt: new Date('2026-11-16T01:00:00Z') });
  assert.equal(fields.occurredAt, '2026-11-16T02:00:00.000Z');
  assert.equal(fields.juiceProducedLiters, '250');
  assert.equal(fields.reportedBatches.length, 2);
  assert.ok(!('caneConsumedKg' in fields));
});

test('three reusable woks permit more than three reported batches and track mixed contributions', () => {
  const rows = Array.from({ length: 5 }, (_, index) => ({
    batchReference: `BATCH-${index}`, wokNumber: index % 3 + 1, totalJuiceLiters: '115', sourceJuiceLiters: '100',
  }));
  assert.equal(completeMillingFields({ ...fixture(), juiceProducedLiters: '500', reportedBatches: rows }).reportedBatches.length, 5);
  const mixed = { batchReference: 'MIXED', wokNumber: 3, totalJuiceLiters: '100', sourceJuiceLiters: '20' };
  assert.equal(update({ reportedBatches: [mixed] }).changes.reportedBatches[0].sourceJuiceLiters, '20');
  for (const changes of [{ wokNumber: 4 }, { wokNumber: '1' }, { totalJuiceLiters: '115.000000000000000001' },
    { sourceJuiceLiters: '101' }, { sourceJuiceLiters: '0' }, { tenantId: lotId }]) {
    assert.throws(() => update({ reportedBatches: [{ ...mixed, ...changes }] }), BadRequestException);
  }
  assert.throws(() => update({ reportedBatches: [mixed, mixed] }), BadRequestException);
});
