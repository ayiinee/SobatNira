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

export interface LotSummary extends Lot {
  status: 'open' | 'closed';
  netWeightGrams: string | null;
  caneTypeCode: string | null;
  brix: string | null;
  juiceProducedLiters: string | null;
  intake: ApprovedLotRecord | null;
  milling: ApprovedLotRecord | null;
}

export interface LotDetail extends LotSummary {
  synthetic: boolean;
  closureId: string | null;
  closedAt: Date | null;
  closedBy: string | null;
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

const SUMMARY_COLUMNS = `
  CASE WHEN c.lot_id IS NULL THEN 'open' ELSE 'closed' END AS status,
  trim_scale(i.net_weight_kg * 1000)::text AS "netWeightGrams",
  i.cane_type_code AS "caneTypeCode", trim_scale(i.brix)::text AS brix,
  trim_scale(COALESCE(mc.quantity_after, m.juice_produced_liters))::text AS "juiceProducedLiters",
  ${approvedRecord('i')} AS intake, ${approvedRecord('m')} AS milling`;

function summaryJoins(synthetic: '$5' | 'true' | 'false', page = false) {
  const scope = page ? '(page."tenantId",page."factoryId",page.id)' : '(l.tenant_id,l.factory_id,l.id)';
  return `
      LEFT JOIN sobatnira.intake_records i ON (i.tenant_id,i.factory_id,i.lot_id) = ${scope} AND i.is_synthetic = ${synthetic}
      LEFT JOIN sobatnira.milling_records m ON (m.tenant_id,m.factory_id,m.lot_id) = ${scope} AND m.is_synthetic = ${synthetic}
      LEFT JOIN LATERAL (SELECT revision_id,created_at FROM sobatnira.stock_reconciliations
        WHERE intake_record_id=i.id ORDER BY revision_version DESC LIMIT 1) ic ON true
      LEFT JOIN LATERAL (SELECT revision_id,created_at,quantity_after FROM sobatnira.stock_reconciliations
        WHERE milling_record_id=m.id ORDER BY revision_version DESC LIMIT 1) mc ON true
      LEFT JOIN sobatnira.lot_closures c ON (c.tenant_id,c.factory_id,c.lot_id) = ${scope}
        AND c.is_synthetic = ${synthetic} AND c.reopened_at IS NULL`;
}

function closedLot(synthetic: boolean) {
  return `EXISTS(SELECT 1 FROM sobatnira.lot_closures c
    WHERE (c.tenant_id,c.factory_id,c.lot_id)=(l.tenant_id,l.factory_id,l.id)
      AND c.is_synthetic=${synthetic ? 'true' : 'false'} AND c.reopened_at IS NULL)`;
}

@Injectable()
export class LotsRepository {
  constructor(private readonly database: DatabaseService) {}

