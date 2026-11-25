import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { object, text } from '../production/production.dto';
import { FactoryAccess, FactoryRole } from './auth.types';
import { ACTIVE_ACCESS_SQL as ACTIVE_ACCESS } from './access.sql';

// Every access read joins current active tenant, factory and both memberships.
// There is no cache that can retain a revoked role until a JWT expires.
@Injectable()
export class AccessRepository {
  constructor(private readonly database: DatabaseService) {}

  async listAccess(userId: string): Promise<FactoryAccess[]> {
    const result = await this.database.query<FactoryAccess>(
      `${ACTIVE_ACCESS} ORDER BY t.name, f.name, f.id`, [userId],
    );
    return result.rows;
  }

  async findFactoryAccess(userId: string, tenantId: string, factoryId: string): Promise<FactoryAccess | undefined> {
    const result = await this.database.query<FactoryAccess>(
      `${ACTIVE_ACCESS} AND fm.tenant_id = $2::uuid AND fm.factory_id = $3::uuid`,
      [userId, tenantId, factoryId],
    );
    return result.rows[0];
  }

  async listFactoryMembers(access: FactoryAccess) {
    const result = await this.database.query<{ userId: string; email: string | null; role: FactoryRole; isActive: boolean }>(`
      WITH authorized_factory AS (
        ${ACTIVE_ACCESS} AND fm.tenant_id = $2::uuid AND fm.factory_id = $3::uuid AND fm.role = 'owner'
      )
      SELECT fm.user_id AS "userId", u.email, fm.role, (fm.is_active AND tm.is_active) AS "isActive"
      FROM sobatnira.factory_memberships fm
      JOIN sobatnira.tenant_memberships tm ON tm.tenant_id = fm.tenant_id AND tm.user_id = fm.user_id
      JOIN authorized_factory allowed ON allowed."tenantId" = fm.tenant_id AND allowed."factoryId" = fm.factory_id
      LEFT JOIN auth.users u ON u.id=fm.user_id
      ORDER BY fm.user_id
    `, [access.userId, access.tenantId, access.factoryId]);
    return result.rows;
  }

  async factoryProfile(access: FactoryAccess) {
    const { rows: [row] } = await this.database.query(`
      WITH allowed AS (${ACTIVE_ACCESS} AND fm.tenant_id=$2 AND fm.factory_id=$3)
      SELECT f.id, f.tenant_id AS "tenantId", f.name, a.role, f.display_code AS "displayCode",
        f.branch_name AS "branchName", f.support_phone_e164 AS "supportPhone", f.profile_version AS version
      FROM sobatnira.factories f JOIN allowed a ON (f.tenant_id,f.id)=(a."tenantId",a."factoryId")
    `, [access.userId, access.tenantId, access.factoryId]);
    if (!row) throw new ForbiddenException('Akses pabrik sudah berubah.');
    return row;
  }

  editFactoryProfile(access: FactoryAccess, input: unknown) {
    const data = object(input, ['version', 'displayCode', 'branchName', 'supportPhone']);
    if (!Number.isSafeInteger(data.version) || Number(data.version) < 1)
      throw new BadRequestException('Versi profil tidak valid.');
    const [code, branch, phone] = [
      data.displayCode === null ? null : text(data.displayCode, 'Kode pabrik', 60),
      data.branchName === null ? null : text(data.branchName, 'Cabang', 120),
      data.supportPhone === null ? null : text(data.supportPhone, 'WhatsApp bantuan', 16),
    ];
    if (phone && !/^\+[1-9][0-9]{7,14}$/.test(phone))
      throw new BadRequestException('WhatsApp bantuan harus memakai format internasional.');
    return this.database.transaction(async tx => {
      const ids = await this.lockOwner(tx, access);
      const { rows: [row] } = await tx.query(`
        UPDATE sobatnira.factories SET display_code=$3,branch_name=$4,support_phone_e164=$5,profile_version=profile_version+1
        WHERE tenant_id=$1 AND id=$2 AND profile_version=$6
        RETURNING display_code AS "displayCode",branch_name AS "branchName",support_phone_e164 AS "supportPhone",profile_version AS version
      `, [access.tenantId, access.factoryId, code, branch, phone, data.version]);
      if (!row) throw new ConflictException('Profil sudah berubah. Muat ulang.');
      await this.recordChange(tx, ids, 'profile_updated', null);
      return row;
    });
  }

  async authUserIdForEmail(email: string) {
    const { rows } = await this.database.query<{ id: string }>(
      'SELECT id FROM auth.users WHERE lower(email)=$1 LIMIT 2', [email]);
    if (rows.length > 1) throw new ConflictException('Akun ambigu. Hubungi pengelola akses.');
    return rows[0]?.id;
  }

