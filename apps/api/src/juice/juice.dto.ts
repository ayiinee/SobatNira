import { BadRequestException } from '@nestjs/common';
import { parseStockQuery } from '../documents/intake.dto';
import { decimal } from '../production/decimal';
import { object, parsePage, text, uuid } from '../production/production.dto';

function synthetic(input: unknown): boolean {
  if (input !== undefined && typeof input !== 'boolean') throw new BadRequestException('synthetic harus boolean.');
  return input === true;
}

export function parseAvailability(input: unknown) {
  return parseStockQuery(object(input, ['synthetic'])).synthetic;
}

export function parseClosure(input: unknown) {
  return synthetic(object(input ?? {}, ['synthetic']).synthetic);
}

export function parseReopen(input: unknown) {
  const row = object(input, ['closureId', 'reason', 'synthetic']);
  return {
    closureId: uuid(row.closureId, 'closureId'),
    reason: text(row.reason, 'reason', 500),
    synthetic: synthetic(row.synthetic),
  };
}

export function parseClosureHistory(input: unknown) {
  const { synthetic: category, ...page } = object(input, ['synthetic', 'limit', 'offset']);
  return { synthetic: parseAvailability({ synthetic: category }), page: parsePage(page) };
}

export function parseReservation(input: unknown) {
  const row = object(input, ['requestId', 'batchId', 'quantityMl', 'synthetic', 'originLotId']);
  return {
    requestId: uuid(row.requestId, 'requestId'),
    batchId: uuid(row.batchId, 'batchId'),
    quantityMl: decimal(row.quantityMl, 'quantityMl'),
    synthetic: synthetic(row.synthetic),
    originLotId: row.originLotId === undefined ? undefined : uuid(row.originLotId, 'originLotId'),
  };
}

export function parseTransfer(input: unknown, fromLotId: string) {
  const row = object(input, ['requestId', 'toLotId', 'originLotId', 'quantityMl', 'synthetic']);
  const toLotId = uuid(row.toLotId, 'toLotId');
  if (toLotId === fromLotId) throw new BadRequestException('Kloter asal dan tujuan harus berbeda.');
  return {
    requestId: uuid(row.requestId, 'requestId'), fromLotId, toLotId,
    originLotId: row.originLotId === undefined ? fromLotId : uuid(row.originLotId, 'originLotId'),
    quantityMl: decimal(row.quantityMl, 'quantityMl'), synthetic: synthetic(row.synthetic),
  };
}
