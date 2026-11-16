const assert = require('node:assert/strict');
const test = require('node:test');
const { BadRequestException, NotFoundException } = require('@nestjs/common');
const { decimal, parseSyntheticRequest, parseDraftUpdate, parseRevisionAction, parseDocumentQuery, parseStockQuery, completeFields } = require('../dist/documents/intake.dto');
const { syntheticIntake } = require('../dist/documents/synthetic-intake.fixture');
const { IntakeService } = require('../dist/documents/intake.service');
const id = '40000000-0000-4000-8000-000000000001';

test('decimal quantities preserve precision without binary floating-point or rounding', () => {
  assert.equal(decimal('1250.000000000000000001', 'weight'), '1250.000000000000000001');
  assert.equal(decimal('0.000000000000000001', 'weight'), '0.000000000000000001');
  assert.equal(decimal('1250.5000', 'weight'), '1250.5');
  for (const value of [1250, 0.1, '0', '0.000', '-1', 'NaN', 'Infinity', '1e3', '1,250', '01', '9'.repeat(65)]) {
    assert.throws(() => decimal(value, 'weight'), BadRequestException);
  }
});

test('synthetic creation requires stable source request and lot IDs and forbids supplied state/weight', () => {
  assert.deepEqual(parseSyntheticRequest({ lotId: id, requestId: id }), { lotId: id, requestId: id });
  for (const input of [{ lotId: id }, { lotId: 'invalid', requestId: id }, { lotId: id, requestId: id, status: 'approved' },
    { lotId: id, requestId: id, netWeightKg: '100' }, { lotId: id, requestId: id, synthetic: false }]) {
    assert.throws(() => parseSyntheticRequest(input), BadRequestException);
  }
});

test('draft changes require an expected revision and reason and permit incomplete extraction fields', () => {
  const change = parseDraftUpdate({ expectedRevision: 1, reason: ' Koreksi sintetis ', changes: { netWeightKg: '1250.5000', brix: null } });
  assert.deepEqual(change, { expectedRevision: 1, reason: 'Koreksi sintetis', changes: { netWeightKg: '1250.5', brix: null } });
  assert.equal(parseDraftUpdate({ expectedRevision: 1, reason: 'Belum terbaca', changes: { netWeightKg: null } }).changes.netWeightKg, null);
  for (const changes of [{}, { supplierId: id }, { status: 'approved' }, { netWeightKg: 1250 }, { brix: '100.00001' }, { brix: '-1' }, { occurredAt: '2026-02-30T00:00:00Z' }]) {
    assert.throws(() => parseDraftUpdate({ expectedRevision: 1, reason: 'Synthetic', changes }), BadRequestException);
  }
  assert.throws(() => parseDraftUpdate({ expectedRevision: 1, changes: { brix: null } }), BadRequestException);
});

test('confirmation and approval refuse missing required fields but allow unknown optional Brix', () => {
  const fields = syntheticIntake({ id, supplierId: id, receivedAt: new Date('2026-11-16T01:00:00Z') });
  assert.equal(completeFields({ ...fields, brix: null }).netWeightKg, '1250');
  for (const key of ['netWeightKg', 'occurredAt', 'caneTypeCode']) {
    assert.throws(() => completeFields({ ...fields, [key]: null }), BadRequestException);
  }
  for (const value of [0, -1, 1.5, '1', 2147483647]) {
    assert.throws(() => parseRevisionAction({ expectedRevision: value }), BadRequestException);
  }
  assert.equal(parseRevisionAction({ expectedRevision: 2 }), 2);
  assert.throws(() => parseRevisionAction({ expectedRevision: 2, approvedBy: id }), BadRequestException);
});

test('queue and stock filters reject unsupported states and keep synthetic balances opt-in', () => {
  assert.deepEqual(parseDocumentQuery({ status: 'awaiting_validation', lotId: id, limit: '1' }), {
    status: 'awaiting_validation', lotId: id, limit: 1, offset: 0,
  });
  assert.throws(() => parseDocumentQuery({ status: 'ready' }), BadRequestException);
  assert.deepEqual(parseStockQuery({}), { synthetic: false });
  assert.deepEqual(parseStockQuery({ synthetic: 'true', lotId: id }), { synthetic: true, lotId: id });
  assert.throws(() => parseStockQuery({ synthetic: 'yes' }), BadRequestException);
});

test('synthetic creation and simulated confirmation are unavailable in production', () => {
  const service = new IntakeService({}, { environment: 'production' });
  assert.throws(() => service.createSynthetic({}, { lotId: id, requestId: id }), NotFoundException);
  assert.throws(() => service.confirmSynthetic({}, id, 1), NotFoundException);
});
