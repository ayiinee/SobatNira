const assert = require('node:assert/strict');
const test = require('node:test');
const { BadRequestException } = require('@nestjs/common');
const { parseSupplierInput, parseLotInput, parseSupplierQuery, parseLotQuery, timestamp } = require('../dist/production/production.dto');

const supplierId = '40000000-0000-4000-8000-000000000001';

test('supplier input accepts basic metadata and rejects scope/role injection or invalid fields', () => {
  assert.deepEqual(parseSupplierInput({ name: '  Pemasok Sintetis  ' }), { name: 'Pemasok Sintetis' });
  assert.deepEqual(parseSupplierInput({ isActive: false }, true), { isActive: false });
  for (const input of [null, [], {}, { name: '' }, { name: 123 }, { name: 'x\u0000' },
    { name: 'x'.repeat(201) }, { name: 'X', tenantId: supplierId }, { name: 'X', role: 'owner' }, { name: 'X', isActive: false }]) {
    assert.throws(() => parseSupplierInput(input), BadRequestException);
  }
  assert.throws(() => parseSupplierInput({ isActive: 'false' }, true), BadRequestException);
});

test('lot input requires a supplier and explicit event time, with an optional manual display code', () => {
  assert.deepEqual(parseLotInput({ supplierId, receivedAt: '2026-11-16T08:00:00+07:00', displayCode: ' DEMO-01 ' }), {
    supplierId, receivedAt: '2026-11-16T01:00:00.000Z', displayCode: 'DEMO-01',
  });
  assert.deepEqual(parseLotInput({ displayCode: null }, true), { displayCode: null });
  for (const input of [{ supplierId }, { receivedAt: '2026-11-16T01:00:00Z' },
    { supplierId: 'invalid', receivedAt: '2026-11-16T01:00:00Z' },
    { supplierId, receivedAt: '2026-11-16T01:00:00Z', netWeightKg: 1250 },
    { supplierId, receivedAt: '2026-11-16T01:00:00Z', factoryId: supplierId }]) {
    assert.throws(() => parseLotInput(input), BadRequestException);
  }
  assert.throws(() => parseLotInput({}, true), BadRequestException);
});

test('timestamps reject impossible dates and ambiguous local times', () => {
  for (const value of ['2026-02-30T08:00:00Z', '2025-02-29T08:00:00Z', '2026-11-16',
    '2026-11-16T08:00:00', '2026-11-16T24:00:00Z', '2026-11-16T08:60:00Z',
    '2026-11-16T08:00:00+15:00', '2026-11-16T08:00:00+14:01']) {
    assert.throws(() => timestamp(value, 'receivedAt'), BadRequestException, value);
  }
  assert.equal(timestamp('2024-02-29T08:00:00Z', 'receivedAt'), '2024-02-29T08:00:00.000Z');
});

test('list filters validate pagination, UUIDs and time bounds without accepting arbitrary fields', () => {
  assert.deepEqual(parseSupplierQuery({}), { limit: 20, offset: 0 });
  assert.deepEqual(parseSupplierQuery({ isActive: 'false', q: '%_', limit: '2', offset: '10' }), {
    limit: 2, offset: 10, q: '%_', isActive: false,
  });
  for (const input of [{ limit: '-1' }, { limit: '101' }, { offset: '1.5' }, { q: ['a', 'b'] }, { isActive: 'yes' }, { role: 'owner' }]) {
    assert.throws(() => parseSupplierQuery(input), BadRequestException);
  }
  assert.throws(() => parseLotQuery({ supplierId: 'invalid' }), BadRequestException);
  assert.throws(() => parseLotQuery({ receivedFrom: '2026-11-17T00:00:00Z', receivedBefore: '2026-11-16T00:00:00Z' }), BadRequestException);
});
