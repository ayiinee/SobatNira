import { BadRequestException } from '@nestjs/common';
import { expectedRevision } from '../documents/intake.dto';
import { compareDecimals, decimal, sumDecimals } from '../production/decimal';
import { object, text, timestamp, uuid } from '../production/production.dto';

// Labels from the combined result note, not official cooking batch IDs.
export interface ReportedBatch {
  batchReference: string; wokNumber: number; totalJuiceLiters: string; sourceJuiceLiters: string;
}
export interface MillingFields {
  lotId: string;
  occurredAt: string | null;
  juiceProducedLiters: string | null;
  reportedBatches: ReportedBatch[] | null;
}
export interface MillingUpdate {
  expectedRevision: number; reason: string; changes: Partial<MillingFields>;
}

function batches(input: unknown): ReportedBatch[] {
  if (!Array.isArray(input) || input.length > 500) throw new BadRequestException('reportedBatches harus berupa daftar maksimal 500 baris.');
  const references = new Set<string>();
  return input.map((item) => {
    const row = object(item, ['batchReference', 'wokNumber', 'totalJuiceLiters', 'sourceJuiceLiters']);
    const batchReference = text(row.batchReference, 'batchReference', 100);
    if (references.has(batchReference)) throw new BadRequestException('batchReference duplikat dalam nota.');
    references.add(batchReference);
    if (typeof row.wokNumber !== 'number' || !Number.isInteger(row.wokNumber) || row.wokNumber < 1 || row.wokNumber > 3) {
      throw new BadRequestException('wokNumber harus 1, 2, atau 3.');
    }
    const totalJuiceLiters = decimal(row.totalJuiceLiters, 'totalJuiceLiters');
    const sourceJuiceLiters = decimal(row.sourceJuiceLiters, 'sourceJuiceLiters');
    if (compareDecimals(totalJuiceLiters, '115') > 0) throw new BadRequestException('Volume batch melebihi kapasitas awal 115 L per wajan.');
    if (compareDecimals(sourceJuiceLiters, totalJuiceLiters) > 0) throw new BadRequestException('Kontribusi kloter melebihi total nira batch.');
    return { batchReference, wokNumber: row.wokNumber, totalJuiceLiters, sourceJuiceLiters };
  });
}

export function parseMillingUpdate(input: unknown): MillingUpdate {
  const body = object(input, ['expectedRevision', 'reason', 'changes']);
  const raw = object(body.changes, ['lotId', 'occurredAt', 'juiceProducedLiters', 'reportedBatches']);
  if (!Object.keys(raw).length) throw new BadRequestException('Minimal satu perubahan diperlukan.');
  const changes: Partial<MillingFields> = {};
  if ('lotId' in raw) changes.lotId = uuid(raw.lotId, 'lotId');
  if ('occurredAt' in raw) changes.occurredAt = raw.occurredAt === null ? null : timestamp(raw.occurredAt, 'occurredAt');
  if ('juiceProducedLiters' in raw) changes.juiceProducedLiters = raw.juiceProducedLiters === null ? null : decimal(raw.juiceProducedLiters, 'juiceProducedLiters', true);
  if ('reportedBatches' in raw) changes.reportedBatches = raw.reportedBatches === null ? null : batches(raw.reportedBatches);
  return { expectedRevision: expectedRevision(body.expectedRevision), reason: text(body.reason, 'reason', 500), changes };
}

export function completeMillingFields(fields: MillingFields): MillingFields & {
  occurredAt: string; juiceProducedLiters: string; reportedBatches: ReportedBatch[];
} {
  if (!fields.occurredAt || fields.juiceProducedLiters === null || fields.reportedBatches === null) {
    throw new BadRequestException('Lengkapi waktu penggilingan, total liter nira dan rincian batch pada nota hasil.');
  }
  uuid(fields.lotId, 'lotId');
  timestamp(fields.occurredAt, 'occurredAt');
  const total = decimal(fields.juiceProducedLiters, 'juiceProducedLiters', true);
  const rows = batches(fields.reportedBatches);
  if (compareDecimals(sumDecimals(rows.map((row) => row.sourceJuiceLiters)), total) > 0) {
    throw new BadRequestException('Jumlah kontribusi nira kloter pada batch melebihi hasil penggilingan.');
  }
  return { ...fields, occurredAt: fields.occurredAt, juiceProducedLiters: total, reportedBatches: rows };
}