  async addFactoryAdmin(access: FactoryAccess, userId: string) {
    return this.database.transaction(async tx => {
      const ids = await this.lockOwner(tx, access);
      const memberKey = [access.tenantId, access.factoryId, userId];
      const existing = await tx.query<{ role: FactoryRole; is_active: boolean }>(`
        SELECT role,is_active FROM sobatnira.factory_memberships
        WHERE tenant_id=$1 AND factory_id=$2 AND user_id=$3 FOR UPDATE`, memberKey);
      const old = existing.rows[0];
      if (old?.role === 'owner') throw new ConflictException('Akses owner dikelola melalui proses tim.');
      if (old && !old.is_active) throw new ConflictException('Aktifkan kembali admin dari daftar anggota.');
      await tx.query(`
        INSERT INTO sobatnira.tenant_memberships (tenant_id,user_id) VALUES ($1,$2)
        ON CONFLICT DO NOTHING`, [access.tenantId, userId]);
      await this.requireActiveTenantMember(tx, access.tenantId, userId);
      if (!old) {
        await tx.query(`INSERT INTO sobatnira.factory_memberships (tenant_id,factory_id,user_id,role)
          VALUES ($1,$2,$3,'admin')`, memberKey);
        await this.recordChange(tx, ids, 'admin_added', userId);
      }
      await this.setReviewMembership(tx, access.factoryId, userId, true);
      return { userId, role: 'admin', isActive: true };
    });
  }

  async setFactoryAdminActive(access: FactoryAccess, userId: string, active: boolean) {
    return this.database.transaction(async tx => {
      const ids = await this.lockOwner(tx, access);
      const memberKey = [access.tenantId, access.factoryId, userId];
      const { rows: [member] } = await tx.query<{ is_active: boolean }>(`
        SELECT is_active FROM sobatnira.factory_memberships
        WHERE tenant_id=$1 AND factory_id=$2 AND user_id=$3 AND role='admin' FOR UPDATE
      `, memberKey);
      if (!member) throw new NotFoundException('Admin tidak ditemukan pada pabrik ini.');
      if (active) await this.requireActiveTenantMember(tx, access.tenantId, userId);
      if (member.is_active !== active) {
        await tx.query(`UPDATE sobatnira.factory_memberships SET is_active=$4
          WHERE tenant_id=$1 AND factory_id=$2 AND user_id=$3 AND role='admin'`, [...memberKey, active]);
        await this.recordChange(tx, ids, active ? 'admin_activated' : 'admin_deactivated', userId);
      }
      await this.setReviewMembership(tx, access.factoryId, userId, active);
      return { userId, role: 'admin', isActive: active };
    });
  }

  private async lockOwner(tx: DatabaseSession, access: FactoryAccess) {
    const ids = [access.userId, access.tenantId, access.factoryId];
    const owner = await tx.query(`${ACTIVE_ACCESS} AND fm.tenant_id=$2 AND fm.factory_id=$3 AND fm.role='owner'
      FOR UPDATE OF f FOR SHARE OF fm,tm,t`, ids);
    if (!owner.rows.length) throw new ForbiddenException('Perubahan memerlukan owner aktif di pabrik ini.');
    return ids;
  }

  private async requireActiveTenantMember(tx: DatabaseSession, tenantId: string, userId: string) {
    const { rows } = await tx.query(`SELECT 1 FROM sobatnira.tenant_memberships
      WHERE tenant_id=$1 AND user_id=$2 AND is_active FOR SHARE`, [tenantId, userId]);
    if (!rows.length) throw new ConflictException('Akun tidak aktif pada tenant ini.');
  }

  private async setReviewMembership(tx: DatabaseSession, factoryId: string, userId: string, active: boolean) {
    const { rows: [table] } = await tx.query("SELECT to_regclass('review_memberships') AS name", []);
    if (!table.name) return;
    if (active) {
      const { rows } = await tx.query(`
        INSERT INTO review_memberships (factory_id,user_id,role,active) VALUES ($1,$2,'ADMIN',true)
        ON CONFLICT (factory_id,user_id) DO UPDATE SET active=true WHERE review_memberships.role='ADMIN'
        RETURNING user_id`, [factoryId, userId]);
      if (!rows.length) throw new ConflictException('Peran reviewer perlu diperiksa pengelola akses.');
    } else {
      await tx.query("UPDATE review_memberships SET active=false WHERE factory_id=$1 AND user_id=$2 AND role='ADMIN'", [factoryId, userId]);
    }
  }

  private async recordChange(tx: DatabaseSession, ids: string[], action: string, userId: string | null) {
    await tx.query(`INSERT INTO sobatnira.factory_admin_events
      (actor_id,tenant_id,factory_id,action,target_user_id) VALUES ($1,$2,$3,$4,$5)`, [...ids, action, userId]);
  }
}
