import { ConflictException, Injectable } from '@nestjs/common';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService } from '../database/database.service';
import { found, scopeValues } from '../production/production.dto';
import { ClosureCheckService } from './closure-check.service';
import { JuiceRepository } from './juice.repository';

interface Closure { closedBy: string; closedAt: Date }
const closureColumns = 'closed_by AS "closedBy", closed_at AS "closedAt"';

@Injectable()
export class LotClosureService {
  constructor(private readonly db: DatabaseService, private readonly juice: JuiceRepository,
    private readonly batch: ClosureCheckService) {}

  async status(access: FactoryAccess, lotId: string, synthetic: boolean) {
    const result = await this.db.query<{ closedBy: string | null; closedAt: Date | null }>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT c.closed_by AS "closedBy", c.closed_at AS "closedAt"
      FROM sobatnira.lots l JOIN authorized_scope s ON s."tenantId" = l.tenant_id AND s."factoryId" = l.factory_id
      LEFT JOIN sobatnira.lot_closures c ON c.tenant_id = l.tenant_id AND c.factory_id = l.factory_id
        AND c.lot_id = l.id AND c.is_synthetic = $5 WHERE l.id = $4::uuid`,
    [...scopeValues(access), lotId, synthetic]);
    const closure = found(result.rows[0]);
    return { lotId, synthetic, status: closure.closedAt ? 'closed' : 'open', ...closure };
  }

  close(access: FactoryAccess, lotId: string, synthetic: boolean, authorization: string) {
    return this.juice.mutate(access, async (tx) => {
      await this.juice.lockLots(tx, access, [lotId]);
      const values = [access.tenantId, access.factoryId, lotId, synthetic];
      const existing = (await tx.query<Closure>(`SELECT ${closureColumns} FROM sobatnira.lot_closures
        WHERE tenant_id = $1 AND factory_id = $2 AND lot_id = $3 AND is_synthetic = $4`, values)).rows[0];
      if (existing) return { lotId, synthetic, status: 'closed', ...existing };

      const milled = await tx.query(`SELECT id FROM sobatnira.milling_records
        WHERE tenant_id = $1 AND factory_id = $2 AND lot_id = $3 AND is_synthetic = $4`, values);
      if (!milled.rows.length) throw new ConflictException('Kloter belum memiliki penggilingan sah.');
      const balance = await this.juice.balance(tx, access, lotId, synthetic);
      if (balance.reservedMl !== '0' || balance.onHandMl !== '0') {
        throw new ConflictException('Selesaikan reservasi dan pemakaian atau transfer sisa nira sebelum menutup kloter.');
      }

      // Keep the lot locked until the read-only batch check and closure commit finish.
      await this.batch.requireClear(access, lotId, synthetic, authorization);
      const closure = (await tx.query<Closure>(`INSERT INTO sobatnira.lot_closures
        (tenant_id, factory_id, lot_id, is_synthetic, closed_by) VALUES ($1, $2, $3, $4, $5)
        RETURNING ${closureColumns}`, [...values, access.userId])).rows[0];
      return { lotId, synthetic, status: 'closed', ...closure };
    });
  }
}
