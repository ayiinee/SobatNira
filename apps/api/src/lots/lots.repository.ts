import { ConflictException, Injectable } from '@nestjs/common';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService } from '../database/database.service';
import { LotInput, LotQuery, scopeValues } from '../production/production.dto';
import { queryPage } from '../production/production.repository';

export interface Lot {
  id: string; tenantId: string; factoryId: string; supplierId: string; supplierName: string;
  displayCode: string | null; receivedAt: Date; createdAt: Date; updatedAt: Date;
}

interface ApprovedLotRecord {
  id: string;
  approvedAt: string;
  document: {
    source: 'ocr' | 'synthetic';
    documentId: string;
    revisionId: string | null;
    revisionNumber: number | null;
  };
}

export interface LotDetail extends Lot {
  synthetic: boolean;
  status: 'open' | 'closed';
  closedAt: Date | null;
  closedBy: string | null;
  netWeightGrams: string | null;
  intake: ApprovedLotRecord | null;
  milling: ApprovedLotRecord | null;
}

const COLUMNS = `l.id, l.tenant_id AS "tenantId", l.factory_id AS "factoryId", l.supplier_id AS "supplierId",
  l.display_code AS "displayCode", l.received_at AS "receivedAt", l.created_at AS "createdAt", l.updated_at AS "updatedAt"`;

function approvedRecord(alias: 'i' | 'm') {
  const correction = alias === 'i' ? 'ic' : 'mc';
  return `CASE WHEN ${alias}.id IS NOT NULL THEN jsonb_build_object(
    'id', ${alias}.id, 'approvedAt', COALESCE(${correction}.created_at,${alias}.approved_at),
    'document', jsonb_build_object(
      'source', CASE WHEN ${alias}.is_synthetic THEN 'synthetic' ELSE 'ocr' END,
      'documentId', COALESCE(${alias}.ocr_document_id, ${alias}.document_id),
      'revisionId', COALESCE(${correction}.revision_id,${alias}.ocr_revision_id),
      'revisionNumber', ${alias}.document_revision
    )
  ) END`;
}

@Injectable()
export class LotsRepository {
  constructor(private readonly database: DatabaseService) {}

