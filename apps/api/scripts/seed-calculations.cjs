// Deterministic calculation fixtures only; never connects to or modifies a database.
const { calculateProductionPreview, calculateProductionRecapPreview } = require('../dist/production/calculation');
const input = {
  caneNetKg: '1500', caneCostRupiah: '900000', operationalCostRupiah: '100000',
  ingredientCostRupiah: '20000', otherCostRupiah: '0', rounding: 'HALF_UP',
  grades: [
    { code: 'A', weightKg: '30', pricePerKgRupiah: '20000' },
    { code: 'B', weightKg: '30', pricePerKgRupiah: '18000' },
    { code: 'C', weightKg: '30', pricePerKgRupiah: '15000' },
  ],
};
const scenarios = [
  { id: 'synthetic-profit', input },
  { id: 'synthetic-loss', input: { ...input, otherCostRupiah: '700000' } },
  { id: 'synthetic-fractional-weight', input: { ...input, grades: [{ code: 'A', weightKg: '0.125', pricePerKgRupiah: '20000' }] } },
];
const monthlyRecords = Array.from({ length: 30 }, (_, index) => ({
  lotCode: `SYNTHETIC-202610-${String(index + 1).padStart(2, '0')}`,
  calculation: { ...input, caneNetKg: String(1500 + index * 10), caneCostRupiah: String((1500 + index * 10) * 600),
    grades: input.grades.map((grade, gradeIndex) => ({ ...grade, weightKg: String(30 + (index + gradeIndex) % 5) })) },
}));
process.stdout.write(JSON.stringify({ synthetic: true, databaseWritten: false,
  assumptions: { currency: 'IDR', canePricePerKgRupiah: '600', rounding: 'HALF_UP', note: 'Synthetic calculation fixture, not approved production policy' },
  scenarios: scenarios.map(s => ({ ...s, expected: calculateProductionPreview(s.input) })),
  monthly: calculateProductionRecapPreview({ records: monthlyRecords }),
}, null, 2) + '\n');
