import { ForbiddenException, Injectable } from '@nestjs/common';
import { ACTIVE_ACCESS_SQL, FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { DocumentQuery } from '../documents/intake.dto';
import { Pagination, scopeValues } from '../production/production.dto';
import { queryPage } from '../production/production.repository';
import { completeMillingFields, MillingFields } from './milling.dto';

export interface MillingDocument {
  id: string; lotId: string; tenantId: string; factoryId: string;
  source: 'synthetic'; sourceRequestId: string; sourcePayloadHash: string; sourcePayload: unknown; synthetic: true;
  status: 'draft' | 'awaiting_validation' | 'approved'; currentRevision: number;
  confirmedRevision: number | null; confirmedBy: string | null; confirmedAt: Date | null; confirmationSource: string | null;
  approvedRevision: number | null; approvedBy: string | null; approvedAt: Date | null;
  createdAt: Date; updatedAt: Date; fields: MillingFields; milling: Record<string, unknown> | null;
}

const COLUMNS = `d.id, d.tenant_id AS "tenantId", d.factory_id AS "factoryId", d.lot_id AS "lotId",
  d.source, d.source_request_id AS "sourceRequestId", d.source_payload_hash AS "sourcePayloadHash", d.source_payload AS "sourcePayload",
  d.is_synthetic AS synthetic, d.status, d.current_revision AS "currentRevision",
  d.confirmed_revision AS "confirmedRevision", d.confirmed_by AS "confirmedBy", d.confirmed_at AS "confirmedAt",
  d.confirmation_source AS "confirmationSource", d.approved_revision AS "approvedRevision",
  d.approved_by AS "approvedBy", d.approved_at AS "approvedAt", d.created_at AS "createdAt", d.updated_at AS "updatedAt", r.fields,
  (SELECT jsonb_build_object('id', m.id, 'lotId', m.lot_id, 'intakeRecordId', m.intake_record_id,
    'documentRevision', m.document_revision, 'caneConsumedKg', m.cane_consumed_kg::text,
    'juiceProducedLiters', m.juice_produced_liters::text, 'reportedBatches', m.reported_batches,
    'reportedBatchCount', m.reported_batch_count, 'occurredAt', m.occurred_at, 'approvedAt', m.approved_at, 'synthetic', m.is_synthetic)
    FROM sobatnira.milling_records m WHERE m.tenant_id = d.tenant_id AND m.factory_id = d.factory_id AND m.document_id = d.id) AS milling`;
const JOINS = `FROM sobatnira.milling_documents d
  JOIN authorized_scope scope ON scope."tenantId" = d.tenant_id AND scope."factoryId" = d.factory_id
  JOIN sobatnira.milling_document_revisions r ON r.tenant_id = d.tenant_id AND r.factory_id = d.factory_id
    AND r.document_id = d.id AND r.revision = d.current_revision`;

type MillingSource =
  | { synthetic: true; documentId: string; documentRevision: number }
  | { synthetic: false; ocrDocumentId: string; ocrRevisionId: string; caneLabel: string };

@Injectable()
export class MillingRepository {
  constructor(private readonly database: DatabaseService) {}

  mutate<T>(access: FactoryAccess, work: (tx: DatabaseSession) => Promise<T>): Promise<T> {
    return this.database.transaction(async (tx) => {
      const active = await tx.query(`${ACTIVE_ACCESS_SQL}
        AND fm.tenant_id = $2::uuid AND fm.factory_id = $3::uuid AND fm.role IN ('admin', 'owner')
        FOR SHARE OF fm, tm, f, t`, scopeValues(access));
      if (!active.rows.length) throw new ForbiddenException('Akses pabrik tidak lagi tersedia.');
      return work(tx);
    });
  }

  async get(tx: DatabaseSession, access: FactoryAccess, id: string, lock = false): Promise<MillingDocument | undefined> {
    if (lock) {
      const locked = await tx.query(`WITH ${FACTORY_SCOPE_CTE}
        SELECT d.id FROM sobatnira.milling_documents d JOIN authorized_scope scope
          ON scope."tenantId" = d.tenant_id AND scope."factoryId" = d.factory_id
        WHERE d.id = $4::uuid FOR UPDATE OF d`, [...scopeValues(access), id]);
      if (!locked.rows.length) return undefined;
    }
    // A new statement sees revisions/records committed by a writer we waited for.
    return (await tx.query<MillingDocument>(`WITH ${FACTORY_SCOPE_CTE} SELECT ${COLUMNS} ${JOINS}
      WHERE d.id = $4::uuid`, [...scopeValues(access), id])).rows[0];
  }
  find(access: FactoryAccess, id: string) { return this.get(this.database, access, id); }
  list(access: FactoryAccess, query: DocumentQuery) {
    return queryPage<MillingDocument>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT ${COLUMNS} ${JOINS} WHERE ($4::text IS NULL OR d.status = $4) AND ($5::uuid IS NULL OR d.lot_id = $5)
    )`, [...scopeValues(access), query.status ?? null, query.lotId ?? null], query, '"createdAt" DESC, id');
  }

  async lot(tx: DatabaseSession, access: FactoryAccess, id: string) {
    return (await tx.query<{ id: string; receivedAt: Date }>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT l.id, l.received_at AS "receivedAt" FROM sobatnira.lots l JOIN authorized_scope scope
        ON scope."tenantId" = l.tenant_id AND scope."factoryId" = l.factory_id
      WHERE l.id = $4::uuid FOR UPDATE OF l`, [...scopeValues(access), id])).rows[0];
  }

  async sourceId(tx: DatabaseSession, access: FactoryAccess, requestId: string) {
    return (await tx.query<{ id: string }>(`SELECT id FROM sobatnira.milling_documents
      WHERE tenant_id = $1 AND factory_id = $2 AND source = 'synthetic' AND source_request_id = $3`,
    [access.tenantId, access.factoryId, requestId])).rows[0]?.id;
  }
  async insert(tx: DatabaseSession, access: FactoryAccess, lotId: string, requestId: string, hash: string, payload: unknown) {
    return (await tx.query<{ id: string }>(`INSERT INTO sobatnira.milling_documents
      (tenant_id, factory_id, lot_id, source, source_request_id, source_payload_hash, source_payload)
      VALUES ($1, $2, $3, 'synthetic', $4, $5, $6::jsonb)
      ON CONFLICT (tenant_id, factory_id, source, source_request_id) DO NOTHING RETURNING id`,
    [access.tenantId, access.factoryId, lotId, requestId, hash, JSON.stringify(payload)])).rows[0]?.id;
  }
  revision(tx: DatabaseSession, access: FactoryAccess, id: string, revision: number, fields: MillingFields, reason?: string) {
    return tx.query(`INSERT INTO sobatnira.milling_document_revisions
      (tenant_id, factory_id, document_id, revision, fields, origin, actor_id, reason)
      VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8)`,
    [access.tenantId, access.factoryId, id, revision, JSON.stringify(fields),
      revision === 1 ? 'synthetic_extraction' : 'admin_correction', access.userId, reason ?? null]);
  }
  advance(tx: DatabaseSession, access: FactoryAccess, id: string, revision: number, lotId: string) {
    return tx.query(`UPDATE sobatnira.milling_documents SET current_revision = $4, lot_id = $5, updated_at = clock_timestamp()
      WHERE tenant_id = $1 AND factory_id = $2 AND id = $3`, [access.tenantId, access.factoryId, id, revision, lotId]);
  }
  confirm(tx: DatabaseSession, access: FactoryAccess, id: string, revision: number) {
    return tx.query(`UPDATE sobatnira.milling_documents SET status = 'awaiting_validation', confirmed_revision = $4,
      confirmed_by = $5, confirmed_at = clock_timestamp(), confirmation_source = 'synthetic_admin', updated_at = clock_timestamp()
      WHERE tenant_id = $1 AND factory_id = $2 AND id = $3`, [access.tenantId, access.factoryId, id, revision, access.userId]);
  }

  async intakeAndBalance(tx: DatabaseSession, access: FactoryAccess, lotId: string, synthetic = true) {
    return (await tx.query<{ id: string; netWeightKg: string; occurredAt: Date; stockMatches: boolean; alreadyMilled: boolean }>(`
      SELECT i.id, i.net_weight_kg::text AS "netWeightKg", i.occurred_at AS "occurredAt",
        COALESCE((SELECT sum(s.quantity_delta_kg) FROM sobatnira.cane_stock_entries s
          WHERE s.tenant_id = i.tenant_id AND s.factory_id = i.factory_id AND s.lot_id = i.lot_id AND s.is_synthetic = i.is_synthetic), 0)
          = i.net_weight_kg AS "stockMatches",
        EXISTS(SELECT 1 FROM sobatnira.milling_records m WHERE m.tenant_id = i.tenant_id AND m.factory_id = i.factory_id AND m.lot_id = i.lot_id) AS "alreadyMilled"
      FROM sobatnira.intake_records i WHERE i.tenant_id = $1 AND i.factory_id = $2 AND i.lot_id = $3 AND i.is_synthetic = $4`,
    [access.tenantId, access.factoryId, lotId, synthetic])).rows[0];
  }

  async approve(tx: DatabaseSession, access: FactoryAccess, doc: MillingDocument,
    fields: ReturnType<typeof completeMillingFields>, intake: { id: string; netWeightKg: string }) {
    const record = await this.postMilling(tx, access, fields, intake, {
      synthetic: true, documentId: doc.id, documentRevision: doc.currentRevision,
    });
    await tx.query(`UPDATE sobatnira.milling_documents SET status = 'approved', approved_revision = current_revision,
      approved_by = $4, approved_at = $5, updated_at = clock_timestamp() WHERE tenant_id = $1 AND factory_id = $2 AND id = $3`,
    [access.tenantId, access.factoryId, doc.id, access.userId, record.approvedAt]);
  }

  // The caller holds the lot lock and checks the approved receipt and its balance in this transaction.
  async postMilling(tx: DatabaseSession, access: FactoryAccess,
    fields: { lotId: string; occurredAt: string; juiceProducedLiters: string; reportedBatches: readonly unknown[] },
    intake: { id: string; netWeightKg: string }, source: MillingSource) {
    const record = (await tx.query<{ id: string; approvedAt: Date }>(`INSERT INTO sobatnira.milling_records
      (tenant_id, factory_id, lot_id, intake_record_id, document_id, document_revision, cane_consumed_kg,
        juice_produced_liters, occurred_at, approved_by, is_synthetic, reported_batches, ocr_document_id, ocr_revision_id, ocr_cane_label)
      VALUES ($1, $2, $3, $4, $5, $6, $7::numeric, $8::numeric, $9::timestamptz, $10, $11, $12::jsonb, $13, $14, $15)
      RETURNING id, approved_at AS "approvedAt"`,
    [access.tenantId, access.factoryId, fields.lotId, intake.id,
      source.synthetic ? source.documentId : null, source.synthetic ? source.documentRevision : null, intake.netWeightKg,
      fields.juiceProducedLiters, fields.occurredAt, access.userId, source.synthetic, JSON.stringify(fields.reportedBatches),
      source.synthetic ? null : source.ocrDocumentId, source.synthetic ? null : source.ocrRevisionId,
      source.synthetic ? null : source.caneLabel])).rows[0];
    await tx.query(`INSERT INTO sobatnira.sugarcane_stock_movements
      (tenant_id, factory_id, lot_id, milling_record_id, movement_type, quantity_delta_kg, occurred_at, is_synthetic)
      VALUES ($1, $2, $3, $4, 'milling', -($5::numeric), $6::timestamptz, $7)`,
    [access.tenantId, access.factoryId, fields.lotId, record.id, intake.netWeightKg, fields.occurredAt, source.synthetic]);
    await tx.query(`INSERT INTO sobatnira.juice_stock_movements
      (tenant_id, factory_id, lot_id, milling_record_id, movement_type, quantity_delta_liters, occurred_at, is_synthetic)
      VALUES ($1, $2, $3, $4, 'milling', $5::numeric, $6::timestamptz, $7)`,
    [access.tenantId, access.factoryId, fields.lotId, record.id, fields.juiceProducedLiters, fields.occurredAt, source.synthetic]);
    return record;
  }
  event(tx: DatabaseSession, access: FactoryAccess, id: string, action: string, before: MillingDocument | null, after: MillingDocument) {
    return tx.query(`INSERT INTO sobatnira.milling_document_events
      (tenant_id, factory_id, document_id, action, actor_id, before_data, after_data)
      VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb)`,
    [access.tenantId, access.factoryId, id, action, access.userId, before ? JSON.stringify(before) : null, JSON.stringify(after)]);
  }
  history(access: FactoryAccess, id: string, page: Pagination) {
    return queryPage<{ id: string }>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT e.id, e.action, e.actor_id AS "actorId", e.before_data AS before, e.after_data AS after, e.occurred_at AS "occurredAt"
      FROM sobatnira.milling_document_events e JOIN authorized_scope scope
        ON scope."tenantId" = e.tenant_id AND scope."factoryId" = e.factory_id WHERE e.document_id = $4::uuid
    )`, [...scopeValues(access), id], page, '"occurredAt" DESC, id');
  }
  revisions(access: FactoryAccess, id: string, page: Pagination) {
    return queryPage<{ id: string }>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT r.document_id::text || ':' || r.revision AS id, r.revision, r.fields, r.origin, r.reason,
        r.actor_id AS "actorId", r.created_at AS "createdAt" FROM sobatnira.milling_document_revisions r JOIN authorized_scope scope
        ON scope."tenantId" = r.tenant_id AND scope."factoryId" = r.factory_id WHERE r.document_id = $4::uuid
    )`, [...scopeValues(access), id], page, 'revision DESC');
  }
  async balance(access: FactoryAccess, synthetic: boolean, lotId?: string) {
    const result = await this.database.query<{ quantityLiters: string }>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT COALESCE(sum(m.quantity_delta_liters), 0)::text AS "quantityLiters"
      FROM sobatnira.juice_produced_entries m JOIN authorized_scope scope
        ON scope."tenantId" = m.tenant_id AND scope."factoryId" = m.factory_id
      WHERE m.is_synthetic = $4 AND ($5::uuid IS NULL OR m.lot_id = $5)`, [...scopeValues(access), synthetic, lotId ?? null]);
    return { material: 'juice', unit: 'L', synthetic, lotId: lotId ?? null, quantityLiters: result.rows[0].quantityLiters };
  }

  async summary(access: FactoryAccess, lotId: string, synthetic: boolean) {
    return (await this.database.query<{ lotId: string; milling: Record<string, unknown> | null }>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT l.id AS "lotId", (SELECT jsonb_build_object('id', m.id, 'documentId', m.document_id,
        'documentRevision', m.document_revision, 'caneConsumedKg', m.cane_consumed_kg::text,
        'juiceProducedLiters', COALESCE(c.quantity_after, m.juice_produced_liters)::text, 'reportedBatchCount', m.reported_batch_count,
        'reportedBatches', m.reported_batches, 'occurredAt', m.occurred_at,
        'approvedAt', COALESCE(c.created_at,m.approved_at), 'synthetic', m.is_synthetic)
        || CASE WHEN m.is_synthetic THEN '{}'::jsonb
          ELSE jsonb_build_object('ocrDocumentId', m.ocr_document_id, 'ocrRevisionId', COALESCE(c.revision_id,m.ocr_revision_id),
            'ocrCaneLabel', m.ocr_cane_label) END
        FROM sobatnira.milling_records m LEFT JOIN LATERAL (
          SELECT revision_id,quantity_after,created_at FROM sobatnira.stock_reconciliations
          WHERE milling_record_id=m.id ORDER BY revision_version DESC LIMIT 1
        ) c ON true WHERE m.tenant_id = l.tenant_id AND m.factory_id = l.factory_id
          AND m.lot_id = l.id AND m.is_synthetic = $5) AS milling
      FROM sobatnira.lots l JOIN authorized_scope scope ON scope."tenantId" = l.tenant_id AND scope."factoryId" = l.factory_id
      WHERE l.id = $4::uuid`, [...scopeValues(access), lotId, synthetic])).rows[0];
  }
}
