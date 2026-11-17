import { ForbiddenException } from '@nestjs/common';
import { ACTIVE_ACCESS_SQL } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseSession } from '../database/database.service';

export async function requireProductionAccess(db: DatabaseSession, userId: string, factoryId: string, lock = true) {
  const { rows: [access] } = await db.query<FactoryAccess>(`${ACTIVE_ACCESS_SQL} AND fm.factory_id=$2
    AND fm.role IN ('admin','owner') ${lock ? 'FOR SHARE OF fm,tm,f,t' : ''}`, [userId, factoryId]);
  if (!access) throw new ForbiddenException('Akses produksi pada pabrik ini diperlukan.');
  return access;
}
