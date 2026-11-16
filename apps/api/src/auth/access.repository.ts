import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { FactoryAccess, FactoryRole } from './auth.types';
import { ACTIVE_ACCESS_SQL as ACTIVE_ACCESS } from './access.sql';

// Every access read joins current active tenant, factory and both memberships.
// There is no cache that can retain a revoked role until a JWT expires.
@Injectable()
export class AccessRepository {
  constructor(private readonly database: DatabaseService) {}

  async listAccess(userId: string): Promise<FactoryAccess[]> {
    const result = await this.database.query<FactoryAccess>(
      `${ACTIVE_ACCESS} ORDER BY t.name, f.name, f.id`, [userId],
    );
    return result.rows;
  }

  async findFactoryAccess(userId: string, tenantId: string, factoryId: string): Promise<FactoryAccess | undefined> {
    const result = await this.database.query<FactoryAccess>(
      `${ACTIVE_ACCESS} AND fm.tenant_id = $2::uuid AND fm.factory_id = $3::uuid`,
      [userId, tenantId, factoryId],
    );
    return result.rows[0];
  }

  async listFactoryMembers(access: FactoryAccess) {
    const result = await this.database.query<{ userId: string; role: FactoryRole; isActive: boolean }>(`
      WITH authorized_factory AS (
        ${ACTIVE_ACCESS} AND fm.tenant_id = $2::uuid AND fm.factory_id = $3::uuid AND fm.role = 'owner'
      )
      SELECT fm.user_id AS "userId", fm.role, (fm.is_active AND tm.is_active) AS "isActive"
      FROM sobatnira.factory_memberships fm
      JOIN sobatnira.tenant_memberships tm ON tm.tenant_id = fm.tenant_id AND tm.user_id = fm.user_id
      JOIN authorized_factory allowed ON allowed."tenantId" = fm.tenant_id AND allowed."factoryId" = fm.factory_id
      ORDER BY fm.user_id
    `, [access.userId, access.tenantId, access.factoryId]);
    return result.rows;
  }
}
