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

export function parseReservation(input: unknown) {
  const row = object(input, ['requestId', 'batchId', 'quantityMl', 'synthetic']);
  return {
    requestId: uuid(row.requestId, 'requestId'),
    batchId: uuid(row.batchId, 'batchId'),
    quantityMl: decimal(row.quantityMl, 'quantityMl'),
    synthetic: synthetic(row.synthetic),
  };
}
