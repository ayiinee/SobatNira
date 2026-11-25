import { ConflictException } from '@nestjs/common';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseSession } from '../database/database.service';
import { object, text, uuid } from './production.dto';

export function parseBatchSource(value: unknown) {
  if (value === undefined) return null;
  const row = object(value, ['documentId','revisionId','block','rowReference']);
  return { documentId: uuid(row.documentId), revisionId: uuid(row.revisionId),
    block: text(row.block,'block',300), rowReference: text(row.rowReference,'rowReference',300) };
}

function read(value: any) { return value?.status === 'READ' ? value.normalized_value : null; }

export async function batchSourceRows(db: DatabaseSession, access: FactoryAccess, lotId: string) {
  // Approval rows, rather than current_revision_id, identify the latest officially accepted note.
  const { rows } = await db.query(`SELECT m.ocr_document_id AS "documentId",m.ocr_cane_label AS block,
    p.revision_id AS "revisionId",r.extraction,
    (SELECT jsonb_agg(v.extraction) FROM document_approvals a JOIN document_revisions v ON v.id=a.revision_id
      WHERE a.document_id=d.id) AS "approvedHistory" FROM sobatnira.milling_records m
    JOIN source_documents d ON d.id=m.ocr_document_id AND d.factory_id=m.factory_id
    JOIN LATERAL (SELECT a.revision_id FROM document_approvals a JOIN document_revisions v ON v.id=a.revision_id
      WHERE a.document_id=d.id ORDER BY v.version DESC LIMIT 1) p ON true
    JOIN document_revisions r ON r.id=p.revision_id
    WHERE m.tenant_id=$1 AND m.factory_id=$2 AND m.lot_id=$3 AND NOT m.is_synthetic`,
    [access.tenantId,access.factoryId,lotId]);
  const result: Record<string, any>[] = [];
  for (const note of rows) {
    const blocks = note.extraction?.cane_blocks;
    if (!Array.isArray(blocks)) continue;
    const matches = blocks.filter((b: any) => read(b.cane_label) === note.block);
    if (matches.length !== 1) throw new ConflictException('Identitas blok nota berubah atau ambigu. Periksa sumber nota.');
    const seen = new Set<string>();
    for (const row of matches[0].batches ?? []) {
      if (typeof row.row_reference !== 'string' || seen.has(row.row_reference))
        throw new ConflictException('Identitas baris nota ambigu. Periksa sumber nota.');
      seen.add(row.row_reference);
      result.push({ source: { documentId: note.documentId, revisionId: note.revisionId,
        block: note.block, rowReference: row.row_reference }, wokNumber: read(row.pan_number),
        physicalWeightKg: row.output?.hasil_kg?.unit === 'kg' ? read(row.output.hasil_kg) : null,
        grade: read(row.output?.grade), finishTime: read(row.cooking?.jam_turun),
        contentsKg: read(row.cooking?.isi_kg), gamping: row.cooking?.gamping ?? null });
    }
    for (const previous of note.approvedHistory ?? []) {
      const oldBlocks = previous.cane_blocks?.filter((b: any) => read(b.cane_label) === note.block) ?? [];
      if (oldBlocks.length !== 1 || oldBlocks[0].batches?.some((r: any) => !seen.has(r.row_reference)))
        throw new ConflictException('Identitas baris nota berubah. Periksa sumber; jangan mencocokkan dari nomor wajan.');
    }
  }
  const existing = (await db.query(`SELECT id,source_document_id,source_block,source_row FROM sobatnira.production_batches
    WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND status<>'cancelled' AND source_document_id IS NOT NULL`,
    [access.tenantId,access.factoryId,lotId])).rows;
  return result.map((row): Record<string, any> => ({ ...row, batchId: existing.find(b => b.source_document_id === row.source.documentId
    && b.source_block === row.source.block && b.source_row === row.source.rowReference)?.id ?? null }));
}

export async function assertBatchSource(db: DatabaseSession, access: FactoryAccess, lotId: string,
  source: ReturnType<typeof parseBatchSource>, batchId?: string) {
  if (!source) return;
  await db.query('SELECT id FROM source_documents WHERE id=$1 AND factory_id=$2 FOR SHARE', [source.documentId,access.factoryId]);
  const row = (await batchSourceRows(db,access,lotId)).find(r =>
    r.source.documentId === source.documentId && r.source.block === source.block && r.source.rowReference === source.rowReference);
  if (!row || row.source.revisionId !== source.revisionId || (row.batchId && row.batchId !== batchId))
    throw new ConflictException('Sumber nota sudah berubah atau baris sudah digunakan. Muat ulang nota sah.');
}
