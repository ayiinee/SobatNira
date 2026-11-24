import { BadRequestException } from '@nestjs/common';
import { decimal } from './decimal';
import { caneTypeCode, object } from './production.dto';

const SCALE = 1_000_000n;
function quantity(value: unknown, name: string): bigint {
  const parsed = decimal(value, name);
  const [whole, fraction = ''] = parsed.split('.');
  if (fraction.length > 6) throw new BadRequestException(`${name} maksimal 6 angka desimal kg.`);
  return BigInt(whole) * SCALE + BigInt(fraction.padEnd(6, '0'));
}
function money(value: unknown, name: string): bigint {
  if (typeof value !== 'string' || !/^(0|[1-9]\d{0,29})$/.test(value)) {
    throw new BadRequestException(`${name} harus string rupiah bulat nonnegatif, maksimal 30 digit.`);
  }
  return BigInt(value);
}
function roundHalfUp(numerator: bigint, denominator: bigint): bigint {
  return (numerator + denominator / 2n) / denominator;
}
function kg(value: bigint): string {
  const raw = `${value / SCALE}.${(value % SCALE).toString().padStart(6, '0')}`;
  return raw.replace(/0+$/, '').replace(/\.$/, '');
}
function percentage(sugar: bigint, cane: bigint): string {
  const hundredths = roundHalfUp(sugar * 10_000n, cane);
  return `${hundredths / 100n}.${(hundredths % 100n).toString().padStart(2, '0')}`;
}

/** Explicit input simulation, never posts stock, approvals or accounting entries. */
export function calculateProductionPreview(input: unknown, internal = false) {
  const body = object(input, ['caneNetKg', 'caneCostRupiah', 'operationalCostRupiah', 'ingredientCostRupiah', 'otherCostRupiah', 'rounding', 'grades']);
  if (body.rounding !== 'HALF_UP') throw new BadRequestException('Pilih rounding HALF_UP secara eksplisit untuk simulasi ini.');
  const cane = quantity(body.caneNetKg, 'caneNetKg');
  const caneCost = money(body.caneCostRupiah, 'caneCostRupiah');
  const operating = money(body.operationalCostRupiah, 'operationalCostRupiah');
  const ingredients = money(body.ingredientCostRupiah, 'ingredientCostRupiah');
  const other = money(body.otherCostRupiah, 'otherCostRupiah');
  if (!Array.isArray(body.grades) || (!internal && body.grades.length < 1) || (!internal && body.grades.length > 100)) {
    throw new BadRequestException('grades harus memuat 1–100 hasil grade.');
  }
  const seen = new Set<string>();
  let finalSugar = 0n;
  let exactRevenue = 0n;
  const grades = body.grades.map((value, index) => {
    const row = object(value, ['code', 'weightKg', 'pricePerKgRupiah']);
    const code = caneTypeCode(row.code, 'code').toUpperCase();
    if (seen.has(code)) throw new BadRequestException('Kode grade duplikat.');
    seen.add(code);
    const weight = quantity(row.weightKg, `grades[${index}].weightKg`);
    const price = money(row.pricePerKgRupiah, `grades[${index}].pricePerKgRupiah`);
    finalSugar += weight;
    exactRevenue += weight * price;
    return { code, weightKg: kg(weight), pricePerKgRupiah: price.toString(), exactValueRupiah: `${weight * price / SCALE}.${(weight * price % SCALE).toString().padStart(6, '0')}`.replace(/0+$/, '').replace(/\.$/, '') };
  });
  // Round the sum once. Summing rounded line items can change the result.
  const revenue = roundHalfUp(exactRevenue, SCALE);
  const cost = caneCost + operating + ingredients + other;
  return {
    mode: 'preview' as const, calculationVersion: 'production-preview-v1', rounding: 'HALF_UP',
    basis: 'final_grade_weight_over_cane_net_weight',
    caneNetKg: kg(cane), finalSugarKg: kg(finalSugar),
    rendemenPercent: percentage(finalSugar, cane),
    grades, productionValueRupiah: revenue.toString(),
    costs: { caneRupiah: caneCost.toString(), operationalRupiah: operating.toString(), ingredientRupiah: ingredients.toString(), otherRupiah: other.toString() },
    totalCostRupiah: cost.toString(), productionMarginRupiah: (revenue - cost).toString(),
    persisted: false,
  };
}

export function calculateProductionRecapPreview(input: unknown) {
  const body = object(input, ['records']);
  if (!Array.isArray(body.records) || body.records.length < 1 || body.records.length > 100) {
    throw new BadRequestException('records harus memuat 1–100 kloter.');
  }
  const codes = new Set<string>();
  const records = body.records.map(value => {
    const row = object(value, ['lotCode', 'calculation']);
    const lotCode = caneTypeCode(row.lotCode, 'lotCode').toUpperCase();
    if (codes.has(lotCode)) throw new BadRequestException('Kloter duplikat akan menghitung biaya dua kali.');
    codes.add(lotCode);
    return { lotCode, ...calculateProductionPreview(row.calculation) };
  });
  const cane = records.reduce((sum, row) => sum + quantity(row.caneNetKg, 'caneNetKg'), 0n);
  const sugar = records.reduce((sum, row) => sum + quantity(row.finalSugarKg, 'finalSugarKg'), 0n);
  const revenue = records.reduce((sum, row) => sum + BigInt(row.productionValueRupiah), 0n);
  const cost = records.reduce((sum, row) => sum + BigInt(row.totalCostRupiah), 0n);
  return {
    mode: 'preview' as const, persisted: false, calculationVersion: 'production-preview-v1',
    revenueRoundingBasis: 'per_lot', lotCount: records.length, records,
    totals: { caneNetKg: kg(cane), finalSugarKg: kg(sugar), rendemenPercent: percentage(sugar, cane),
      productionValueRupiah: revenue.toString(), totalCostRupiah: cost.toString(), productionMarginRupiah: (revenue - cost).toString() },
  };
}
