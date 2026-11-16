import { BadRequestException } from '@nestjs/common';
import { parseStockQuery } from '../documents/intake.dto';
import { decimal } from '../production/decimal';
import { object, uuid } from '../production/production.dto';

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