  private selection(access: FactoryAccess, query: LotQuery, counts = false) {
    const synthetic = query.synthetic === true;
    const ctes = `${FACTORY_SCOPE_CTE}, filtered AS ${query.pagination === 'cursor' ? 'NOT MATERIALIZED ' : ''}(
      SELECT ${COLUMNS}, s.name AS "supplierName"${query.pagination === 'cursor'
        ? `, to_char(l.received_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "cursorReceivedAt"` : ''}
        ${counts ? `, ${closedLot(synthetic)} AS "isClosed"` : ''}
      FROM sobatnira.lots l
      JOIN authorized_scope scope ON scope."tenantId" = l.tenant_id AND scope."factoryId" = l.factory_id
      JOIN sobatnira.suppliers s ON s.tenant_id = l.tenant_id AND s.id = l.supplier_id
      ${synthetic ? `JOIN sobatnira.intake_records receipt ON (receipt.tenant_id,receipt.factory_id,receipt.lot_id)
        = (l.tenant_id,l.factory_id,l.id) AND receipt.is_synthetic` : ''}
      WHERE ($4::text IS NULL OR ${query.searchMode === 'normalized' ? `
        (regexp_replace(lower($4),'[[:space:]-]','','g') <> '' AND
          (strpos(regexp_replace(lower(COALESCE(l.display_code,l.id::text)),'[[:space:]-]','','g'),regexp_replace(lower($4),'[[:space:]-]','','g')) > 0
           OR strpos(replace(l.id::text,'-',''),regexp_replace(lower($4),'[[:space:]-]','','g')) > 0))`
        : `strpos(lower(COALESCE(l.display_code, '')), lower($4)) > 0`}
        OR strpos(lower(s.name), lower($4)) > 0)
        AND ($5::uuid IS NULL OR l.supplier_id = $5)
        AND ($6::timestamptz IS NULL OR l.received_at >= $6)
        AND ($7::timestamptz IS NULL OR l.received_at < $7)
        AND ($8::uuid IS NULL OR l.id=$8)
        ${query.status ? `AND ${query.status === 'open' ? 'NOT ' : ''}${closedLot(synthetic)}` : ''}
    )`;
    const values = [...scopeValues(access), query.q ?? null, query.supplierId ?? null,
      query.receivedFrom ?? null, query.receivedBefore ?? null, query.lotId ?? null];
    return { ctes, values };
  }

  async counts(access: FactoryAccess, query: LotQuery) {
    const { ctes, values } = this.selection(access, query, true);
    const { rows: [row] } = await this.database.query<{ total: string; open: string; closed: string }>(`WITH ${ctes}
      SELECT count(*) AS total, count(*) FILTER (WHERE NOT "isClosed") AS open,
        count(*) FILTER (WHERE "isClosed") AS closed FROM filtered`, values);
    return { total: Number(row.total), open: Number(row.open), closed: Number(row.closed) };
  }

  async suggestions(access: FactoryAccess, query: LotQuery) {
    const { ctes, values } = this.selection(access, query);
    const { rows } = await this.database.query<Lot & { rank: number }>(`WITH ${ctes}, normalized AS (
      SELECT *, regexp_replace(lower(COALESCE("displayCode",id::text)),'[[:space:]-]','','g') AS code,
        replace(id::text,'-','') AS identifier, regexp_replace(lower($4),'[[:space:]-]','','g') AS term
      FROM filtered
    ), ranked AS (
      SELECT *, CASE WHEN code=term OR identifier=term THEN 0
        WHEN starts_with(code,term) OR starts_with(identifier,term) THEN 1
        WHEN strpos(code,term)>0 OR strpos(identifier,term)>0 THEN 2 ELSE 3 END AS rank
      FROM normalized WHERE term<>''
    ) SELECT id,"tenantId","factoryId","supplierId","supplierName","displayCode","receivedAt","createdAt","updatedAt",rank
      FROM ranked WHERE rank<3 ORDER BY rank, COALESCE("displayCode",id::text) COLLATE "C",id LIMIT $9`,
    [...values, query.limit]);
    return { items: rows };
  }

  list(access: FactoryAccess, query: LotQuery) {
    const synthetic = query.synthetic === true;
    const { ctes, values } = this.selection(access, query);
    const enrichment = query.includeSummary ? {
      columns: `${synthetic ? 'true AS synthetic, ' : ''}summary.*`,
      joins: `LEFT JOIN LATERAL (SELECT ${SUMMARY_COLUMNS} FROM (SELECT 1) seed
        ${summaryJoins(synthetic ? 'true' : 'false', true)}) summary ON page.id IS NOT NULL`,
    } : undefined;
    if (query.pagination === 'cursor') return this.cursorPage(ctes, values, query, enrichment);
    // Keep the legacy response shape, including its complete total.
    return queryPage<Lot | LotSummary>(this.database, ctes, values, query, '"receivedAt" DESC, id', enrichment);
  }

  private async cursorPage(ctes: string, values: unknown[], query: LotQuery, enrichment?: { columns: string; joins: string }) {
    const result = await this.database.query<Lot & { cursorReceivedAt: string }>(`WITH ${ctes}, page AS (
      SELECT * FROM filtered WHERE ($9::timestamptz IS NULL OR
        ("receivedAt" <= $9 AND ("receivedAt" < $9 OR id > $10::uuid)))
      ORDER BY "receivedAt" DESC,id LIMIT $11
    ) SELECT page.*${enrichment ? `, ${enrichment.columns}` : ''} FROM page
      ${enrichment?.joins ?? ''} ORDER BY "receivedAt" DESC,id`,
    [...values, query.after?.receivedAt ?? null, query.after?.id ?? null, query.limit + 1]);
    const rows = result.rows.slice(0, query.limit);
    const last = rows.at(-1);
    return { items: rows.map(({ cursorReceivedAt: _, ...row }) => row), limit: query.limit,
      nextCursor: result.rows.length > query.limit && last
        ? Buffer.from(JSON.stringify([last.cursorReceivedAt, last.id])).toString('base64url') : null };
  }

  async find(access: FactoryAccess, id: string, synthetic = false): Promise<LotDetail | undefined> {
    const result = await this.database.query<LotDetail>(`
      WITH ${FACTORY_SCOPE_CTE}
      SELECT ${COLUMNS}, s.name AS "supplierName", $5::boolean AS synthetic,
        c.id AS "closureId", c.closed_at AS "closedAt", c.closed_by AS "closedBy",
        ${SUMMARY_COLUMNS}
      FROM sobatnira.lots l
      JOIN authorized_scope scope ON scope."tenantId" = l.tenant_id AND scope."factoryId" = l.factory_id
      JOIN sobatnira.suppliers s ON s.tenant_id = l.tenant_id AND s.id = l.supplier_id
      ${summaryJoins('$5')}
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
