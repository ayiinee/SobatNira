import { Injectable } from '@nestjs/common';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { Pagination, scopeValues } from './production.dto';

export interface Page<T> { items: T[]; total: number; limit: number; offset: number }

// CTEs and ORDER BY fragments are fixed source code, never client input.
export async function queryPage<T extends { id: string }>(
  database: DatabaseSession, ctes: string, values: unknown[], page: Pagination, order: string,
): Promise<Page<T>> {
  const result = await database.query<T & { total: string }>(`
    WITH ${ctes}, page AS (
      SELECT * FROM filtered ORDER BY ${order} LIMIT $${values.length + 1}::int OFFSET $${values.length + 2}::int
    )
    SELECT page.*, totals.total FROM (SELECT count(*) AS total FROM filtered) totals
    LEFT JOIN page ON true ORDER BY ${order}
  `, [...values, page.limit, page.offset]);
  return {
    items: result.rows.filter((row) => row.id !== null).map(({ total: _total, ...row }) => row as unknown as T),
    total: Number(result.rows[0]?.total ?? 0), limit: page.limit, offset: page.offset,
  };
}

@Injectable()
export class ProductionHistoryRepository {
  constructor(private readonly database: DatabaseService) {}

  list(access: FactoryAccess, entity: 'supplier' | 'lot' | 'cane_type', id: string, page: Pagination) {
    return queryPage<{ id: string; action: string; actorId: string; before: unknown; after: unknown; occurredAt: Date }>(
      this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
        SELECT e.id, e.action, e.actor_id AS "actorId", e.before_data AS before,
          e.after_data AS after, e.occurred_at AS "occurredAt"
        FROM sobatnira.production_audit_events e
        JOIN authorized_scope scope ON scope."tenantId" = e.tenant_id AND scope."factoryId" = e.factory_id
        WHERE e.entity_type = $4 AND e.entity_id = $5::uuid
      )`, [...scopeValues(access), entity, id], page, '"occurredAt" DESC, id',
    );
  }
}
