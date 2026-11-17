import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { DatabaseSession } from '../database/database.service';
import { MillingRepository } from '../milling/milling.repository';
import { decimal } from '../production/decimal';
import { object, Pagination, text, timestamp, uuid } from '../production/production.dto';
import { Field, Note } from './contracts';
import { requireProductionAccess } from './production-access';

type PostedMilling = {
  id: string; cane_label: string; lot_id: string; juice_produced_liters: string;
  occurred_at: Date; revision_id: string;
};

function read(field: Field | undefined) {
  return field?.status === 'READ' ? field.normalized_value : null;
}

function noteBlocks(note: Note) {
  if (note.document_type !== 'PRODUCTION_NOTE' || !Array.isArray(note.cane_blocks) || !note.cane_blocks.length) {
    throw new ConflictException('Nota produksi harus memiliki blok tebu.');
  }
  const result = new Map<string, unknown[]>();
  for (const block of note.cane_blocks) {
    const label = read(block.cane_label);
    if (typeof label !== 'string' || !label.trim() || result.has(label.trim())) {
      throw new ConflictException('Lengkapi label tebu yang unik pada setiap blok sebelum pengesahan.');
    }
    result.set(label.trim(), block.batches.map((row: {
      row_reference: string; pan_number?: Field; cooking?: { isi_kg?: Field; jam_turun?: Field };
    }) => ({
      rowReference: row.row_reference,
      wokNumber: read(row.pan_number),
      contentsKg: row.cooking?.isi_kg?.unit === 'kg' ? read(row.cooking.isi_kg) : null,
      finishTime: read(row.cooking?.jam_turun),
    })));
  }
  return result;
}

function parseMappings(input: unknown) {
  if (!Array.isArray(input) || input.length > 100) throw new BadRequestException('Isian penggilingan wajib berupa daftar blok.');
  const labels = new Set<string>();
  const lots = new Set<string>();
  return input.map((item) => {
    const row = object(item, ['cane_label', 'lot_id', 'occurred_at', 'juice_produced_liters']);
    const caneLabel = text(row.cane_label, 'cane_label', 300);
    const lotId = uuid(row.lot_id, 'lot_id');
    if (labels.has(caneLabel) || lots.has(lotId)) throw new BadRequestException('Satu blok harus memilih satu kloter yang berbeda.');
    labels.add(caneLabel);
    lots.add(lotId);
    return { caneLabel, lotId, occurredAt: timestamp(row.occurred_at, 'occurred_at'),
      juiceProducedLiters: decimal(row.juice_produced_liters, 'juice_produced_liters', true) };
  });
}

@Injectable()
export class ProductionMilling {
  constructor(private readonly milling: MillingRepository) {}

  async choices(db: DatabaseSession, userId: string, factoryId: string, page: Pagination) {
    const access = await requireProductionAccess(db, userId, factoryId);
    const { rows } = await db.query(`SELECT l.id,l.display_code AS "displayCode",l.received_at AS "receivedAt",
      s.name AS "supplierName" FROM sobatnira.lots l
      JOIN sobatnira.suppliers s ON s.tenant_id=l.tenant_id AND s.id=l.supplier_id
      JOIN sobatnira.intake_records i ON i.tenant_id=l.tenant_id AND i.factory_id=l.factory_id AND i.lot_id=l.id AND NOT i.is_synthetic
      WHERE l.tenant_id=$1 AND l.factory_id=$2 AND NOT EXISTS (
        SELECT 1 FROM sobatnira.milling_records m WHERE m.tenant_id=l.tenant_id AND m.factory_id=l.factory_id AND m.lot_id=l.id
      ) ORDER BY l.received_at DESC,l.id LIMIT $3 OFFSET $4`,
    [access.tenantId, factoryId, page.limit + 1, page.offset]);
    return { items: rows.slice(0, page.limit), next_offset: rows.length > page.limit ? page.offset + page.limit : null };
  }

  async posted(db: DatabaseSession, factoryId: string, documentId: string, version: number) {
    const { rows } = await db.query<PostedMilling>(`SELECT m.id,m.ocr_cane_label AS cane_label,m.lot_id,
      COALESCE(c.quantity_after,m.juice_produced_liters)::text AS juice_produced_liters,
      m.occurred_at,COALESCE(c.revision_id,m.ocr_revision_id) AS revision_id
      FROM sobatnira.milling_records m JOIN document_revisions r ON r.id=m.ocr_revision_id AND r.document_id=m.ocr_document_id
      LEFT JOIN LATERAL (
        SELECT revision_id,quantity_after FROM sobatnira.stock_reconciliations
          WHERE milling_record_id=m.id AND revision_version<=$3 ORDER BY revision_version DESC LIMIT 1
      ) c ON true
      WHERE m.factory_id=$1 AND m.ocr_document_id=$2 AND r.version<=$3 ORDER BY m.ocr_cane_label`,
    [factoryId, documentId, version]);
    return rows;
  }

  async post(db: DatabaseSession, input: { documentId: string; revisionId: string; version: number;
    userId: string; factoryId: string; note: Note; mappings: unknown }) {
    const access = await requireProductionAccess(db, input.userId, input.factoryId);
    const blocks = noteBlocks(input.note);
    const prior = await this.posted(db, input.factoryId, input.documentId, input.version);
    const mappings = parseMappings(input.mappings);
    const bookedLabels = new Set(prior.map((record) => record.cane_label));
    if (prior.some((record) => !blocks.has(record.cane_label))) {
      throw new ConflictException('Label tebu yang sudah dibukukan berubah. Periksa revisi sebelum pengesahan.');
    }
    if (mappings.length !== blocks.size - bookedLabels.size ||
        mappings.some(({ caneLabel }) => !blocks.has(caneLabel) || bookedLabels.has(caneLabel))) {
      throw new ConflictException('Lengkapi penggilingan untuk setiap blok baru. Blok yang sudah dibukukan tetap sama.');
    }

    // All document reviews lock lots in UUID order so multi-block approvals can compete safely.
    for (const { lotId } of [...mappings].sort((a, b) => a.lotId.localeCompare(b.lotId))) {
      if (!await this.milling.lot(db, access, lotId)) {
        throw new ConflictException('Kloter penggilingan tidak tersedia pada pabrik ini.');
      }
    }

    for (const mapping of mappings) {
      const intake = await this.milling.intakeAndBalance(db, access, mapping.lotId, false);
      if (!intake || intake.alreadyMilled || !intake.stockMatches) {
        throw new ConflictException('Kloter memerlukan penerimaan sah, saldo tebu yang sesuai, dan belum dibukukan penggilingannya.');
      }
      if (Date.parse(mapping.occurredAt) < intake.occurredAt.getTime()) {
        throw new ConflictException('Waktu penggilingan tidak boleh mendahului penerimaan tebu.');
      }
      await this.milling.postMilling(db, access, { ...mapping, reportedBatches: blocks.get(mapping.caneLabel)! },
        intake, { synthetic: false, ocrDocumentId: input.documentId, ocrRevisionId: input.revisionId, caneLabel: mapping.caneLabel });
    }

    return this.posted(db, input.factoryId, input.documentId, input.version);
  }
}
