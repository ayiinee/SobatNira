import { BadRequestException } from '@nestjs/common';
import { object, Pagination, parsePage, text, timestamp, uuid } from '../production/production.dto';
import { decimal } from '../production/decimal';
export { decimal } from '../production/decimal';

export interface IntakeFields {
  lotId: string;
  supplierId: string;
  occurredAt: string | null;
  caneTypeCode: string | null;
  netWeightKg: string | null;
  brix: string | null;
}
export interface SyntheticRequest { lotId: string; requestId: string }
export interface DraftUpdate {
  expectedRevision: number;
  reason: string;
  changes: Partial<Omit<IntakeFields, 'supplierId'>>;
}
export interface DocumentQuery extends Pagination { status?: string; lotId?: string }

function brix(input: unknown): string {
  const result = decimal(input, 'brix', true);
  const [integer, fraction] = result.split('.');
  if (BigInt(integer) > 100n || (integer === '100' && fraction)) throw new BadRequestException('brix harus berada pada rentang 0–100.');
  return result;
}

function caneCode(input: unknown): string {
  // Preserve the supplied code; the complete code catalogue remains a product decision.
  const code = text(input, 'caneTypeCode', 40);
  if (!/^[A-Za-z0-9_-]+$/.test(code)) throw new BadRequestException('caneTypeCode tidak valid.');
  return code;
}

export function expectedRevision(input: unknown): number {
  if (typeof input !== 'number' || !Number.isSafeInteger(input) || input < 1 || input > 2147483646) {
    throw new BadRequestException('expectedRevision harus berupa bilangan bulat positif.');
  }
  return input;
}

export function parseSyntheticRequest(input: unknown): SyntheticRequest {
  const body = object(input, ['lotId', 'requestId']);
  return { lotId: uuid(body.lotId, 'lotId'), requestId: uuid(body.requestId, 'requestId') };
}

export function parseDraftUpdate(input: unknown): DraftUpdate {
  const body = object(input, ['expectedRevision', 'reason', 'changes']);
  const changes = object(body.changes, ['lotId', 'occurredAt', 'caneTypeCode', 'netWeightKg', 'brix']);
  if (!Object.keys(changes).length) throw new BadRequestException('Minimal satu perubahan diperlukan.');
  const parsed: DraftUpdate['changes'] = {};
  if ('lotId' in changes) parsed.lotId = uuid(changes.lotId, 'lotId');
  if ('occurredAt' in changes) parsed.occurredAt = changes.occurredAt === null ? null : timestamp(changes.occurredAt, 'occurredAt');
  if ('caneTypeCode' in changes) parsed.caneTypeCode = changes.caneTypeCode === null ? null : caneCode(changes.caneTypeCode);
  if ('netWeightKg' in changes) parsed.netWeightKg = changes.netWeightKg === null ? null : decimal(changes.netWeightKg, 'netWeightKg');
  if ('brix' in changes) parsed.brix = changes.brix === null ? null : brix(changes.brix);
  return { expectedRevision: expectedRevision(body.expectedRevision), reason: text(body.reason, 'reason', 500), changes: parsed };
}

export function parseRevisionAction(input: unknown): number {
  return expectedRevision(object(input, ['expectedRevision']).expectedRevision);
}

export function completeFields(fields: IntakeFields): IntakeFields & { occurredAt: string; caneTypeCode: string; netWeightKg: string } {
  if (!fields.occurredAt || !fields.caneTypeCode || !fields.netWeightKg) {
    throw new BadRequestException('Lengkapi waktu kejadian, jenis tebu dan berat bersih sebelum konfirmasi/pengesahan.');
  }
  timestamp(fields.occurredAt, 'occurredAt');
  caneCode(fields.caneTypeCode);
  decimal(fields.netWeightKg, 'netWeightKg');
  uuid(fields.lotId, 'lotId');
  uuid(fields.supplierId, 'supplierId');
  if (fields.brix !== null) brix(fields.brix);
  return fields as IntakeFields & { occurredAt: string; caneTypeCode: string; netWeightKg: string };
}

export function parseDocumentQuery(input: unknown): DocumentQuery {
  const query = object(input, ['status', 'lotId', 'limit', 'offset']);
  const result: DocumentQuery = parsePage({
    ...(query.limit === undefined ? {} : { limit: query.limit }),
    ...(query.offset === undefined ? {} : { offset: query.offset }),
  });
  if (query.status !== undefined) {
    if (!['draft', 'awaiting_validation', 'approved'].includes(query.status as string)) throw new BadRequestException('status tidak didukung.');
    result.status = query.status as string;
  }
  if (query.lotId !== undefined) result.lotId = uuid(query.lotId, 'lotId');
  return result;
}

export function parseStockQuery(input: unknown): { synthetic: boolean; lotId?: string } {
  const query = object(input, ['synthetic', 'lotId']);
  if (query.synthetic !== undefined && query.synthetic !== 'true' && query.synthetic !== 'false') {
    throw new BadRequestException('synthetic harus true atau false.');
  }
  return { synthetic: query.synthetic === 'true', ...(query.lotId === undefined ? {} : { lotId: uuid(query.lotId, 'lotId') }) };
}
