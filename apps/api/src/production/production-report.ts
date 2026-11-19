import { sumDecimals } from './decimal';

type Grade = { code: string; weightKg: string; pricePerKgRupiah: string };
type Batch = { id: string; code: string; wokNumber: number; occurredAt: string; quantityMl: string; physicalWeightKg: string; grades: Grade[] };
type Calculation = { finalSugarKg: string; rendemenPercent: string; productionValueRupiah: string; totalCostRupiah: string; productionMarginRupiah: string; costs: Record<string, string> };
export type ProductionReportLot = {
  lotId: string; code: string; supplier: string; receivedAt: string;
  caneNetKg: string; caneType: string | null; juiceLiters: string | null;
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

export function productionReport(items: ProductionReportLot[]) {
  const grades = new Map<string, { code: string; weightKg: string; exactValueRupiah: string }>();
  const lots = items.map(lot => ({ ...lot, batches: lot.batches.map(batch => {
    const results = batch.grades.map(grade => ({ ...grade, exactValueRupiah: exactValue(grade) }));
    for (const grade of results) {
      const previous = grades.get(grade.code);
      grades.set(grade.code, { code: grade.code,
        weightKg: sumDecimals([previous?.weightKg ?? '0', grade.weightKg]),
        exactValueRupiah: sumDecimals([previous?.exactValueRupiah ?? '0', grade.exactValueRupiah]) });
    }
    return { ...batch, grades: results, finalSugarKg: sumDecimals(results.map(g => g.weightKg)),
      exactValueRupiah: sumDecimals(results.map(g => g.exactValueRupiah)) };
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