  list(access: FactoryAccess, query: LotQuery) {
    return queryPage<Lot>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT ${COLUMNS}, s.name AS "supplierName" FROM sobatnira.lots l
      JOIN authorized_scope scope ON scope."tenantId" = l.tenant_id AND scope."factoryId" = l.factory_id
      JOIN sobatnira.suppliers s ON s.tenant_id = l.tenant_id AND s.id = l.supplier_id
      WHERE ($4::text IS NULL OR strpos(lower(COALESCE(l.display_code, '')), lower($4)) > 0 OR strpos(lower(s.name), lower($4)) > 0)
        AND ($5::uuid IS NULL OR l.supplier_id = $5)
        AND ($6::timestamptz IS NULL OR l.received_at >= $6)
        AND ($7::timestamptz IS NULL OR l.received_at < $7)
    )`, [...scopeValues(access), query.q ?? null, query.supplierId ?? null,
      query.receivedFrom ?? null, query.receivedBefore ?? null], query, '"receivedAt" DESC, id');
  }

  async find(access: FactoryAccess, id: string, synthetic = false): Promise<LotDetail | undefined> {
    const result = await this.database.query<LotDetail>(`
      WITH ${FACTORY_SCOPE_CTE}
      SELECT ${COLUMNS}, s.name AS "supplierName", $5::boolean AS synthetic,
        CASE WHEN c.lot_id IS NULL THEN 'open' ELSE 'closed' END AS status,
        c.closed_at AS "closedAt", c.closed_by AS "closedBy",
        trim_scale(i.net_weight_kg * 1000)::text AS "netWeightGrams",
        ${approvedRecord('i')} AS intake, ${approvedRecord('m')} AS milling
      FROM sobatnira.lots l
      JOIN authorized_scope scope ON scope."tenantId" = l.tenant_id AND scope."factoryId" = l.factory_id
      JOIN sobatnira.suppliers s ON s.tenant_id = l.tenant_id AND s.id = l.supplier_id
      LEFT JOIN sobatnira.intake_records i ON i.tenant_id = l.tenant_id AND i.factory_id = l.factory_id
        AND i.lot_id = l.id AND i.is_synthetic = $5
      LEFT JOIN sobatnira.milling_records m ON m.tenant_id = l.tenant_id AND m.factory_id = l.factory_id
        AND m.lot_id = l.id AND m.is_synthetic = $5
      LEFT JOIN LATERAL (SELECT revision_id,created_at FROM sobatnira.stock_reconciliations
        WHERE intake_record_id=i.id ORDER BY revision_version DESC LIMIT 1) ic ON true
      LEFT JOIN LATERAL (SELECT revision_id,created_at FROM sobatnira.stock_reconciliations
        WHERE milling_record_id=m.id ORDER BY revision_version DESC LIMIT 1) mc ON true
      LEFT JOIN sobatnira.lot_closures c ON c.tenant_id = l.tenant_id AND c.factory_id = l.factory_id
        AND c.lot_id = l.id AND c.is_synthetic = $5
      WHERE l.id = $4::uuid
    `, [...scopeValues(access), id, synthetic]);
    return result.rows[0];
  }

  async create(access: FactoryAccess, input: LotInput): Promise<Lot | undefined> {
    const result = await this.database.query<Lot>(`
      WITH ${FACTORY_SCOPE_CTE}, eligible_supplier AS (
        SELECT s.id, s.tenant_id FROM sobatnira.suppliers s
        JOIN authorized_scope scope ON scope."tenantId" = s.tenant_id
        WHERE s.id = $4::uuid AND s.is_active FOR SHARE OF s
      ), changed AS (
        INSERT INTO sobatnira.lots AS l(tenant_id, factory_id, supplier_id, display_code, received_at)
        SELECT s.tenant_id, $3::uuid, s.id, $5::text, $6::timestamptz FROM eligible_supplier s
        RETURNING ${COLUMNS}
      ), audited AS (
        INSERT INTO sobatnira.production_audit_events
          (tenant_id, factory_id, entity_type, entity_id, action, actor_id, after_data)
        SELECT c."tenantId", c."factoryId", 'lot', c.id, 'created', $1::uuid, to_jsonb(c) FROM changed c
      ) SELECT c.*, s.name AS "supplierName" FROM changed c
        JOIN sobatnira.suppliers s ON s.tenant_id = c."tenantId" AND s.id = c."supplierId"
    `, [...scopeValues(access), input.supplierId, input.displayCode ?? null, input.receivedAt]);
    return result.rows[0];
  }

  async update(access: FactoryAccess, id: string, input: LotInput): Promise<Lot | undefined> {
    return this.database.transaction(async (tx) => {
      const locked = await tx.query<{ supplierId: string; receivedAt: Date }>(`WITH ${FACTORY_SCOPE_CTE}
        SELECT l.supplier_id AS "supplierId", l.received_at AS "receivedAt" FROM sobatnira.lots l
        JOIN authorized_scope scope ON scope."tenantId" = l.tenant_id AND scope."factoryId" = l.factory_id
        WHERE l.id = $4::uuid FOR UPDATE OF l`, [...scopeValues(access), id]);
      const lot = locked.rows[0];
      if (!lot) return undefined;
      const changesOfficialFields = (input.supplierId !== undefined && input.supplierId !== lot.supplierId) ||
        (input.receivedAt !== undefined && Date.parse(input.receivedAt) !== lot.receivedAt.getTime());
      if (changesOfficialFields) {
        const approved = await tx.query(`SELECT id FROM sobatnira.intake_records
          WHERE tenant_id = $1 AND factory_id = $2 AND lot_id = $3`, [access.tenantId, access.factoryId, id]);
        if (approved.rows.length) throw new ConflictException('Metadata penerimaan sah harus diubah melalui alur koreksi resmi.');
      }
      const result = await tx.query<Lot>(`
      WITH ${FACTORY_SCOPE_CTE}, previous AS (
        SELECT ${COLUMNS} FROM sobatnira.lots l
        JOIN authorized_scope scope ON scope."tenantId" = l.tenant_id AND scope."factoryId" = l.factory_id
        JOIN sobatnira.suppliers s ON s.tenant_id = l.tenant_id AND s.id = COALESCE($5::uuid, l.supplier_id)
        WHERE l.id = $4::uuid AND ($5::uuid IS NULL OR $5 = l.supplier_id OR s.is_active)
        FOR UPDATE OF l FOR SHARE OF s
      ), changed AS (
        UPDATE sobatnira.lots AS l SET
          supplier_id = COALESCE($5::uuid, l.supplier_id),
          display_code = CASE WHEN $6::boolean THEN $7::text ELSE l.display_code END,
          received_at = COALESCE($8::timestamptz, l.received_at), updated_at = clock_timestamp()
        FROM previous p WHERE l.id = p.id RETURNING ${COLUMNS}
      ), audited AS (
        INSERT INTO sobatnira.production_audit_events
          (tenant_id, factory_id, entity_type, entity_id, action, actor_id, before_data, after_data)
        SELECT c."tenantId", c."factoryId", 'lot', c.id, 'updated', $1::uuid, to_jsonb(p), to_jsonb(c)
        FROM changed c JOIN previous p ON p.id = c.id
      ) SELECT c.*, s.name AS "supplierName" FROM changed c
        JOIN sobatnira.suppliers s ON s.tenant_id = c."tenantId" AND s.id = c."supplierId"
    `, [...scopeValues(access), id, input.supplierId ?? null, 'displayCode' in input,
      input.displayCode ?? null, input.receivedAt ?? null]);
      return result.rows[0];
    });
  }
}
