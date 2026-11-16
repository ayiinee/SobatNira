import { ConflictException, ForbiddenException, Injectable } from '@nestjs/common';
import { ACTIVE_ACCESS_SQL, FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { found, scopeValues } from '../production/production.dto';
import { compareDecimals } from '../production/decimal';
import { parseReservation } from './juice.dto';

type Balance = { onHandMl: string; reservedMl: string; availableMl: string };
type State = 'reserved' | 'consumed' | 'released';
interface Reservation extends ReturnType<typeof parseReservation> {
  lotId: string;
  state: State;
  createdBy: string;
  createdAt: Date;
  finalizedBy: string | null;
  finalizedAt: Date | null;
}
const reservationColumns = `lot_id AS "lotId", request_id AS "requestId", batch_id AS "batchId",
  quantity_ml::text AS "quantityMl", is_synthetic AS synthetic, state,
  created_by AS "createdBy", created_at AS "createdAt", finalized_by AS "finalizedBy", finalized_at AS "finalizedAt"`;

@Injectable()
export class JuiceRepository {
  constructor(private readonly db: DatabaseService) {}

  private scope(access: FactoryAccess) {
    return [access.tenantId, access.factoryId];
  }

  mutate<T>(access: FactoryAccess, work: (tx: DatabaseSession) => Promise<T>) {
    return this.db.transaction(async (tx) => {
      const membership = await tx.query(`${ACTIVE_ACCESS_SQL}
        AND fm.tenant_id = $2::uuid AND fm.factory_id = $3::uuid AND fm.role IN ('admin', 'owner')
        FOR SHARE OF fm, tm, f, t`, scopeValues(access));
      if (!membership.rows.length) throw new ForbiddenException('Akses pabrik tidak lagi tersedia.');
      return work(tx);
    });
  }

  async lockLots(tx: DatabaseSession, access: FactoryAccess, ids: string[]) {
    const result = await tx.query(`SELECT id FROM sobatnira.lots
      WHERE tenant_id = $1 AND factory_id = $2 AND id = ANY($3::uuid[]) ORDER BY id FOR UPDATE`,
    [...this.scope(access), ids]);
    if (result.rows.length !== ids.length) found(undefined);
  }

  async lockRequest(tx: DatabaseSession, access: FactoryAccess, kind: string, requestId: string) {
    await tx.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
      [`sobatnira:juice:${kind}:${access.tenantId}:${access.factoryId}:${requestId}`]);
  }

  balance(tx: DatabaseSession, access: FactoryAccess, lotId: string, synthetic: boolean) {
    return tx.query<Balance>(`SELECT
      trim_scale(COALESCE(sum(on_hand_ml), 0))::text AS "onHandMl",
      trim_scale(COALESCE(sum(reserved_ml), 0))::text AS "reservedMl",
      trim_scale(COALESCE(sum(on_hand_ml - reserved_ml), 0))::text AS "availableMl"
      FROM sobatnira.juice_balance_entries WHERE tenant_id = $1 AND factory_id = $2
      AND lot_id = $3 AND is_synthetic = $4`, [...this.scope(access), lotId, synthetic]).then((result) => result.rows[0]);
  }

  async availability(access: FactoryAccess, lotId: string, synthetic: boolean) {
    const result = await this.db.query<Balance>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT trim_scale(COALESCE(sum(e.on_hand_ml), 0))::text AS "onHandMl",
        trim_scale(COALESCE(sum(e.reserved_ml), 0))::text AS "reservedMl",
        trim_scale(COALESCE(sum(e.on_hand_ml - e.reserved_ml), 0))::text AS "availableMl"
      FROM sobatnira.lots l JOIN authorized_scope s
        ON l.tenant_id = s."tenantId" AND l.factory_id = s."factoryId"
      LEFT JOIN sobatnira.juice_balance_entries e ON e.tenant_id = l.tenant_id
        AND e.factory_id = l.factory_id AND e.lot_id = l.id AND e.is_synthetic = $5
      WHERE l.id = $4::uuid GROUP BY l.id`, [...scopeValues(access), lotId, synthetic]);
    return { lotId, synthetic, unit: 'ml', ...found(result.rows[0]) };
  }

  async assertAvailable(tx: DatabaseSession, access: FactoryAccess, lotId: string, synthetic: boolean, quantityMl: string) {
    const balance = await this.balance(tx, access, lotId, synthetic);
    if (balance.availableMl.startsWith('-') || compareDecimals(balance.availableMl, quantityMl) < 0) {
      throw new ConflictException('Nira tersedia tidak cukup.');
    }
  }

  reserve(access: FactoryAccess, lotId: string, input: ReturnType<typeof parseReservation>) {
    return this.mutate(access, async (tx) => {
      await this.lockRequest(tx, access, 'reserve', input.requestId);
      await this.lockLots(tx, access, [lotId]);
      const scope = this.scope(access);
      const existing = (await tx.query<Reservation>(`SELECT ${reservationColumns} FROM sobatnira.juice_reservations
        WHERE tenant_id = $1 AND factory_id = $2 AND request_id = $3`, [...scope, input.requestId])).rows[0];
      if (existing) {
        if (existing.lotId !== lotId || existing.batchId !== input.batchId || existing.synthetic !== input.synthetic
          || compareDecimals(existing.quantityMl, input.quantityMl) !== 0) {
          throw new ConflictException('requestId sudah digunakan untuk reservasi berbeda.');
        }
        return existing;
      }
      await this.assertAvailable(tx, access, lotId, input.synthetic, input.quantityMl);
      return (await tx.query<Reservation>(`INSERT INTO sobatnira.juice_reservations
        (tenant_id, factory_id, lot_id, request_id, batch_id, quantity_ml, is_synthetic, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING ${reservationColumns}`,
      [...scope, lotId, input.requestId, input.batchId, input.quantityMl, input.synthetic, access.userId])).rows[0];
    });
  }

  finalize(access: FactoryAccess, lotId: string, requestId: string, state: Exclude<State, 'reserved'>) {
    return this.mutate(access, async (tx) => {
      await this.lockLots(tx, access, [lotId]);
      const values = [...this.scope(access), lotId, requestId];
      const existing = found((await tx.query<Reservation>(`SELECT ${reservationColumns} FROM sobatnira.juice_reservations
        WHERE tenant_id = $1 AND factory_id = $2 AND lot_id = $3 AND request_id = $4`, values)).rows[0]);
      if (existing.state === state) return existing;
      if (existing.state !== 'reserved') throw new ConflictException('Reservasi sudah difinalisasi dengan aksi berbeda.');
      return (await tx.query<Reservation>(`UPDATE sobatnira.juice_reservations
        SET state = $5, finalized_by = $6, finalized_at = clock_timestamp()
        WHERE tenant_id = $1 AND factory_id = $2 AND lot_id = $3 AND request_id = $4 RETURNING ${reservationColumns}`,
      [...values, state, access.userId])).rows[0];
    });
  }
}
