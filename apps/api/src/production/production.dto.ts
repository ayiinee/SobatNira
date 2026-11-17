import { BadRequestException, NotFoundException } from '@nestjs/common';
import { FactoryAccess, UUID_PATTERN } from '../auth/auth.types';

export interface Pagination { limit: number; offset: number }
export interface SupplierInput { name?: string; isActive?: boolean }
export interface LotInput { supplierId?: string; displayCode?: string | null; receivedAt?: string }
export interface CatalogQuery extends Pagination { q?: string; isActive?: boolean }
export type SupplierQuery = CatalogQuery;
export interface LotQuery extends Pagination { q?: string; supplierId?: string; receivedFrom?: string; receivedBefore?: string; includeSummary?: boolean }

export function object(input: unknown, allowed: string[]): Record<string, unknown> {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new BadRequestException('Gunakan objek JSON atau parameter query yang valid.');
  const record = input as Record<string, unknown>;
  if (Object.keys(record).some((key) => !allowed.includes(key))) throw new BadRequestException('Terdapat field yang tidak didukung.');
  return record;
}

export function text(input: unknown, field: string, max: number): string {
  if (typeof input !== 'string') throw new BadRequestException(`${field} harus berupa teks.`);
  const result = input.trim();
  if (!result || [...result].length > max || /[\u0000-\u001f\u007f]/.test(result)) {
    throw new BadRequestException(`${field} harus berisi 1–${max} karakter tanpa karakter kontrol.`);
  }
  return result;
}

export function caneTypeCode(input: unknown, field: string): string {
  const code = text(input, field, 40);
  if (!/^[A-Za-z0-9_-]+$/.test(code)) throw new BadRequestException(`${field} tidak valid.`);
  return code;
}

export function uuid(input: unknown, field = 'id'): string {
  if (typeof input !== 'string' || !UUID_PATTERN.test(input)) throw new BadRequestException(`${field} harus berupa UUID.`);
  return input.toLowerCase();
}

export function timestamp(input: unknown, field: string): string {
  if (typeof input !== 'string') throw new BadRequestException(`${field} harus berupa waktu ISO 8601 dengan zona waktu.`);
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,3})?(Z|[+-](\d{2}):(\d{2}))$/.exec(input);
  if (!match) throw new BadRequestException(`${field} harus berupa waktu ISO 8601 dengan zona waktu.`);
  const [, y, m, d, h, min, sec, , oh, om] = match;
  const year = Number(y), month = Number(m), day = Number(d);
  const days = [31, year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month < 1 || month > 12 || day < 1 || day > days[month - 1] || Number(h) > 23 ||
      Number(min) > 59 || Number(sec) > 59 || Number(oh ?? 0) > 14 || Number(om ?? 0) > 59 ||
      (Number(oh) === 14 && Number(om) !== 0) || !Number.isFinite(Date.parse(input))) {
    throw new BadRequestException(`${field} tidak valid.`);
  }
  return new Date(input).toISOString();
}

function pagination(record: Record<string, unknown>): Pagination {
  const integer = (key: string, fallback: number, min: number, max: number) => {
    if (record[key] === undefined) return fallback;
    const raw = record[key];
    if (typeof raw !== 'string' || !/^\d+$/.test(raw) || !Number.isSafeInteger(Number(raw)) ||
      Number(raw) < min || Number(raw) > max) throw new BadRequestException(`${key} di luar rentang yang diizinkan.`);
    return Number(raw);
  };
  return { limit: integer('limit', 20, 1, 100), offset: integer('offset', 0, 0, 2147483647) };
}

export function parseSupplierInput(input: unknown, patch = false): SupplierInput {
  const record = object(input, patch ? ['name', 'isActive'] : ['name']);
  if (!Object.keys(record).length) throw new BadRequestException('Minimal satu field diperlukan.');
  const result: SupplierInput = {};
  if (!patch || record.name !== undefined) result.name = text(record.name, 'name', 200);
  if (record.isActive !== undefined) {
    if (typeof record.isActive !== 'boolean') throw new BadRequestException('isActive harus berupa boolean.');
    result.isActive = record.isActive;
  }
  return result;
}

export function parseLotInput(input: unknown, patch = false): LotInput {
  const record = object(input, ['supplierId', 'displayCode', 'receivedAt']);
  if (!Object.keys(record).length) throw new BadRequestException('Minimal satu field diperlukan.');
  const result: LotInput = {};
  if (!patch || record.supplierId !== undefined) result.supplierId = uuid(record.supplierId, 'supplierId');
  if (!patch || record.receivedAt !== undefined) result.receivedAt = timestamp(record.receivedAt, 'receivedAt');
  if ('displayCode' in record) result.displayCode = record.displayCode === null ? null : text(record.displayCode, 'displayCode', 100);
  return result;
}

export function parseCatalogQuery(input: unknown): CatalogQuery {
  const record = object(input, ['q', 'isActive', 'limit', 'offset']);
  const query: CatalogQuery = pagination(record);
  if (record.q !== undefined) query.q = text(record.q, 'q', 100);
  if (record.isActive !== undefined) {
    if (record.isActive !== 'true' && record.isActive !== 'false') throw new BadRequestException('isActive harus true atau false.');
    query.isActive = record.isActive === 'true';
  }
  return query;
}

export const parseSupplierQuery = parseCatalogQuery;

export function parseLotQuery(input: unknown): LotQuery {
  const record = object(input, ['q', 'supplierId', 'receivedFrom', 'receivedBefore', 'includeSummary', 'limit', 'offset']);
  const query: LotQuery = pagination(record);
  if (record.includeSummary !== undefined) {
    if (record.includeSummary !== 'true' && record.includeSummary !== 'false') {
      throw new BadRequestException('includeSummary harus true atau false.');
    }
    query.includeSummary = record.includeSummary === 'true';
  }
  if (record.q !== undefined) query.q = text(record.q, 'q', 100);
  if (record.supplierId !== undefined) query.supplierId = uuid(record.supplierId, 'supplierId');
  if (record.receivedFrom !== undefined) query.receivedFrom = timestamp(record.receivedFrom, 'receivedFrom');
  if (record.receivedBefore !== undefined) query.receivedBefore = timestamp(record.receivedBefore, 'receivedBefore');
  if (query.receivedFrom && query.receivedBefore && Date.parse(query.receivedFrom) >= Date.parse(query.receivedBefore)) {
    throw new BadRequestException('receivedBefore harus sesudah receivedFrom.');
  }
  return query;
}

export function parsePage(input: unknown): Pagination { return pagination(object(input, ['limit', 'offset'])); }
export function scopeValues(access: FactoryAccess): string[] { return [access.userId, access.tenantId, access.factoryId]; }
export function found<T>(row: T | undefined): T {
  if (!row) throw new NotFoundException('Data tidak ditemukan dalam cakupan ini.');
  return row;
}
