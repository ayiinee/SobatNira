import { BadRequestException } from '@nestjs/common';

export function units(value: string, places = 6): bigint {
  const [whole, fraction = ''] = value.split('.');
  if (fraction.length > places) throw new BadRequestException('Presisi alokasi tidak valid.');
  return BigInt(whole + fraction.padEnd(places, '0'));
}

export function kilograms(value: bigint): string {
  return `${value / 1000000n}.${(value % 1000000n).toString().padStart(6, '0')}`.replace(/0+$/, '').replace(/\.$/, '');
}

// Largest remainder, with stable lot IDs breaking ties. No float arithmetic.
export function allocate(total: bigint, shares: { id: string; quantity: string }[]): Map<string, bigint> {
  const places = Math.max(0, ...shares.map(s => s.quantity.split('.')[1]?.length ?? 0));
  const weights = shares.map(s => ({ id: s.id, weight: units(s.quantity, places) }));
  const denominator = weights.reduce((n, s) => n + s.weight, 0n);
  if (denominator <= 0n || total < 0n) throw new BadRequestException('Volume alokasi tidak valid.');
  const rows = weights.map(s => ({ id: s.id, value: total * s.weight / denominator, remainder: total * s.weight % denominator }));
  rows.sort((a, b) => a.remainder === b.remainder ? a.id.localeCompare(b.id) : a.remainder > b.remainder ? -1 : 1);
  let left = total - rows.reduce((n, s) => n + s.value, 0n);
  for (const row of rows) if (left > 0n) { row.value++; left--; }
  return new Map(rows.map(s => [s.id, s.value]));
}
