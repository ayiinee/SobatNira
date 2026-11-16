import { Injectable } from '@nestjs/common';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService } from '../database/database.service';
import { scopeValues, SupplierInput, SupplierQuery } from '../production/production.dto';
import { queryPage } from '../production/production.repository';

export interface Supplier {
  id: string; tenantId: string; name: string; isActive: boolean; createdAt: Date; updatedAt: Date;
}

const COLUMNS = `s.id, s.tenant_id AS "tenantId", s.name, s.is_active AS "isActive",
  s.created_at AS "createdAt", s.updated_at AS "updatedAt"`;

@Injectable()
export class SuppliersRepository {
  constructor(private readonly database: DatabaseService) {}

  list(access: FactoryAccess, query: SupplierQuery) {
    return queryPage<Supplier>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT ${COLUMNS} FROM sobatnira.suppliers s
      JOIN authorized_scope scope ON scope."tenantId" = s.tenant_id
      WHERE ($4::text IS NULL OR strpos(lower(s.name), lower($4)) > 0)
        AND ($5::boolean IS NULL OR s.is_active = $5)
    )`, [...scopeValues(access), query.q ?? null, query.isActive ?? null], query, 'name, id');
  }

  async find(access: FactoryAccess, id: string): Promise<Supplier | undefined> {
    const result = await this.database.query<Supplier>(`
      WITH ${FACTORY_SCOPE_CTE}
      SELECT ${COLUMNS} FROM sobatnira.suppliers s
      JOIN authorized_scope scope ON scope."tenantId" = s.tenant_id
      WHERE s.id = $4::uuid
    `, [...scopeValues(access), id]);
    return result.rows[0];
  }

  async create(access: FactoryAccess, input: SupplierInput): Promise<Supplier | undefined> {
    const result = await this.database.query<Supplier>(`
      WITH ${FACTORY_SCOPE_CTE}, changed AS (
        INSERT INTO sobatnira.suppliers AS s(tenant_id, name)
        SELECT scope."tenantId", $4 FROM authorized_scope scope
        RETURNING ${COLUMNS}
      ), audited AS (
        INSERT INTO sobatnira.production_audit_events
          (tenant_id, factory_id, entity_type, entity_id, action, actor_id, after_data)
        SELECT c."tenantId", $3::uuid, 'supplier', c.id, 'created', $1::uuid, to_jsonb(c) FROM changed c
      ) SELECT * FROM changed
    `, [...scopeValues(access), input.name]);
    return result.rows[0];
  }

  async update(access: FactoryAccess, id: string, input: SupplierInput): Promise<Supplier | undefined> {
    const result = await this.database.query<Supplier>(`
      WITH ${FACTORY_SCOPE_CTE}, previous AS (
        SELECT ${COLUMNS} FROM sobatnira.suppliers s
        JOIN authorized_scope scope ON scope."tenantId" = s.tenant_id
        WHERE s.id = $4::uuid FOR UPDATE OF s
      ), changed AS (
        UPDATE sobatnira.suppliers AS s SET
          name = COALESCE($5::text, s.name), is_active = COALESCE($6::boolean, s.is_active), updated_at = clock_timestamp()
        FROM previous p WHERE s.id = p.id RETURNING ${COLUMNS}
      ), audited AS (
        INSERT INTO sobatnira.production_audit_events
          (tenant_id, factory_id, entity_type, entity_id, action, actor_id, before_data, after_data)
        SELECT c."tenantId", $3::uuid, 'supplier', c.id, 'updated', $1::uuid, to_jsonb(p), to_jsonb(c)
        FROM changed c JOIN previous p ON p.id = c.id
      ) SELECT * FROM changed
    `, [...scopeValues(access), id, input.name ?? null, input.isActive ?? null]);
    return result.rows[0];
  }
}
