import { BadRequestException } from '@nestjs/common';
import { fields, Field, Note, SCHEMA_VERSION, validNote } from './contracts';
import { setCorrectedValue } from './revisions';

const truck = ['arrival_date','supplier_name','vehicle_number','brix','net_weight_kg','cane_type','receiving_operator'];
const weights = new Set(['net_weight_kg','isi_kg','hasil_kg']);

function blank(key: string): Field {
  return { raw_value: null, normalized_value: null, status: 'NOT_PRESENT', source: 'ADMIN_CORRECTION',
    unit: weights.has(key) ? 'kg' : key === 'gamping' ? 'CUSTOM_MEASURE' : null, confidence: null, evidence: [] };
}

function group(keys: string[]) {
  return Object.fromEntries(keys.map((key) => [key, blank(key)]));
}

export function manualNote(input: Record<string, unknown>): Note {
  const type = input.document_type;
  if (type !== 'TRUCK_ARRIVAL_NOTE' && type !== 'PRODUCTION_NOTE') throw new BadRequestException('Pilih satu jenis nota');
  const values = input.values;
  if (!values || typeof values !== 'object' || Array.isArray(values) || Object.keys(values).length === 0 || Object.keys(values).length > 1000) {
    throw new BadRequestException('Isi nilai yang dapat diperiksa pada foto');
  }
  const note: Note = { document_type: type, schema_version: SCHEMA_VERSION, template_version: null, issues: [] };
  if (type === 'TRUCK_ARRIVAL_NOTE') {
    note.header = group(truck);
    note.cane_tag_reference = { raw_value: null, status: 'NOT_CAPTURED', source_note: 'Label tebu menunggu konfirmasi.' };
  } else {
    const rows = input.rows_per_block;
    if (!Array.isArray(rows) || rows.length === 0 || rows.length > 30 ||
      rows.some((count) => !Number.isInteger(count) || count < 1 || count > 50) || rows.reduce((total, count) => total + count, 0) > 100) {
      throw new BadRequestException('Nota produksi memerlukan blok tebu dan baris wajan');
    }
    note.header = group(['production_date','shift','chef']);
    note.unmapped_columns = [];
    note.cane_blocks = rows.map((count, block) => ({
      block_reference: `BLOCK-${block + 1}`, cane_label: blank('cane_label'),
      kloter_match: { status: 'NOT_ATTEMPTED', candidate_kloter_id: null, match_method: 'NONE' },
      batches: Array.from({ length: count }, (_, row) => ({
        row_reference: `ROW-${row + 1}`, pan_number: blank('pan_number'), brix: blank('brix'), brix_measurement_stage: 'UNKNOWN',
        cooking: group(['isi_kg','gamping','jam_turun']), output: group(['grade','hasil_kg']), unmapped_cells: [],
      })),
    }));
  }
  const available = new Map(fields(note));
  for (const [path, value] of Object.entries(values)) {
    setCorrectedValue(available.get(path), path, value, 'ADMIN_CORRECTION');
  }
  if (!validNote(note, type)) throw new BadRequestException('Isian manual melanggar kontrak nota');
  return note;
}
