import { reworkAffectedLots } from './rework';
import { ConflictException } from '@nestjs/common';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseSession } from '../database/database.service';
import { allocate, kilograms, units } from './allocation';
import { calculateProductionPreview } from './calculation';
import { sumDecimals } from './decimal';
import { found } from './production.dto';
import { Grade, ProductionReportLot } from './production-report';

type Batch = { id: string; lot_id: string; code: string; wok_number: number; occurred_at: string;
  quantity_ml: string; physical_weight_kg: string; grades: Grade[];
  origins: { id: string; quantity: string }[] };
type AllocatedBatch = ProductionReportLot['batches'][number] & {
  cookingLotId: string; sourceVolumes: { id: string; quantity: string }[] };

export async function rebuildSnapshots(tx: DatabaseSession, access: FactoryAccess,
  trigger: { id: string; lot_id: string; is_synthetic: boolean }, correctionId: string | null,
  costCorrectionId: string | null = null) {
  const scope = [access.tenantId, access.factoryId, trigger.is_synthetic];
  const batches = (await tx.query<Batch>(`SELECT b.*,quantity_ml::text,physical_weight_kg::text,
    (SELECT jsonb_agg(jsonb_build_object('code',g.code,'weightKg',g.weight_kg::text,
      'pricePerKgRupiah',g.price_per_kg_rupiah::text) ORDER BY g.code)
      FROM sobatnira.batch_grade_results g WHERE g.batch_id=b.id) AS grades,
    (SELECT jsonb_agg(jsonb_build_object('id',r.origin_lot_id,'quantity',r.quantity::text) ORDER BY r.origin_lot_id)
      FROM (SELECT origin_lot_id,sum(quantity_ml) AS quantity FROM sobatnira.juice_reservations
        WHERE batch_id=b.id AND tenant_id=b.tenant_id AND factory_id=b.factory_id AND state='consumed'
        GROUP BY origin_lot_id) r) AS origins
    FROM sobatnira.production_batches b WHERE tenant_id=$1 AND factory_id=$2
      AND is_synthetic=$3 AND status='approved' ORDER BY b.id`, scope)).rows;
  const affected = new Set([trigger.lot_id]);
  let size = -1;
  while (size !== affected.size) {
    size = affected.size;
    for (const b of batches) {
      const ids = [b.lot_id, ...(b.origins ?? []).map(o => o.id)];
      if (ids.some(id => affected.has(id))) ids.forEach(id => affected.add(id));
    }
  }
  const ids = [...affected].sort();
  await tx.query(`SELECT id FROM sobatnira.lots WHERE tenant_id=$1 AND factory_id=$2
    AND id=ANY($3::uuid[]) ORDER BY id FOR UPDATE`, [access.tenantId, access.factoryId, ids]);
  if ((await tx.query(`SELECT 1 FROM sobatnira.lot_closures WHERE tenant_id=$1 AND factory_id=$2
    AND is_synthetic=$3 AND lot_id=ANY($4::uuid[]) AND reopened_at IS NULL`, [...scope, ids])).rows.length)
    throw new ConflictException('Buka kembali seluruh kloter terdampak sebelum mengubah hasil atau biaya.');
  const lots = (await tx.query(`SELECT c.*,i.net_weight_kg::text AS weight FROM sobatnira.lot_production_costs c
    JOIN sobatnira.intake_records i ON (i.tenant_id,i.factory_id,i.lot_id)=(c.tenant_id,c.factory_id,c.lot_id)
    WHERE c.tenant_id=$1 AND c.factory_id=$2 AND i.is_synthetic=$3 AND c.lot_id=ANY($4::uuid[])`, [...scope, ids])).rows;
  if (lots.length !== ids.length) throw new ConflictException('Semua kloter asal memerlukan penerimaan dan biaya resmi.');
  const pending = await reworkAffectedLots(tx,access,trigger.is_synthetic);
  if(ids.some(id => pending.includes(id))) return {id:trigger.id,financialStatus:'REWORK_FINANCIALS_PENDING',affectedLotIds:pending};
  const allocated = new Map<string, AllocatedBatch[]>(ids.map(id => [id, []]));
  const selected = batches.filter(b => affected.has(b.lot_id));
  for (const b of selected) {
    const shares = b.origins?.length ? b.origins : [{ id: b.lot_id, quantity: b.quantity_ml }];
    const perOrigin = new Map(shares.map(s => [s.id, [] as Grade[]]));
    for (const grade of b.grades) {
      for (const [id, value] of allocate(units(grade.weightKg), shares)) {
        if (value) perOrigin.get(id)!.push({ ...grade, weightKg: kilograms(value) });
      }
    }
    for (const s of shares) {
      const grades = perOrigin.get(s.id)!;
      allocated.get(s.id)!.push({ id: b.id, code: b.code, wokNumber: b.wok_number,
        occurredAt: b.occurred_at, quantityMl: s.quantity,
        physicalWeightKg: sumDecimals(grades.map(g => g.weightKg)), grades,
        cookingLotId: b.lot_id,
        consumedByOrigin: [{ originLotId: s.id, lotCode: s.id, quantityMl: s.quantity }],
        sourceVolumes: shares });
    }
  }
  const cooking = new Map(ids.map(id => [id, 0n]));
  const exactRevenue = ids.map(id => ({ id, quantity: allocated.get(id)!.reduce((n, b) =>
    n + b.grades.reduce((v: bigint, g: Grade) => v + units(g.weightKg) * BigInt(g.pricePerKgRupiah), 0n), 0n).toString() }));
  const revenueSum = exactRevenue.reduce((n, r) => n + BigInt(r.quantity), 0n);
  const revenue = revenueSum ? allocate((revenueSum + 500000n) / 1000000n, exactRevenue) : new Map(ids.map(id => [id, 0n]));
  const allocationBasis: unknown[] = [];
  for (const host of lots) {
    const used = new Map<string, string[]>();
    for (const b of selected.filter(b => b.lot_id === host.lot_id)) {
      for (const s of b.origins?.length ? b.origins : [{ id: b.lot_id, quantity: b.quantity_ml }]) {
        used.set(s.id, [...(used.get(s.id) ?? []), s.quantity]);
      }
    }
    if (!used.size) { cooking.set(host.lot_id, cooking.get(host.lot_id)! + BigInt(host.operational_rupiah)); continue; }
    const shares = [...used].map(([id, volumes]) => ({ id, quantity: sumDecimals(volumes) }));
    allocationBasis.push({ cookingLotId: host.lot_id, operationalRupiah: String(host.operational_rupiah), shares });
    for (const [id, value] of allocate(BigInt(host.operational_rupiah), shares)) cooking.set(id, cooking.get(id)! + value);
  }
  let result;
  for (const lot of lots) {
    const rows = allocated.get(lot.lot_id)!;
    const combined = new Map<string, Grade>();
    for (const g of rows.flatMap(row => row.grades as Grade[])) {
      const key = g.code + ':' + g.pricePerKgRupiah, old = combined.get(key);
      combined.set(key, { ...g, weightKg: sumDecimals([old?.weightKg ?? '0', g.weightKg]) });
    }
    const input = { caneNetKg: lot.weight, caneCostRupiah: String(lot.cane_rupiah),
      operationalCostRupiah: cooking.get(lot.lot_id)!.toString(), ingredientCostRupiah: String(lot.ingredient_rupiah),
      otherCostRupiah: String(lot.other_rupiah), rounding: 'HALF_UP',
      grades: [...combined.values()].map((g, i) => ({ ...g, code: 'G_' + i })) };
    // A donor may receive zero after microgram rounding; allow an empty internal result.
    const preview = calculateProductionPreview(input, true);
    const saved = (await tx.query(`INSERT INTO sobatnira.production_calculation_snapshots
      (tenant_id,factory_id,lot_id,batch_id,calculation_version,input_snapshot,output_snapshot,is_synthetic,
        approved_by,correction_id,cost_correction_id)
      VALUES($1,$2,$3,$4,'production-v2',$5,$6,$7,$8,$9,$10) RETURNING *`,
      [access.tenantId, access.factoryId, lot.lot_id, trigger.id,
        JSON.stringify({ ...input, allocatedBatches: rows, allocationBasis, costVersion: lot.version }),
        JSON.stringify({ ...preview, productionValueRupiah: revenue.get(lot.lot_id)!.toString(),
          productionMarginRupiah: (revenue.get(lot.lot_id)! - BigInt(preview.totalCostRupiah)).toString(),
          mode: 'approved', persisted: true, calculationVersion: 'production-v2' }),
        trigger.is_synthetic, access.userId, correctionId, costCorrectionId])).rows[0];
    if (lot.lot_id === trigger.lot_id) result = saved;
  }
  return found(result);
}
