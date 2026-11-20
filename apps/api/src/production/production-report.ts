import { compareDecimals, sumDecimals } from './decimal';

export type Grade = { code: string; weightKg: string; pricePerKgRupiah: string };
type OriginVolume = { originLotId: string; lotCode: string; quantityMl: string };
type Batch = { id: string; code: string; wokNumber: number; occurredAt: string; quantityMl: string; physicalWeightKg: string;
  grades: Grade[]; consumedByOrigin?: OriginVolume[] };
type Calculation = { finalSugarKg: string; rendemenPercent: string; productionValueRupiah: string; totalCostRupiah: string; productionMarginRupiah: string; costs: Record<string, string> };
export type ProductionReportLot = {
  lotId: string; code: string; supplier: string; receivedAt: string;
  caneNetKg: string; caneType: string | null; juiceLiters: string | null;
  closed?: boolean;
  calculationSnapshotId?: string | null;
  calculationVersion?: string | null;
  calculation: Calculation | null; batches: Batch[];
};

// Preserve fractional rupiah at grade/batch level. Only the persisted lot
// snapshot defines rounded revenue and margin; no batch cost allocation is inferred.
function exactValue(grade: Grade): string {
  const [whole, fraction = ''] = grade.weightKg.split('.');
  const scale = 10n ** BigInt(fraction.length);
  const value = BigInt(whole + fraction) * BigInt(grade.pricePerKgRupiah);
  return fraction.length
    ? `${value / scale}.${(value % scale).toString().padStart(fraction.length, '0')}`.replace(/0+$/, '').replace(/\.$/, '')
    : value.toString();
}

export function batchGradeTotals(grades: Grade[]) {
  const results = grades.map(grade => ({ ...grade, exactValueRupiah: exactValue(grade) }));
  return { grades: results, finalSugarKg: sumDecimals(results.map(grade => grade.weightKg)),
    exactValueRupiah: sumDecimals(results.map(grade => grade.exactValueRupiah)) };
}

export function productionReport(items: ProductionReportLot[]) {
  const grades = new Map<string, { code: string; weightKg: string; exactValueRupiah: string }>();
  const lots = items.map(lot => ({ ...lot, batches: lot.batches.map(batch => {
    const totals = batchGradeTotals(batch.grades);
    for (const grade of totals.grades) {
      const previous = grades.get(grade.code);
      grades.set(grade.code, { code: grade.code,
        weightKg: sumDecimals([previous?.weightKg ?? '0', grade.weightKg]),
        exactValueRupiah: sumDecimals([previous?.exactValueRupiah ?? '0', grade.exactValueRupiah]) });
    }
    return { ...batch, ...totals };
  }) }));
  const produced = items.flatMap(lot => lot.calculation ? [lot.calculation] : []);
  const money = (field: 'productionValueRupiah' | 'totalCostRupiah' | 'productionMarginRupiah') =>
    produced.reduce((sum, row) => sum + BigInt(row[field]), 0n).toString();
  return { items: lots, grades: [...grades.values()].sort((a, b) => a.code.localeCompare(b.code)),
    totals: { lotCount: items.length, producedLotCount: produced.length,
      batchCount: lots.reduce((sum, lot) => sum + lot.batches.length, 0),
      caneNetKg: sumDecimals(items.map(lot => lot.caneNetKg)),
      finalSugarKg: sumDecimals(produced.map(row => row.finalSugarKg)),
      productionValueRupiah: money('productionValueRupiah'), totalCostRupiah: money('totalCostRupiah'),
      productionMarginRupiah: money('productionMarginRupiah') } };
}

export function contributionRanking(items: ProductionReportLot[]) {
  const batches = items.flatMap(lot => lot.batches);
  const incompleteBatchIds = batches.filter(batch => {
    const consumed = sumDecimals((batch.consumedByOrigin ?? []).map(row => row.quantityMl));
    return compareDecimals(consumed, batch.quantityMl) !== 0;
  }).map(batch => batch.id);
  const volumes = new Map<string, OriginVolume>();
  if (!incompleteBatchIds.length) {
    for (const batch of batches) {
      for (const row of batch.consumedByOrigin ?? []) {
        const previous = volumes.get(row.originLotId);
        volumes.set(row.originLotId, { ...row, quantityMl: sumDecimals([previous?.quantityMl ?? '0', row.quantityMl]) });
      }
    }
  }
  const ranked = [...volumes.values()].sort((a, b) =>
    compareDecimals(b.quantityMl, a.quantityMl) || a.originLotId.localeCompare(b.originLotId));
  const leading = ranked.filter(row => compareDecimals(row.quantityMl, ranked[0].quantityMl) === 0);
  return {
    status: incompleteBatchIds.length ? 'incomplete' : ranked.length ? 'complete' : 'no_data',
    unit: 'mL',
    leadingCount: leading.length,
    leaders: leading.slice(0, 10),
    incompleteBatchIds,
  };
}
