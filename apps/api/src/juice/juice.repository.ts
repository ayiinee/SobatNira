import { ConflictException, ForbiddenException, Injectable } from '@nestjs/common';
import { ACTIVE_ACCESS_SQL, FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { found, scopeValues } from '../production/production.dto';
import { compareDecimals } from '../production/decimal';
import { parseReservation, parseTransfer } from './juice.dto';

type Balance = { onHandMl: string; reservedMl: string; availableMl: string };
type State = 'reserved' | 'consumed' | 'released';
interface Reservation extends ReturnType<typeof parseReservation> {
  lotId: string;
  originLotId: string;
  state: State;
  createdBy: string;
  createdAt: Date;
  finalizedBy: string | null;
  finalizedAt: Date | null;
}
const reservationColumns = `lot_id AS "lotId", origin_lot_id AS "originLotId", request_id AS "requestId", batch_id AS "batchId",
  quantity_ml::text AS "quantityMl", is_synthetic AS synthetic, state,
  created_by AS "createdBy", created_at AS "createdAt", finalized_by AS "finalizedBy", finalized_at AS "finalizedAt"`;
type Transfer = ReturnType<typeof parseTransfer> & { createdBy: string; createdAt: Date };
const transferColumns = `request_id AS "requestId", from_lot_id AS "fromLotId", to_lot_id AS "toLotId",
  origin_lot_id AS "originLotId", quantity_ml::text AS "quantityMl", is_synthetic AS synthetic,
  created_by AS "createdBy", created_at AS "createdAt"`;

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

  balance(tx: DatabaseSession, access: FactoryAccess, lotId: string, synthetic: boolean, originLotId?: string) {
    return tx.query<Balance>(`SELECT
      trim_scale(COALESCE(sum(on_hand_ml), 0))::text AS "onHandMl",
      trim_scale(COALESCE(sum(reserved_ml), 0))::text AS "reservedMl",
      trim_scale(COALESCE(sum(on_hand_ml - reserved_ml), 0))::text AS "availableMl"
      FROM sobatnira.juice_balance_entries WHERE tenant_id = $1 AND factory_id = $2
      AND lot_id = $3 AND is_synthetic = $4 AND ($5::uuid IS NULL OR origin_lot_id = $5)`,
    [...this.scope(access), lotId, synthetic, originLotId ?? null]).then((result) => result.rows[0]);
  }

  async availability(access: FactoryAccess, lotId: string, synthetic: boolean) {
    const result = await this.db.query<Balance & { origins: (Balance & { originLotId: string })[] }>(`
      WITH ${FACTORY_SCOPE_CTE}, scoped_lot AS (
        SELECT l.id, l.tenant_id, l.factory_id FROM sobatnira.lots l JOIN authorized_scope s
          ON l.tenant_id = s."tenantId" AND l.factory_id = s."factoryId" WHERE l.id = $4::uuid
      ), origins AS (
        SELECT e.origin_lot_id, sum(e.on_hand_ml) AS on_hand, sum(e.reserved_ml) AS reserved
          FROM sobatnira.juice_balance_entries e JOIN scoped_lot l
            ON e.tenant_id = l.tenant_id AND e.factory_id = l.factory_id AND e.lot_id = l.id
          WHERE e.is_synthetic = $5 GROUP BY e.origin_lot_id
      )
      SELECT trim_scale(COALESCE(sum(o.on_hand), 0))::text AS "onHandMl",
        trim_scale(COALESCE(sum(o.reserved), 0))::text AS "reservedMl",
        trim_scale(COALESCE(sum(o.on_hand - o.reserved), 0))::text AS "availableMl",
        COALESCE(jsonb_agg(jsonb_build_object('originLotId', o.origin_lot_id,
          'onHandMl', trim_scale(o.on_hand)::text, 'reservedMl', trim_scale(o.reserved)::text,
          'availableMl', trim_scale(o.on_hand - o.reserved)::text) ORDER BY o.origin_lot_id)
          FILTER (WHERE o.origin_lot_id IS NOT NULL), '[]'::jsonb) AS origins
      FROM scoped_lot l LEFT JOIN origins o ON true GROUP BY l.id`, [...scopeValues(access), lotId, synthetic]);
    return { lotId, synthetic, unit: 'ml', ...found(result.rows[0]) };
  }

  async assertAvailable(tx: DatabaseSession, access: FactoryAccess, lotId: string, synthetic: boolean, quantityMl: string, originLotId: string) {
    const balance = await this.balance(tx, access, lotId, synthetic, originLotId);
    if (balance.availableMl.startsWith('-') || compareDecimals(balance.availableMl, quantityMl) < 0) {
      throw new ConflictException('Nira tersedia tidak cukup.');
    }
  }

  private async assertOpen(tx: DatabaseSession, access: FactoryAccess, ids: string[], synthetic: boolean) {
    const closed = await tx.query(`SELECT lot_id FROM sobatnira.lot_closures
      WHERE tenant_id = $1 AND factory_id = $2 AND lot_id = ANY($3::uuid[]) AND is_synthetic = $4`,
    [...this.scope(access), ids, synthetic]);
    if (closed.rows.length) throw new ConflictException('Kloter sudah ditutup.');
  }

  reserve(access: FactoryAccess, lotId: string, input: ReturnType<typeof parseReservation>) {
    return this.mutate(access, async (tx) => {
      await this.lockRequest(tx, access, 'reserve', input.requestId);
      await this.lockLots(tx, access, [lotId]);
      const scope = this.scope(access);
      const originLotId = input.originLotId ?? lotId;
      const existing = (await tx.query<Reservation>(`SELECT ${reservationColumns} FROM sobatnira.juice_reservations
        WHERE tenant_id = $1 AND factory_id = $2 AND request_id = $3`, [...scope, input.requestId])).rows[0];
      if (existing) {
        if (existing.lotId !== lotId || existing.originLotId !== originLotId || existing.batchId !== input.batchId || existing.synthetic !== input.synthetic
          || compareDecimals(existing.quantityMl, input.quantityMl) !== 0) {
          throw new ConflictException('requestId sudah digunakan untuk reservasi berbeda.');
        }
        return existing;
      }
      await this.assertOpen(tx, access, [lotId], input.synthetic);
      await this.assertAvailable(tx, access, lotId, input.synthetic, input.quantityMl, originLotId);
      return (await tx.query<Reservation>(`INSERT INTO sobatnira.juice_reservations
        (tenant_id, factory_id, lot_id, request_id, batch_id, quantity_ml, is_synthetic, created_by, origin_lot_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING ${reservationColumns}`,
      [...scope, lotId, input.requestId, input.batchId, input.quantityMl, input.synthetic, access.userId, originLotId])).rows[0];
    });
  }

  transfer(access: FactoryAccess, input: ReturnType<typeof parseTransfer>) {
    return this.mutate(access, async (tx) => {
      await this.lockRequest(tx, access, 'transfer', input.requestId);
      await this.lockLots(tx, access, [input.fromLotId, input.toLotId]);
      const scope = this.scope(access);
      const existing = (await tx.query<Transfer>(`SELECT ${transferColumns} FROM sobatnira.juice_transfers
        WHERE tenant_id = $1 AND factory_id = $2 AND request_id = $3`, [...scope, input.requestId])).rows[0];
      if (existing) {
        if (existing.fromLotId !== input.fromLotId || existing.toLotId !== input.toLotId || existing.originLotId !== input.originLotId
          || existing.synthetic !== input.synthetic || compareDecimals(existing.quantityMl, input.quantityMl) !== 0) {
          throw new ConflictException('requestId sudah digunakan untuk transfer berbeda.');
        }
        return existing;
      }
      await this.assertOpen(tx, access, [input.fromLotId, input.toLotId], input.synthetic);
      await this.assertAvailable(tx, access, input.fromLotId, input.synthetic, input.quantityMl, input.originLotId);
      return (await tx.query<Transfer>(`INSERT INTO sobatnira.juice_transfers
        (tenant_id, factory_id, request_id, from_lot_id, to_lot_id, origin_lot_id, quantity_ml, is_synthetic, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING ${transferColumns}`,
      [...scope, input.requestId, input.fromLotId, input.toLotId, input.originLotId, input.quantityMl,
        input.synthetic, access.userId])).rows[0];
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
