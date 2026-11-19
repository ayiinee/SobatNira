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

// Membership revocation applies to OCR reads and edits as well as stock posting.
export const ACTIVE_REVIEW_ACCESS_SQL = `EXISTS (
 SELECT 1 FROM sobatnira.factory_memberships rfm
 JOIN sobatnira.tenant_memberships rtm ON rtm.tenant_id=rfm.tenant_id AND rtm.user_id=rfm.user_id
 JOIN sobatnira.factories rf ON rf.id=rfm.factory_id AND rf.tenant_id=rfm.tenant_id
 JOIN sobatnira.tenants rt ON rt.id=rf.tenant_id
 WHERE rfm.user_id=a.user_id AND rfm.factory_id=a.factory_id
 AND rfm.is_active AND rtm.is_active AND rf.is_active AND rt.is_active
 AND upper(rfm.role)=a.role
)`;
