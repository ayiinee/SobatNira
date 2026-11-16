import { BadRequestException } from '@nestjs/common';

// Quantities remain decimal strings through JSON and PostgreSQL numeric.
export function decimal(input: unknown, field: string, allowZero = false): string {
  if (typeof input !== 'string' || input.length > 64 || !/^(0|[1-9]\d*)(\.\d+)?$/.test(input)) {
    throw new BadRequestException(`${field} harus berupa string desimal tanpa eksponen/pemisah ribuan (maksimum 64 karakter).`);
  }
  const result = input.includes('.') ? input.replace(/0+$/, '').replace(/\.$/, '') : input;
  if (!allowZero && result === '0') throw new BadRequestException(`${field} harus lebih besar dari nol.`);
  return result;
}

function scaled(values: string[]): { integers: bigint[]; places: number } {
  const places = Math.max(0, ...values.map((value) => value.split('.')[1]?.length ?? 0));
  return { places, integers: values.map((value) => {
    const [whole, fraction = ''] = value.split('.');
    return BigInt(whole + fraction.padEnd(places, '0'));
  }) };
}

// Only validated, nonnegative decimal strings enter these arithmetic helpers.
export function compareDecimals(left: string, right: string): number {
  const { integers: [a, b] } = scaled([left, right]);
  return a < b ? -1 : a > b ? 1 : 0;
}

export function sumDecimals(values: string[]): string {
  const { integers, places } = scaled(values);
  const digits = integers.reduce((total, value) => total + value, 0n).toString().padStart(places + 1, '0');
  return places ? (digits.slice(0, -places) + '.' + digits.slice(-places)).replace(/0+$/, '').replace(/\.$/, '') : digits;
}
