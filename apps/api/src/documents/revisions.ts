import { BadRequestException } from '@nestjs/common';
import { Field, fields, Issue, Note, validNote } from './contracts';

type Row = { row_reference: string; pan_number: Field; cooking: { jam_turun: Field }; [key: string]: unknown };
type Block = { block_reference: string; cane_label: Field; batches: Row[]; [key: string]: unknown };
const missing = new Set(['BLANK', 'NOT_YET_FILLED', 'NOT_PRESENT', 'ILLEGIBLE']);
const anchor = (row: Row) => row.pan_number.status === 'READ' && row.cooking.jam_turun.status === 'READ' &&
  row.pan_number.normalized_value !== null && row.cooking.jam_turun.normalized_value !== null
  ? JSON.stringify([String(row.pan_number.normalized_value), row.cooking.jam_turun.normalized_value]) : undefined;
const blockLabel = (block: Block) => block.cane_label.status === 'READ' && block.cane_label.normalized_value;

function mergeFields(previous: Record<string, unknown>, incoming: Record<string, unknown>, prefix: string, issues: Issue[]) {
  for (const [path, field] of fields(incoming)) {
    const old = fields(previous).find(([key]) => key === path)?.[1];
    if (!old || old.status !== 'READ') {
      if (field.status === 'READ') issues.push({ code: 'REVISION_FIELD_ADDED', severity: 'INFO',
        field_path: `${prefix}.${path}`, message: 'Nilai baru pada foto lanjutan.' });
      continue;
    }
    if (missing.has(field.status)) Object.assign(field, old);
    else if (field.status === 'READ' && field.normalized_value !== old.normalized_value) {
      issues.push({ code: 'REVISION_FIELD_CHANGED', severity: 'WARNING', field_path: `${prefix}.${path}`, message: 'Nilai berbeda dari revisi sebelumnya.' });
    }
  }
}

export function mergeProduction(previous: Note, incoming: Note) {
  const next = structuredClone(incoming);
  const prior = previous.cane_blocks as Block[];
  const latest = next.cane_blocks as Block[];
  const issues: Issue[] = [];
  const ambiguous = [...prior, ...latest].some((block) => !blockLabel(block) || block.batches.some((row) => !anchor(row))) ||
    [prior, latest].some((blocks) => new Set(blocks.map(blockLabel)).size !== blocks.length ||
      blocks.some((block) => new Set(block.batches.map(anchor)).size !== block.batches.length));
  if (ambiguous) {
    return { note: next, issues: [{ code: 'ROW_MATCH_REQUIRED', severity: 'BLOCKER', message: 'Perlu verifikasi blok atau baris pada kedua revisi.' }] as Issue[] };
  }

  mergeFields(previous.header as Record<string, unknown>, next.header as Record<string, unknown>, 'header', issues);
  for (const oldBlock of prior) {
    const block = latest.find((item) => blockLabel(item) === blockLabel(oldBlock));
    if (!block) {
      latest.push(structuredClone(oldBlock));
      continue;
    }
    for (const oldRow of oldBlock.batches) {
      const row = block.batches.find((item) => anchor(item) === anchor(oldRow));
      if (!row) block.batches.push(structuredClone(oldRow));
      else mergeFields(oldRow, row, `cane_blocks.${latest.indexOf(block)}.batches.${block.batches.indexOf(row)}`, issues);
    }
  }
  for (const [index, block] of latest.entries()) {
    block.block_reference = `BLOCK-${index + 1}`;
    const oldBlock = prior.find(item => blockLabel(item) === blockLabel(block));
    if (!oldBlock) issues.push({ code: 'REVISION_FIELD_ADDED', severity: 'INFO',
      field_path: `cane_blocks.${index}.cane_label`, message: 'Blok tebu baru.' });
    for (const [rowIndex, row] of block.batches.entries()) {
      row.row_reference = `ROW-${rowIndex + 1}`;
      if (oldBlock && !oldBlock.batches.some(item => anchor(item) === anchor(row))) {
        issues.push({ code: 'REVISION_FIELD_ADDED', severity: 'INFO',
          field_path: `cane_blocks.${index}.batches.${rowIndex}.pan_number`, message: 'Baris masak baru.' });
      }
    }
  }
  const columns = next.unmapped_columns as Array<{ header_raw: string | null }>;
  for (const column of previous.unmapped_columns as typeof columns) {
    if (!columns.some(({ header_raw }) => header_raw === column.header_raw)) columns.push(structuredClone(column));
  }
  return { note: next, issues };
}

export function setCorrectedValue(field: Field | undefined, path: string, value: unknown, source: 'OPERATOR_CORRECTION' | 'ADMIN_CORRECTION') {
  const name = path.split('.').at(-1);
  let valid = typeof value === 'string' && value.trim().length > 0 && value.length <= 300;
  if (field?.unit === 'kg' || name === 'brix') valid = typeof value === 'number' && Number.isFinite(value) && value >= 0;
  if (name === 'arrival_date' || name === 'production_date') {
    valid = typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
      Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
  }
  if (name === 'jam_turun') valid = typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
  if (!field || !valid) throw new BadRequestException('Field atau nilai koreksi tidak valid');
  field.normalized_value = value as string | number;
  field.status = 'READ';
  field.source = source;
  field.confidence = null;
}

export function correctField(note: Note, path: string, value: unknown, source: 'OPERATOR_CORRECTION' | 'ADMIN_CORRECTION') {
  const edited = structuredClone(note);
  const field = fields(edited).find(([key]) => key === path)?.[1];
  setCorrectedValue(field, path, value, source);
  edited.issues = edited.issues.filter((issue) => issue.field_path !== path);
  if (!validNote(edited, note.document_type)) throw new BadRequestException('Koreksi melanggar kontrak nota');
  return edited;
}
