import { ConflictException, Injectable } from '@nestjs/common';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService } from '../database/database.service';
import { CatalogQuery, scopeValues } from '../production/production.dto';
import { queryPage } from '../production/production.repository';
import { parseCaneTypeCreate, parseCaneTypeUpdate } from './cane-types.dto';

interface CaneType {
  id: string;
  tenantId: string;
  code: string;
  name: string;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const COLUMNS = `ct.id, ct.tenant_id AS "tenantId", ct.code, ct.name, ct.is_active AS "isActive",
  ct.created_at AS "createdAt", ct.updated_at AS "updatedAt"`;

@Injectable()
export class CaneTypesRepository {
  constructor(private readonly database: DatabaseService) {}

  list(access: FactoryAccess, query: CatalogQuery) {
    return queryPage<CaneType>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT ${COLUMNS} FROM sobatnira.cane_types ct
      JOIN authorized_scope scope ON scope."tenantId" = ct.tenant_id
      WHERE ($4::text IS NULL OR strpos(lower(ct.code), lower($4)) > 0 OR strpos(lower(ct.name), lower($4)) > 0)
        AND ($5::boolean IS NULL OR ct.is_active = $5)
    )`, [...scopeValues(access), query.q ?? null, query.isActive ?? null], query, 'code, id');
  }

  async find(access: FactoryAccess, id: string): Promise<CaneType | undefined> {
    const { rows: [row] } = await this.database.query<CaneType>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT ${COLUMNS} FROM sobatnira.cane_types ct
      JOIN authorized_scope scope ON scope."tenantId" = ct.tenant_id
      WHERE ct.id = $4::uuid`, [...scopeValues(access), id]);
    return row;
  }

  async create(access: FactoryAccess, input: ReturnType<typeof parseCaneTypeCreate>): Promise<CaneType | undefined> {
    const { rows: [result] } = await this.database.query<(CaneType | { id: null }) & { authorized: boolean }>(`
      WITH ${FACTORY_SCOPE_CTE}, changed AS (
        INSERT INTO sobatnira.cane_types AS ct(tenant_id, code, name)
        SELECT scope."tenantId", $4, $5 FROM authorized_scope scope
        ON CONFLICT (tenant_id, code) DO NOTHING RETURNING ${COLUMNS}
      ), audited AS (
        INSERT INTO sobatnira.production_audit_events
          (tenant_id, factory_id, entity_type, entity_id, action, actor_id, after_data)
        SELECT c."tenantId", $3::uuid, 'cane_type', c.id, 'created', $1::uuid, to_jsonb(c) FROM changed c
      ), allowed AS (SELECT EXISTS (SELECT 1 FROM authorized_scope) AS authorized)
      SELECT allowed.authorized, c.* FROM allowed LEFT JOIN changed c ON true
    `, [...scopeValues(access), input.code, input.name]);
    const { authorized, ...item } = result;
    if (!authorized) return undefined;
    if (item.id === null) throw new ConflictException('Kode jenis tebu sudah terdaftar pada tenant ini.');
    return item;
  }

  async update(access: FactoryAccess, id: string, input: ReturnType<typeof parseCaneTypeUpdate>): Promise<CaneType | undefined> {
    const { rows: [row] } = await this.database.query<CaneType>(`
      WITH ${FACTORY_SCOPE_CTE}, previous AS (
        SELECT ${COLUMNS} FROM sobatnira.cane_types ct
        JOIN authorized_scope scope ON scope."tenantId" = ct.tenant_id
        WHERE ct.id = $4::uuid FOR UPDATE OF ct
      ), changed AS (
        UPDATE sobatnira.cane_types AS ct SET
          name = COALESCE($5::text, p.name), is_active = COALESCE($6::boolean, p."isActive"), updated_at = clock_timestamp()
        FROM previous p WHERE ct.id = p.id
          AND (p.name, p."isActive") IS DISTINCT FROM (COALESCE($5::text, p.name), COALESCE($6::boolean, p."isActive"))
        RETURNING ${COLUMNS}
      ), audited AS (
        INSERT INTO sobatnira.production_audit_events
          (tenant_id, factory_id, entity_type, entity_id, action, actor_id, before_data, after_data)
        SELECT c."tenantId", $3::uuid, 'cane_type', c.id, 'updated', $1::uuid, to_jsonb(p), to_jsonb(c)
        FROM changed c JOIN previous p ON p.id = c.id
      ) SELECT * FROM changed UNION ALL SELECT * FROM previous WHERE NOT EXISTS (SELECT 1 FROM changed)
    `, [...scopeValues(access), id, input.name ?? null, input.isActive ?? null]);
    return row;
  }
}
