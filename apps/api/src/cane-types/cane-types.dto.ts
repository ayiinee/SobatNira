import { BadRequestException } from '@nestjs/common';
import { caneTypeCode, object, text } from '../production/production.dto';

export function parseCaneTypeCreate(input: unknown) {
  const row = object(input, ['code', 'name']);
  return { code: caneTypeCode(row.code, 'code').toUpperCase(), name: text(row.name, 'name', 200) };
}

export function parseCaneTypeUpdate(input: unknown) {
  const row = object(input, ['name', 'isActive']);
  if (!Object.keys(row).length) throw new BadRequestException('Minimal satu field diperlukan.');
  if ('isActive' in row && typeof row.isActive !== 'boolean') {
    throw new BadRequestException('isActive harus berupa boolean.');
  }
  return { name: 'name' in row ? text(row.name, 'name', 200) : undefined,
    isActive: typeof row.isActive === 'boolean' ? row.isActive : undefined };
}
