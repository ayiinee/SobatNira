import { ForbiddenException, Injectable } from '@nestjs/common';
import { ACTIVE_ACCESS_SQL, FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { Pagination, scopeValues } from '../production/production.dto';
import { queryPage } from '../production/production.repository';
import { DocumentQuery, IntakeFields } from './intake.dto';
import { EvidenceInfo } from '../evidence/evidence.types';

export interface IntakeDocument {
  id: string; tenantId: string; factoryId: string; lotId: string;
  source: 'synthetic'; sourceRequestId: string; sourcePayloadHash: string; sourcePayload: unknown; synthetic: true;
  status: 'draft' | 'awaiting_validation' | 'approved'; currentRevision: number;
  confirmedRevision: number | null; confirmedBy: string | null; confirmedAt: Date | null;
  confirmationSource: 'synthetic_admin' | null;
  approvedRevision: number | null; approvedBy: string | null; approvedAt: Date | null;
  createdAt: Date; updatedAt: Date; fields: IntakeFields; intake: Record<string, unknown> | null;
  evidence: EvidenceInfo | null;
}
export interface IntakeLot {
  id: string; tenantId: string; factoryId: string; supplierId: string; displayCode: string | null;
  receivedAt: Date; createdAt: Date; updatedAt: Date;
}

const COLUMNS = `d.id, d.tenant_id AS "tenantId", d.factory_id AS "factoryId", d.lot_id AS "lotId",
  d.source, d.source_request_id AS "sourceRequestId", d.source_payload_hash AS "sourcePayloadHash", d.source_payload AS "sourcePayload",
  d.is_synthetic AS synthetic, d.status, d.current_revision AS "currentRevision",
  d.confirmed_revision AS "confirmedRevision", d.confirmed_by AS "confirmedBy", d.confirmed_at AS "confirmedAt",
  d.confirmation_source AS "confirmationSource",
  d.approved_revision AS "approvedRevision", d.approved_by AS "approvedBy", d.approved_at AS "approvedAt",
  d.created_at AS "createdAt", d.updated_at AS "updatedAt", r.fields,
  (SELECT jsonb_build_object('id', e.id, 'documentId', e.document_id, 'contentType', e.content_type,
    'byteSize', e.byte_size, 'sha256', e.sha256, 'width', e.width, 'height', e.height,
    'uploadedBy', e.uploaded_by, 'createdAt', e.created_at,
    'contentPath', '/tenants/' || e.tenant_id || '/factories/' || e.factory_id || '/intake-documents/' || e.document_id || '/evidence/' || e.id || '/content')
    FROM sobatnira.intake_evidence e WHERE e.tenant_id = d.tenant_id AND e.factory_id = d.factory_id
      AND e.document_id = d.id AND e.id = d.evidence_id) AS evidence,
  (SELECT jsonb_build_object('id', i.id, 'lotId', i.lot_id, 'supplierId', i.supplier_id,
    'documentRevision', i.document_revision, 'netWeightKg', i.net_weight_kg::text, 'caneTypeCode', i.cane_type_code,
    'brix', i.brix::text, 'occurredAt', i.occurred_at, 'approvedAt', i.approved_at, 'synthetic', i.is_synthetic)
    FROM sobatnira.intake_records i WHERE i.tenant_id = d.tenant_id AND i.factory_id = d.factory_id AND i.document_id = d.id) AS intake`;
const JOINS = `FROM sobatnira.intake_documents d
  JOIN authorized_scope scope ON scope."tenantId" = d.tenant_id AND scope."factoryId" = d.factory_id
  JOIN sobatnira.intake_document_revisions r ON r.tenant_id = d.tenant_id AND r.factory_id = d.factory_id
    AND r.document_id = d.id AND r.revision = d.current_revision`;

@Injectable()
export class IntakeRepository {
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

  async get(tx: DatabaseSession, access: FactoryAccess, id: string, lock = false): Promise<IntakeDocument | undefined> {
    if (lock) {
      const locked = await tx.query(`WITH ${FACTORY_SCOPE_CTE}
        SELECT d.id FROM sobatnira.intake_documents d JOIN authorized_scope scope
          ON scope."tenantId" = d.tenant_id AND scope."factoryId" = d.factory_id
        WHERE d.id = $4::uuid FOR UPDATE OF d`, [...scopeValues(access), id]);
      if (!locked.rows.length) return undefined;
    }
    // Read revisions/intake on a fresh snapshot after any competing writer commits.
    const result = await tx.query<IntakeDocument>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT ${COLUMNS} ${JOINS} WHERE d.id = $4::uuid`,
    [...scopeValues(access), id]);
    return result.rows[0];
  }

  find(access: FactoryAccess, id: string) { return this.get(this.database, access, id); }

  list(access: FactoryAccess, query: DocumentQuery) {
    return queryPage<IntakeDocument>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT ${COLUMNS} ${JOINS}
      WHERE ($4::text IS NULL OR d.status = $4) AND ($5::uuid IS NULL OR d.lot_id = $5)
    )`, [...scopeValues(access), query.status ?? null, query.lotId ?? null], query, '"createdAt" DESC, id');
  }

  async lot(tx: DatabaseSession, access: FactoryAccess, id: string): Promise<IntakeLot | undefined> {
    const result = await tx.query<IntakeLot>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT l.id, l.tenant_id AS "tenantId", l.factory_id AS "factoryId", l.supplier_id AS "supplierId",
        l.display_code AS "displayCode", l.received_at AS "receivedAt", l.created_at AS "createdAt", l.updated_at AS "updatedAt"
      FROM sobatnira.lots l JOIN authorized_scope scope
        ON scope."tenantId" = l.tenant_id AND scope."factoryId" = l.factory_id
      WHERE l.id = $4::uuid FOR UPDATE OF l`, [...scopeValues(access), id]);
    return result.rows[0];
  }

  async sourceId(tx: DatabaseSession, access: FactoryAccess, requestId: string): Promise<string | undefined> {
    const result = await tx.query<{ id: string }>(`SELECT id FROM sobatnira.intake_documents
      WHERE tenant_id = $1 AND factory_id = $2 AND source = 'synthetic' AND source_request_id = $3`,
    [access.tenantId, access.factoryId, requestId]);
    return result.rows[0]?.id;
  }

  async insert(tx: DatabaseSession, access: FactoryAccess, lotId: string, requestId: string, hash: string, sourcePayload: unknown) {
    const result = await tx.query<{ id: string }>(`INSERT INTO sobatnira.intake_documents
      (tenant_id, factory_id, lot_id, source, source_request_id, source_payload_hash, source_payload)
      VALUES ($1, $2, $3, 'synthetic', $4, $5, $6::jsonb)
      ON CONFLICT (tenant_id, factory_id, source, source_request_id) DO NOTHING RETURNING id`,
    [access.tenantId, access.factoryId, lotId, requestId, hash, JSON.stringify(sourcePayload)]);
    return result.rows[0]?.id;
  }

  revision(tx: DatabaseSession, access: FactoryAccess, id: string, revision: number, fields: IntakeFields, reason?: string,
    evidenceId: string | null = null, origin?: 'evidence_attachment') {
    return tx.query(`INSERT INTO sobatnira.intake_document_revisions
      (tenant_id, factory_id, document_id, revision, fields, origin, actor_id, reason, evidence_id)
      VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8, $9)`,
    [access.tenantId, access.factoryId, id, revision, JSON.stringify(fields),
      origin ?? (revision === 1 ? 'synthetic_extraction' : 'admin_correction'), access.userId, reason ?? null, evidenceId]);
  }

  advance(tx: DatabaseSession, access: FactoryAccess, id: string, revision: number, lotId: string) {
    return tx.query(`UPDATE sobatnira.intake_documents SET current_revision = $4, lot_id = $5, updated_at = clock_timestamp()
      WHERE tenant_id = $1 AND factory_id = $2 AND id = $3`, [access.tenantId, access.factoryId, id, revision, lotId]);
  }

  confirm(tx: DatabaseSession, access: FactoryAccess, id: string, revision: number) {
    return tx.query(`UPDATE sobatnira.intake_documents SET status = 'awaiting_validation', confirmed_revision = $4,
      confirmed_by = $5, confirmed_at = clock_timestamp(), confirmation_source = 'synthetic_admin', updated_at = clock_timestamp()
      WHERE tenant_id = $1 AND factory_id = $2 AND id = $3`, [access.tenantId, access.factoryId, id, revision, access.userId]);
  }

  async existingIntake(tx: DatabaseSession, access: FactoryAccess, lotId: string): Promise<boolean> {
    const result = await tx.query('SELECT id FROM sobatnira.intake_records WHERE tenant_id = $1 AND factory_id = $2 AND lot_id = $3',
      [access.tenantId, access.factoryId, lotId]);
    return result.rows.length > 0;
  }

  async approve(tx: DatabaseSession, access: FactoryAccess, document: IntakeDocument, lot: IntakeLot, fields: IntakeFields) {
    const record = await tx.query<{ id: string; approvedAt: Date }>(`INSERT INTO sobatnira.intake_records
      (tenant_id, factory_id, lot_id, supplier_id, document_id, document_revision, cane_type_code,
        net_weight_kg, brix, occurred_at, approved_by, is_synthetic)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8::numeric, $9::numeric, $10::timestamptz, $11, true)
      RETURNING id, approved_at AS "approvedAt"`,
    [access.tenantId, access.factoryId, lot.id, lot.supplierId, document.id, document.currentRevision,
      fields.caneTypeCode, fields.netWeightKg, fields.brix, fields.occurredAt, access.userId]);
    const intake = record.rows[0];
    await tx.query(`INSERT INTO sobatnira.sugarcane_stock_movements
      (tenant_id, factory_id, lot_id, intake_record_id, movement_type, quantity_delta_kg, occurred_at, is_synthetic)
      VALUES ($1, $2, $3, $4, 'intake', $5::numeric, $6::timestamptz, true)`,
    [access.tenantId, access.factoryId, lot.id, intake.id, fields.netWeightKg, fields.occurredAt]);
    if (lot.receivedAt.toISOString() !== fields.occurredAt) {
      const changed = await tx.query<IntakeLot>(`UPDATE sobatnira.lots SET received_at = $4::timestamptz, updated_at = clock_timestamp()
        WHERE tenant_id = $1 AND factory_id = $2 AND id = $3
        RETURNING id, tenant_id AS "tenantId", factory_id AS "factoryId", supplier_id AS "supplierId", display_code AS "displayCode",
          received_at AS "receivedAt", created_at AS "createdAt", updated_at AS "updatedAt"`,
      [access.tenantId, access.factoryId, lot.id, fields.occurredAt]);
      await tx.query(`INSERT INTO sobatnira.production_audit_events
        (tenant_id, factory_id, entity_type, entity_id, action, actor_id, before_data, after_data)
        VALUES ($1, $2, 'lot', $3, 'updated', $4, $5::jsonb, $6::jsonb)`,
      [access.tenantId, access.factoryId, lot.id, access.userId, JSON.stringify(lot), JSON.stringify(changed.rows[0])]);
    }
    await tx.query(`UPDATE sobatnira.intake_documents SET status = 'approved', approved_revision = current_revision,
      approved_by = $4, approved_at = $5, updated_at = clock_timestamp() WHERE tenant_id = $1 AND factory_id = $2 AND id = $3`,
    [access.tenantId, access.factoryId, document.id, access.userId, intake.approvedAt]);
  }

  event(tx: DatabaseSession, access: FactoryAccess, id: string, action: string, before: IntakeDocument | null, after: IntakeDocument) {
    return tx.query(`INSERT INTO sobatnira.intake_document_events
      (tenant_id, factory_id, document_id, action, actor_id, before_data, after_data)
      VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb)`,
    [access.tenantId, access.factoryId, id, action, access.userId, before ? JSON.stringify(before) : null, JSON.stringify(after)]);
  }

  history(access: FactoryAccess, id: string, page: Pagination) {
    return queryPage<{ id: string }>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT e.id, e.action, e.actor_id AS "actorId", e.before_data AS before, e.after_data AS after, e.occurred_at AS "occurredAt"
      FROM sobatnira.intake_document_events e JOIN authorized_scope scope
        ON scope."tenantId" = e.tenant_id AND scope."factoryId" = e.factory_id WHERE e.document_id = $4::uuid
    )`, [...scopeValues(access), id], page, '"occurredAt" DESC, id');
  }

  revisions(access: FactoryAccess, id: string, page: Pagination) {
    return queryPage<{ id: string }>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT r.document_id::text || ':' || r.revision AS id, r.revision, r.fields, r.origin, r.reason, r.evidence_id AS "evidenceId",
        r.actor_id AS "actorId", r.created_at AS "createdAt"
      FROM sobatnira.intake_document_revisions r JOIN authorized_scope scope
        ON scope."tenantId" = r.tenant_id AND scope."factoryId" = r.factory_id WHERE r.document_id = $4::uuid
    )`, [...scopeValues(access), id], page, 'revision DESC');
  }

  async balance(access: FactoryAccess, synthetic: boolean, lotId?: string) {
    const result = await this.database.query<{ quantityKg: string }>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT COALESCE(sum(m.quantity_delta_kg), 0)::text AS "quantityKg"
      FROM sobatnira.cane_stock_entries m JOIN authorized_scope scope
        ON scope."tenantId" = m.tenant_id AND scope."factoryId" = m.factory_id
      WHERE m.is_synthetic = $4 AND ($5::uuid IS NULL OR m.lot_id = $5)`,
    [...scopeValues(access), synthetic, lotId ?? null]);
    return { material: 'sugarcane', unit: 'kg', synthetic, lotId: lotId ?? null, quantityKg: result.rows[0].quantityKg };
  }
}
