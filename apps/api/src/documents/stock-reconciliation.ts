import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseSession } from '../database/database.service';
import { decimal } from '../production/decimal';
import { object, text, uuid } from '../production/production.dto';
import { Revision } from './intake';

export function parseStockReconciliation(input: unknown) {
  const body = object(input, ['revision_id', 'expected_version', 'lot_id', 'quantity', 'reason']);
  return {
    lotId: uuid(body.lot_id, 'lot_id'),
    quantity: decimal(body.quantity, 'quantity', true),
    reason: text(body.reason, 'reason', 500),
  };
}

const publicColumns = `id, material, lot_id, revision_id, previous_revision_id, revision_version,
  trim_scale(quantity_before)::text AS quantity_before, trim_scale(quantity_after)::text AS quantity_after,
  trim_scale(quantity_delta)::text AS quantity_delta, reason, actor_id, created_at`;
interface StockSource { id: string; quantity: string; blocked: boolean; consistent: boolean }

const caneSource = `SELECT i.id, trim_scale(i.net_weight_kg)::text AS quantity,
  EXISTS (SELECT 1 FROM sobatnira.milling_records m WHERE m.tenant_id=i.tenant_id
    AND m.factory_id=i.factory_id AND m.lot_id=i.lot_id) AS blocked,
  i.net_weight_kg = COALESCE((SELECT sum(s.quantity_delta_kg) FROM sobatnira.cane_stock_entries s
    WHERE s.tenant_id=i.tenant_id AND s.factory_id=i.factory_id AND s.lot_id=i.lot_id AND NOT s.is_synthetic),0) AS consistent
  FROM sobatnira.intake_records i
  WHERE i.tenant_id=$1 AND i.factory_id=$2 AND i.lot_id=$3 AND i.ocr_document_id=$4 AND NOT i.is_synthetic`;

const juiceSource = `SELECT m.id, trim_scale(COALESCE(c.quantity_after,m.juice_produced_liters))::text AS quantity,
  (EXISTS (SELECT 1 FROM sobatnira.juice_reservations r WHERE r.tenant_id=m.tenant_id AND r.factory_id=m.factory_id
    AND (r.lot_id=m.lot_id OR r.origin_lot_id=m.lot_id) AND NOT r.is_synthetic AND r.state IN ('reserved','consumed'))
  OR EXISTS (SELECT 1 FROM sobatnira.juice_transfers t WHERE t.tenant_id=m.tenant_id AND t.factory_id=m.factory_id
    AND m.lot_id IN (t.from_lot_id,t.to_lot_id,t.origin_lot_id) AND NOT t.is_synthetic)) AS blocked,
  COALESCE(c.quantity_after,m.juice_produced_liters) * 1000 = COALESCE(
    (SELECT sum(s.on_hand_ml) FROM sobatnira.juice_balance_entries s WHERE s.tenant_id=m.tenant_id
      AND s.factory_id=m.factory_id AND s.lot_id=m.lot_id AND NOT s.is_synthetic),0) AS consistent
  FROM sobatnira.milling_records m LEFT JOIN LATERAL (
    SELECT quantity_after FROM sobatnira.stock_reconciliations WHERE milling_record_id=m.id
    ORDER BY revision_version DESC LIMIT 1
  ) c ON true
  WHERE m.tenant_id=$1 AND m.factory_id=$2 AND m.lot_id=$3 AND m.ocr_document_id=$4 AND NOT m.is_synthetic`;

@Injectable()
export class StockReconciliation {
  async history(db: DatabaseSession, factoryId: string, documentId: string, version: number) {
    const result = await db.query(`SELECT ${publicColumns} FROM sobatnira.stock_reconciliations
      WHERE factory_id=$1 AND document_id=$2 AND revision_version<=$3 ORDER BY revision_version`, [factoryId, documentId, version]);
    return result.rows;
  }

  async post(db: DatabaseSession, access: FactoryAccess, previous: Revision, revision: Revision,
    input: ReturnType<typeof parseStockReconciliation>) {
    const { lotId, quantity, reason } = input;
    const values = [access.tenantId, access.factoryId, lotId];
    // Milling, reservations, transfers and closure use the same lot lock.
    const locked = await db.query(`SELECT id FROM sobatnira.lots WHERE tenant_id=$1 AND factory_id=$2 AND id=$3 FOR UPDATE`, values);
    if (!locked.rows.length) throw new ConflictException('Kloter koreksi tidak tersedia pada pabrik ini.');
    const status = await db.query(`SELECT 1 FROM sobatnira.lot_closures
      WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND NOT is_synthetic`, values);
    if (status.rows.length) throw new ConflictException('Kloter sudah ditutup.');

    const isCane = revision.extraction?.document_type === 'TRUCK_ARRIVAL_NOTE';
    if (isCane && quantity === '0') throw new BadRequestException('Berat bersih harus lebih besar dari nol.');
    const { rows: [record] } = await db.query<StockSource>(isCane ? caneSource : juiceSource, [...values, revision.document_id]);
    if (!record) throw new ConflictException('Nota ini belum membukukan material pada kloter tersebut.');
    if (record.blocked || !record.consistent) {
      throw new ConflictException('Stok sudah dipakai, direservasi, ditransfer, atau tidak sesuai. Koreksi perlu rekonsiliasi lanjutan.');
    }
    if (quantity === record.quantity) throw new BadRequestException('Kuantitas koreksi harus berbeda dari nilai saat ini.');

    if (isCane) {
      await db.query(`UPDATE sobatnira.intake_records SET posted_net_weight_kg=initial_net_weight_kg, net_weight_kg=$2::numeric
        WHERE id=$1`, [record.id, quantity]);
    }
    const result = await db.query(`INSERT INTO sobatnira.stock_reconciliations (
      tenant_id,factory_id,lot_id,material,intake_record_id,milling_record_id,document_id,
      previous_revision_id,revision_id,revision_version,quantity_before,quantity_after,reason,actor_id
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING ${publicColumns}`,
    [...values, isCane ? 'sugarcane' : 'juice', isCane ? record.id : null, isCane ? null : record.id, revision.document_id,
      previous.id, revision.id, revision.version, record.quantity, quantity, reason, access.userId]);
    return result.rows[0];
  }
}
