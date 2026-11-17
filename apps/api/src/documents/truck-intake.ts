import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { DatabaseSession } from '../database/database.service';
import { Pagination } from '../production/production.dto';
import { completeFields } from './intake.dto';
import { Field, Note } from './contracts';
import { requireProductionAccess } from './production-access';

type Lot = {
  id: string; tenantId: string; supplierId: string; supplierName: string; displayCode: string | null; receivedAt: Date;
};
const lotColumns = `l.id, l.tenant_id AS "tenantId", l.supplier_id AS "supplierId",
  s.name AS "supplierName", l.display_code AS "displayCode", l.received_at AS "receivedAt"`;
const lots = `FROM sobatnira.lots l JOIN sobatnira.suppliers s ON s.tenant_id=l.tenant_id AND s.id=l.supplier_id
  WHERE l.factory_id=$1 AND s.is_active
  AND NOT EXISTS (SELECT 1 FROM sobatnira.intake_records i
    WHERE i.tenant_id=l.tenant_id AND i.factory_id=l.factory_id AND i.lot_id=l.id)`;

export const postedIntakeColumns = `id, lot_id, supplier_id, net_weight_kg::text AS net_weight_kg,
  occurred_at AS received_at, ocr_document_id AS document_id, ocr_revision_id AS revision_id`;
export type PostedIntake = {
  id: string; lot_id: string; supplier_id: string; net_weight_kg: string; received_at: string;
  document_id: string; revision_id: string;
};

@Injectable()
export class TruckIntake {
  async choices(db: DatabaseSession, userId: string, factoryId: string, page: Pagination) {
    await requireProductionAccess(db, userId, factoryId);
    const { rows } = await db.query<Lot>(`SELECT ${lotColumns} ${lots}
      ORDER BY l.received_at DESC,l.id LIMIT $2 OFFSET $3`, [factoryId, page.limit + 1, page.offset]);
    return { items: rows.slice(0, page.limit), next_offset: rows.length > page.limit ? page.offset + page.limit : null };
  }

  async post(db: DatabaseSession, input: { documentId: string; revisionId: string; userId: string; factoryId: string;
    lotId: string; supplierId: string; note: Note }) {
    const { documentId, revisionId, userId, factoryId, lotId, supplierId, note } = input;
    if (note.document_type !== 'TRUCK_ARRIVAL_NOTE') throw new ConflictException('Jenis revisi tidak cocok dengan penerimaan tebu.');
    await requireProductionAccess(db, userId, factoryId);
    // Lock the same lot as synthetic intake and validate the balance in a fresh statement.
    const { rows: [lot] } = await db.query<Lot>(`SELECT ${lotColumns} FROM sobatnira.lots l
      JOIN sobatnira.suppliers s ON s.tenant_id=l.tenant_id AND s.id=l.supplier_id
      WHERE l.factory_id=$1 AND l.id=$2 AND s.id=$3 AND s.is_active FOR UPDATE OF l FOR SHARE OF s`,
    [factoryId, lotId, supplierId]);
    if (!lot) throw new ConflictException('Kloter atau pemasok tidak tersedia pada pabrik ini. Pilih ulang kloter.');

    const duplicate = await db.query(`SELECT id FROM sobatnira.intake_records
      WHERE (tenant_id=$1 AND factory_id=$2 AND lot_id=$3) OR ocr_document_id=$4 OR ocr_revision_id=$5`,
    [lot.tenantId, factoryId, lot.id, documentId, revisionId]);
    if (duplicate.rows.length) throw new ConflictException('Nota atau kloter sudah dibukukan.');

    const header = note.header as Record<string, Field | undefined> | undefined;
    const read = (key: string) => header?.[key]?.status === 'READ' ? header[key]?.normalized_value : null;
    const weight = read('net_weight_kg');
    const cane = read('cane_type');
    const brix = read('brix');
    if (header?.net_weight_kg?.unit !== 'kg' || (typeof weight !== 'number' && typeof weight !== 'string')) {
      throw new BadRequestException('Lengkapi berat bersih tebu dalam kg pada revisi nota.');
    }
    const fields = completeFields({
      lotId, supplierId: lot.supplierId, occurredAt: lot.receivedAt.toISOString(),
      caneTypeCode: typeof cane === 'string' ? cane.trim() : null,
      netWeightKg: String(weight), brix: brix == null ? null : String(brix),
    });

    // A single statement attaches the exact signed revision and posts its stock credit.
    const { rows: [receipt] } = await db.query<PostedIntake>(`WITH receipt AS (
      INSERT INTO sobatnira.intake_records (tenant_id,factory_id,lot_id,supplier_id,ocr_document_id,ocr_revision_id,
        cane_type_code,net_weight_kg,brix,occurred_at,approved_by,is_synthetic)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,false)
      ON CONFLICT DO NOTHING RETURNING *
    ), movement AS (
      INSERT INTO sobatnira.sugarcane_stock_movements
        (tenant_id,factory_id,lot_id,intake_record_id,movement_type,quantity_delta_kg,occurred_at,is_synthetic)
      SELECT tenant_id,factory_id,lot_id,id,'intake',net_weight_kg,occurred_at,false FROM receipt RETURNING intake_record_id
    )
    SELECT ${postedIntakeColumns} FROM receipt JOIN movement ON movement.intake_record_id=receipt.id`,
    [lot.tenantId, factoryId, lotId, lot.supplierId, documentId, revisionId,
      fields.caneTypeCode, fields.netWeightKg, fields.brix, fields.occurredAt, userId]);
    if (!receipt) throw new ConflictException('Nota atau kloter sudah dibukukan.');
    return receipt;
  }
}
