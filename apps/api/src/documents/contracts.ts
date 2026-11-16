import { BadRequestException, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import Ajv from 'ajv/dist/2020';
import addFormats from 'ajv-formats';
import { timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export const SCHEMA_VERSION = '1.0.0';
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export type DocumentType = 'TRUCK_ARRIVAL_NOTE' | 'PRODUCTION_NOTE' | 'UNKNOWN';
export type Evidence = { asset_id: string; coordinate_space: string; bbox: number[] };
export type Issue = { code: string; severity: 'INFO' | 'WARNING' | 'ERROR' | 'BLOCKER'; message: string; field_path?: string };
export type Field = {
  raw_value: string | null;
  normalized_value: string | number | boolean | null;
  status: string;
  source: string;
  unit: string | null;
  confidence: number | null;
  evidence: Evidence[];
  alternatives?: { value: string | number | null; source: string; confidence: number | null }[];
};
export type Note = { document_type: Exclude<DocumentType, 'UNKNOWN'>; schema_version: string; issues: Issue[]; [key: string]: unknown };
export type Inbound = {
  provider: 'BAILEYS'; provider_message_id: string; chat_id: string; sender_phone_e164: string;
  provider_timestamp: string; message_type: 'IMAGE' | 'TEXT'; quoted_message_id?: string | null;
  caption?: string | null; media_mime_type?: string | null; media_file_name?: string | null;
};
export type Envelope = {
  request_id: string; document_id: string; submission_id: string; revision_id: string;
  source_asset_id: string; document_type: DocumentType; schema_version: string;
  status: 'COMPLETED' | 'PARTIAL' | 'NEEDS_REVIEW' | 'FAILED'; extraction: Note | null;
  issues: Issue[]; processing: Record<string, unknown>;
};

const ajv = new Ajv({ strict: false });
addFormats(ajv);
const schema = (name: string) => JSON.parse(readFileSync(resolve(__dirname, '../../../../docs/ai/schemas', `${name}.schema.json`), 'utf8'));
const inbound = ajv.compile<Inbound>(schema('whatsapp-inbound-event'));
const envelope = ajv.compile<Envelope>(schema('extraction-envelope'));
const truck = ajv.compile<Note>(schema('truck-arrival-note'));
const production = ajv.compile<Note>(schema('production-note'));

export function requireServiceToken(actual: string | undefined, expected: string | undefined) {
  if (!expected) throw new ServiceUnavailableException('Otorisasi layanan belum dikonfigurasi');
  const input = Buffer.from(actual ?? '');
  const secret = Buffer.from(expected);
  if (secret.length !== input.length || !timingSafeEqual(secret, input)) throw new UnauthorizedException();
}

export function readInbound(value: unknown, type: Inbound['message_type'], key?: string) {
  if (!inbound(value) || value.message_type !== type || key !== `baileys:${value.provider_message_id}` ||
      value.provider_message_id.length > 255 || value.chat_id.length > 255 ||
      (value.quoted_message_id?.length ?? 0) > 255 || (value.caption?.length ?? 0) > 4096 ||
      (value.media_file_name?.length ?? 0) > 255) {
    throw new BadRequestException('Metadata pesan atau Idempotency-Key tidak valid');
  }
  return value;
}

export function requireUuid(value: unknown): string {
  if (typeof value !== 'string' || !UUID.test(value)) throw new BadRequestException('ID dokumen atau revisi tidak valid');
  return value.toLowerCase();
}

export function readEnvelope(value: unknown, ids: {
  request_id: string; document_id: string; submission_id: string; revision_id: string; source_asset_id: string;
}): Envelope {
  if (!envelope(value) || value.schema_version !== SCHEMA_VERSION ||
      Object.entries(ids).some(([key, id]) => value[key as keyof Envelope] !== id) ||
      (!value.extraction && value.status === 'COMPLETED') ||
      (value.extraction && (value.status === 'FAILED' ||
        !validNote(value.extraction, value.document_type) ||
        fields(value.extraction).some(([, field]) => field.evidence.some((item) => item.asset_id !== ids.source_asset_id))))) {
    throw new Error('INVALID_OCR_CONTRACT');
  }
  return value;
}

export function validNote(value: unknown, type: DocumentType): value is Note {
  if (!(type === 'TRUCK_ARRIVAL_NOTE' ? truck(value) : type === 'PRODUCTION_NOTE' && production(value))) return false;
  const note = value as Note;
  return note.schema_version === SCHEMA_VERSION && fields(note).every(([path, field]) => {
    const key = path.split('.').at(-1);
    const weight = key === 'net_weight_kg' || key === 'isi_kg' || key === 'hasil_kg';
    return (!weight || (field.unit === 'kg' && (field.normalized_value === null ||
      (typeof field.normalized_value === 'number' && Number.isFinite(field.normalized_value) && field.normalized_value >= 0)))) &&
      (key !== 'brix' || field.unit === null);
  });
}

export function fields(value: unknown, path = ''): Array<[string, Field]> {
  if (!value || typeof value !== 'object') return [];
  if ('raw_value' in value && 'normalized_value' in value && 'evidence' in value) return [[path, value as Field]];
  return Object.entries(value).flatMap(([key, child]) => fields(child, path ? `${path}.${key}` : key));
}
