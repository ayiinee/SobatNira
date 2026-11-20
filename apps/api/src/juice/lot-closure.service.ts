import { ConflictException, Injectable } from '@nestjs/common';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService } from '../database/database.service';
import { found, scopeValues } from '../production/production.dto';
import { queryPage } from '../production/production.repository';
import { ClosureCheckService } from './closure-check.service';
import { parseClosureHistory, parseReopen } from './juice.dto';
import { JuiceRepository } from './juice.repository';

interface Closure { closureId: string; closedBy: string; closedAt: Date }
interface Reopening { reopenedBy: string; reopenedAt: Date; reason: string }
interface ClosureHistoryEntry {
  id: string;
  closedBy: string;
  closedAt: Date;
  reopenedBy: string | null;
  reopenedAt: Date | null;
  reason: string | null;
}
const closureColumns = 'id AS "closureId", closed_by AS "closedBy", closed_at AS "closedAt"';
const reopeningColumns = 'reopened_by AS "reopenedBy", reopened_at AS "reopenedAt", reopen_reason AS reason';
const closureScope = 'tenant_id = $1 AND factory_id = $2 AND lot_id = $3 AND is_synthetic = $4';

@Injectable()
export class LotClosureService {
  constructor(private readonly db: DatabaseService, private readonly juice: JuiceRepository,
    private readonly batch: ClosureCheckService) {}

  async status(access: FactoryAccess, lotId: string, synthetic: boolean) {
    const result = await this.db.query<{ closureId: string | null; closedBy: string | null; closedAt: Date | null }>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT c.id AS "closureId", c.closed_by AS "closedBy", c.closed_at AS "closedAt"
      FROM sobatnira.lots l JOIN authorized_scope s ON s."tenantId" = l.tenant_id AND s."factoryId" = l.factory_id
      LEFT JOIN sobatnira.lot_closures c ON c.tenant_id = l.tenant_id AND c.factory_id = l.factory_id
        AND c.lot_id = l.id AND c.is_synthetic = $5 AND c.reopened_at IS NULL WHERE l.id = $4::uuid`,
    [...scopeValues(access), lotId, synthetic]);
    const closure = found(result.rows[0]);
    return { lotId, synthetic, status: closure.closureId ? 'closed' : 'open', ...closure };
  }

  async history(access: FactoryAccess, lotId: string, { synthetic, page }: ReturnType<typeof parseClosureHistory>) {
    await this.status(access, lotId, synthetic);
    return queryPage<ClosureHistoryEntry>(
      this.db, `${FACTORY_SCOPE_CTE}, filtered AS (
        SELECT c.id, c.closed_by AS "closedBy", c.closed_at AS "closedAt", ${reopeningColumns}
        FROM sobatnira.lot_closures c JOIN authorized_scope s
          ON s."tenantId" = c.tenant_id AND s."factoryId" = c.factory_id
        WHERE c.lot_id = $4 AND c.is_synthetic = $5
      )`, [...scopeValues(access), lotId, synthetic], page, '"closedAt" DESC, id',
    );
  }

  close(access: FactoryAccess, lotId: string, synthetic: boolean, authorization: string) {
    return this.juice.mutate(access, async (tx) => {
      await this.juice.lockLots(tx, access, [lotId]);
      const values = [access.tenantId, access.factoryId, lotId, synthetic];
      const existing = (await tx.query<Closure>(`SELECT ${closureColumns} FROM sobatnira.lot_closures
        WHERE ${closureScope} AND reopened_at IS NULL`, values)).rows[0];
      if (existing) return { lotId, synthetic, status: 'closed', ...existing };

      const milled = await tx.query(`SELECT id FROM sobatnira.milling_records
        WHERE tenant_id = $1 AND factory_id = $2 AND lot_id = $3 AND is_synthetic = $4`, values);
      if (!milled.rows.length) throw new ConflictException('Kloter belum memiliki penggilingan sah.');
      const balance = await this.juice.balance(tx, access, lotId, synthetic);
      if (balance.reservedMl !== '0' || balance.onHandMl !== '0') {
        throw new ConflictException('Selesaikan reservasi dan pemakaian atau transfer sisa nira sebelum menutup kloter.');
      }

      // Keep the lot locked until the read-only batch check and closure commit finish.
      await this.batch.requireClear(tx, access, lotId, synthetic, authorization);
      const closure = (await tx.query<Closure>(`INSERT INTO sobatnira.lot_closures
        (tenant_id, factory_id, lot_id, is_synthetic, closed_by) VALUES ($1, $2, $3, $4, $5)
        RETURNING ${closureColumns}`, [...values, access.userId])).rows[0];
      return { lotId, synthetic, status: 'closed', ...closure };
    });
  }

  reopen(access: FactoryAccess, lotId: string, { closureId, synthetic, reason }: ReturnType<typeof parseReopen>) {
    return this.juice.mutate(access, async (tx) => {
      await this.juice.lockLots(tx, access, [lotId]);
      const values = [access.tenantId, access.factoryId, lotId, synthetic, closureId];
      const { rows: [changed] } = await tx.query<Reopening>(`UPDATE sobatnira.lot_closures
        SET reopened_by = $6, reopened_at = clock_timestamp(), reopen_reason = $7
        WHERE ${closureScope} AND id = $5 AND reopened_at IS NULL RETURNING ${reopeningColumns}`,
      [...values, access.userId, reason]);
      if (changed) return { lotId, synthetic, closureId, ...changed };

      const { rows: [previous] } = await tx.query<Reopening>(`SELECT ${reopeningColumns} FROM sobatnira.lot_closures
        WHERE ${closureScope} AND id = $5 AND reopened_at IS NOT NULL`, values);
      if (previous?.reason !== reason) throw new ConflictException('Penutupan tidak cocok atau alasan buka kembali sudah tercatat.');
      return { lotId, synthetic, closureId, ...previous };
    });
  }
}
