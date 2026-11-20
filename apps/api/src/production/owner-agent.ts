import { BadRequestException, Body, Controller, ForbiddenException, Header, HttpCode, Injectable, Post,
  ServiceUnavailableException, UseGuards } from '@nestjs/common';
import { createHash, createHmac, randomBytes } from 'node:crypto';
import { AccessRepository } from '../auth/access.repository';
import { CurrentFactory, FactoryRoles, Public } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService } from '../database/database.service';
import { AdapterGuard } from '../documents/ocr-documents.module';
import { Capabilities } from './capabilities';
import { object, text, uuid } from './production.dto';
import { ReportExports } from './report-exports';
import { ReportDelivery } from './report-delivery';

function phone(value: unknown) {
  if (typeof value !== 'string' || !/^\+[1-9][0-9]{7,14}$/.test(value)) {
    throw new BadRequestException('Gunakan nomor WhatsApp dalam format internasional.');
  }
  return value;
}

@Injectable()
export class OwnerAgentSessions {
  constructor(private readonly db: DatabaseService, private readonly memberships: AccessRepository) {}

  private digest(kind: 'phone' | 'code', value: string) {
    const key = process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN;
    if (process.env.OWNER_AGENT_ENABLED !== 'true' || !key || key.length < 32) {
      throw new ServiceUnavailableException('Asisten owner WhatsApp belum diaktifkan.');
    }
    return createHmac('sha256', key).update(kind).update('\0').update(value).digest('hex');
  }

  async issue(access: FactoryAccess, input: unknown) {
    const body = object(input, ['phone']);
    const target = this.digest('phone', phone(body.phone));
    const code = randomBytes(16).toString('base64url');
    const { rows: [session] } = await this.db.query(`INSERT INTO sobatnira.owner_agent_sessions
      (tenant_id,factory_id,user_id,phone_digest,code_digest,expires_at)
      VALUES ($1,$2,$3,$4,$5,clock_timestamp()+interval '10 minutes') RETURNING expires_at`,
    [access.tenantId, access.factoryId, access.userId, target, this.digest('code', code)]);
    return { code, expires_at: session.expires_at };
  }

  async link(sender: string, value: unknown) {
    if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{22}$/.test(value)) {
      throw new BadRequestException('Kode sambungan tidak valid.');
    }
    const target = this.digest('phone', sender);
    const { rows } = await this.db.query(`UPDATE sobatnira.owner_agent_sessions s
      SET bound_at=clock_timestamp(), expires_at=clock_timestamp()+interval '1 hour'
      FROM sobatnira.factory_memberships f, sobatnira.tenant_memberships t,
        sobatnira.factories factory, sobatnira.tenants tenant
      WHERE s.phone_digest=$1 AND s.code_digest=$2 AND s.bound_at IS NULL AND s.revoked_at IS NULL
        AND s.expires_at>clock_timestamp() AND (f.tenant_id,f.factory_id,f.user_id)=(s.tenant_id,s.factory_id,s.user_id)
        AND f.role='owner' AND f.is_active AND (t.tenant_id,t.user_id)=(s.tenant_id,s.user_id)
        AND t.is_active AND (factory.tenant_id,factory.id)=(s.tenant_id,s.factory_id) AND factory.is_active
        AND tenant.id=s.tenant_id AND tenant.is_active RETURNING s.id`, [target, this.digest('code', value)]);
    if (!rows.length) throw new ForbiddenException('Kode tidak tersedia untuk nomor ini.');
    return { linked: true };
  }

  async access(sender: string) {
    const { rows: [session] } = await this.db.query<{ user_id: string; tenant_id: string;
      factory_id: string; usable: boolean }>(`SELECT user_id,tenant_id,factory_id,
      revoked_at IS NULL AND expires_at>clock_timestamp() AS usable FROM sobatnira.owner_agent_sessions
      WHERE phone_digest=$1 AND bound_at IS NOT NULL ORDER BY bound_at DESC,id DESC LIMIT 1`,
    [this.digest('phone', sender)]);
    const access = session?.usable && await this.memberships.findFactoryAccess(session.user_id, session.tenant_id, session.factory_id);
    if (!access || access.role !== 'owner') throw new ForbiddenException('Sambungkan sesi owner dari pabrik terlebih dahulu.');
    return access;
  }

  async disconnect(sender: string) {
    await this.db.query(`UPDATE sobatnira.owner_agent_sessions SET revoked_at=clock_timestamp()
      WHERE phone_digest=$1 AND revoked_at IS NULL`, [this.digest('phone', sender)]);
    return { disconnected: true };
  }
}

@Controller('tenants/:tenantId/factories/:factoryId/owner-agent')
@FactoryRoles('owner')
export class OwnerAgentSessionController {
  constructor(private readonly sessions: OwnerAgentSessions) {}

  @Post('sessions')
  @Header('Cache-Control', 'private, no-store')
  issue(@CurrentFactory() access: FactoryAccess, @Body() body: unknown) {
    return this.sessions.issue(access, body);
  }
}

@Public()
@UseGuards(AdapterGuard)
@Controller('internal/v1/whatsapp/owner-agent')
export class OwnerAgentController {
  constructor(private readonly sessions: OwnerAgentSessions, private readonly capabilities: Capabilities,
    private readonly reports: ReportExports, private readonly delivery: ReportDelivery) {}

  @Post('notices/claim')
  @HttpCode(200)
  claim() { return this.delivery.claim(sender => this.sessions.access(sender)); }

  @Post('notices/complete')
  @HttpCode(200)
  complete(@Body() input: unknown) {
    const body = object(input, ['reportId', 'claim', 'receipt']);
    return this.delivery.complete(uuid(body.reportId), uuid(body.claim),
      body.receipt === null ? null : text(body.receipt, 'receipt', 255));
  }

  @Post()
  @HttpCode(200)
  async run(@Body() input: unknown) {
    const body = object(input, ['phone', 'chat', 'action', 'code', 'query', 'messageId', 'reportId']);
    const sender = phone(body.phone);
    if (body.chat !== sender) throw new ForbiddenException('Gunakan percakapan langsung yang terverifikasi.');
    if (body.action === 'connect') return this.sessions.link(sender, body.code);
    if (body.action === 'disconnect') return this.sessions.disconnect(sender);
    const access = await this.sessions.access(sender);
    if (body.action === 'check') return { allowed: true };
    if (body.action === 'query') return this.capabilities.query(access, body.query);
    if (body.action === 'report-request') {
      const message = text(body.messageId, 'messageId', 255);
      const hash = createHash('sha256').update(JSON.stringify(['whatsapp-report', sender, message])).digest('hex');
      const key = `${hash.slice(0, 8)}-${hash.slice(8, 12)}-4${hash.slice(13, 16)}-8${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
      return this.reports.request(access, key, body.query, { phone: sender, messageId: message });
    }
    if (body.action === 'report-status') return this.reports.status(access, uuid(body.reportId, 'reportId'));
    throw new BadRequestException('Aksi asisten tidak didukung.');
  }
}
