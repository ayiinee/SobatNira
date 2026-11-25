import { BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header,
  Headers, HttpCode, Injectable, Logger, OnModuleDestroy, OnModuleInit, Param, Post, ServiceUnavailableException,
  StreamableFile } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { AccessRepository } from '../auth/access.repository';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { DatabaseService } from '../database/database.service';
import { assertR2Privacy, MediaStorage } from '../documents/media';
import { reportSelection } from './production-report';
import { loadConfiguration } from '../config/backend.config';
import { Batches } from './batches';
import { found, object, scopeValues, timestamp, uuid } from './production.dto';
import { formats, renderReport, reportMime, ReportFormat, ReportSnapshot, UnsupportedReportCharacter, verifyReport } from './report-formats';
import { ReportTarget, sealReportTarget } from './report-delivery';

type Artifact = { key: string; sha256: string };
type Job = { id: string; tenant_id: string; factory_id: string; requested_by: string; input_hash: string;
  snapshot: ReportSnapshot; status: 'QUEUED' | 'PROCESSING' | 'READY' | 'FAILED'; created_at: Date;
  finished_at: Date | null; claim_token: string; attempts: number; artifacts: Record<ReportFormat, Artifact> | null };
const digest = (value: Buffer | string) => createHash('sha256').update(value).digest('hex');
const lookup = (format: unknown): ReportFormat => {
  if (format !== 'pdf' && format !== 'xlsx') throw new BadRequestException('Format laporan tidak dikenal.');
  return format;
};

@Injectable()
export class ReportExports implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ReportExports.name);
  private timer?: NodeJS.Timeout;
  private running?: Promise<unknown>;
  private privateBucket?: Promise<void>;

  constructor(private readonly db: DatabaseService, private readonly batches: Batches,
    private readonly memberships: AccessRepository, private readonly storage: MediaStorage) {}

  onModuleInit() {
    if (process.env.REPORT_EXPORT_ENABLED === 'true') {
      loadConfiguration({ envFile: false });
      this.timer = setInterval(() => {
        this.running ??= this.processOne().catch(() => this.logger.warn('Antrean ekspor belum tersedia.'))
          .finally(() => { this.running = undefined; });
      }, 2_000);
      this.timer.unref();
    }
  }

  async onModuleDestroy() {
    clearInterval(this.timer);
    await this.running;
  }

  private authorize(access: FactoryAccess) {
    if (!['admin', 'owner'].includes(access.role)) throw new ForbiddenException('Akses admin atau owner diperlukan.');
    if (process.env.REPORT_EXPORT_ENABLED !== 'true') throw new ServiceUnavailableException('Ekspor laporan belum aktif.');
  }

  private publicStatus(job: Job) {
    return { id: job.id, status: job.status, createdAt: job.created_at, finishedAt: job.finished_at,
      from: job.snapshot.from, before: job.snapshot.before, synthetic: job.snapshot.synthetic,
      ...(job.status === 'READY' ? { formats } : {}) };
  }

  private async forActor(access: FactoryAccess, field: 'id' | 'idempotency_key', value: string) {
    const { rows: [job] } = await this.db.query<Job>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT r.* FROM sobatnira.report_exports r JOIN authorized_scope a
      ON (r.tenant_id,r.factory_id,r.requested_by)=(a."tenantId",a."factoryId",a."userId")
      WHERE a.role IN ('admin','owner') AND r.${field}=$4`, [...scopeValues(access), value]);
    return job;
  }

  async request(access: FactoryAccess, key: unknown, body: unknown, target?: ReportTarget) {
    this.authorize(access);
    const idempotencyKey = uuid(key, 'Idempotency-Key');
    const input = object(body, ['from', 'before', 'synthetic', 'supplierId', 'lotId', 'batchId', 'grade']);
    const from = timestamp(input.from, 'from'), before = timestamp(input.before, 'before');
    if (Date.parse(before) - Date.parse(from) > 366 * 86_400_000 || from >= before ||
      (input.synthetic !== undefined && typeof input.synthetic !== 'boolean')) {
      throw new BadRequestException('Periode atau kategori laporan tidak valid.');
    }
    const payload = { from, before, synthetic: String(input.synthetic === true), ...reportSelection(input) };
    const hash = digest(JSON.stringify(payload));
    const previous = await this.forActor(access, 'idempotency_key', idempotencyKey);
    if (previous) {
      if (previous.input_hash !== hash) throw new ConflictException('Kunci sudah dipakai untuk permintaan lain.');
      return this.publicStatus(previous);
    }
    const snapshot = JSON.stringify(await this.batches.productionReport(access, payload, 500));
    if (Buffer.byteLength(snapshot) > 5 * 1024 * 1024) throw new BadRequestException('Persempit periode laporan.');
    const { rows: [inserted] } = await this.db.query<Job>(`WITH ${FACTORY_SCOPE_CTE}
      INSERT INTO sobatnira.report_exports(tenant_id,factory_id,requested_by,idempotency_key,input_hash,snapshot,delivery_target)
      SELECT "tenantId","factoryId","userId",$4,$5,$6,$7 FROM authorized_scope WHERE role IN ('admin','owner')
      ON CONFLICT DO NOTHING RETURNING *`,
    [...scopeValues(access), idempotencyKey, hash, snapshot, target ? sealReportTarget(target) : null]);
    const job = inserted ?? await this.forActor(access, 'idempotency_key', idempotencyKey);
    if (!job) throw new ForbiddenException('Akses admin atau owner diperlukan.');
    if (job.input_hash !== hash) throw new ConflictException('Kunci sudah dipakai untuk permintaan lain.');
    return this.publicStatus(job);
  }

  async status(access: FactoryAccess, id: string) {
    this.authorize(access);
    return this.publicStatus(found(await this.forActor(access, 'id', id)));
  }

  async snapshot(access: FactoryAccess, id: string) {
    this.authorize(access);
    const job = found(await this.forActor(access, 'id', id));
    return { ...this.publicStatus(job), snapshot: job.snapshot };
  }

  async download(access: FactoryAccess, id: string, format: ReportFormat) {
    this.authorize(access);
    const job = found(await this.forActor(access, 'id', id));
    const artifact = job.artifacts?.[format];
    if (job.status !== 'READY' || !artifact) throw new ConflictException('File laporan belum siap.');
    try {
      const data = await this.storage.read(artifact.key, 'reports');
      if (digest(data) !== artifact.sha256) throw new Error('Checksum berbeda.');
      return data;
    } catch { throw new ServiceUnavailableException('File laporan belum dapat diverifikasi.'); }
  }

  async processOne() {
    const token = randomUUID();
    await this.db.query(`UPDATE sobatnira.report_exports SET status='FAILED',finished_at=clock_timestamp(),
      claim_token=NULL,lease_until=NULL WHERE status='PROCESSING' AND attempts=3 AND lease_until<=clock_timestamp()`, []);
    const { rows: [job] } = await this.db.query<Job>(`WITH next AS (
      SELECT id FROM sobatnira.report_exports WHERE attempts<3 AND
        ((status='QUEUED' AND available_at<=clock_timestamp()) OR
         (status='PROCESSING' AND lease_until<=clock_timestamp()))
      ORDER BY available_at,id FOR UPDATE SKIP LOCKED LIMIT 1)
      UPDATE sobatnira.report_exports r SET status='PROCESSING',attempts=attempts+1,
        claim_token=$1,lease_until=clock_timestamp()+interval '2 minutes' FROM next
      WHERE r.id=next.id RETURNING r.*`, [token]);
    if (!job) return false;
    try {
      const current = await this.memberships.findFactoryAccess(job.requested_by, job.tenant_id, job.factory_id);
      if (!current || !['admin', 'owner'].includes(current.role)) {
        await this.finish(job, null, true);
        return true;
      }
      if (process.env.NODE_ENV === 'production' || process.env.SOBATNIRA_MODE === 'connected') {
        this.privateBucket ??= assertR2Privacy().catch(error => { this.privateBucket = undefined; throw error; });
        await this.privateBucket;
      }
      const artifacts = {} as Record<ReportFormat, Artifact>;
      for (const format of formats) {
        const key = digest(`${job.id}:${format}`);
        const bytes = await renderReport(format, job.snapshot, new Date(job.created_at));
        await this.storage.put(key, reportMime[format], bytes, 'reports');
        const stored = await this.storage.read(key, 'reports');
        await verifyReport(format, stored, bytes, job.snapshot);
        artifacts[format] = { key, sha256: digest(stored) };
      }
      await this.finish(job, artifacts);
    } catch (error) {
      const unsupported = error instanceof UnsupportedReportCharacter;
      this.logger.warn({ event: 'report_export_attempt_failed', reportId: job.id, attempt: job.attempts,
        reason: unsupported ? 'unsupported_pdf_character' : 'export_failed' });
      await this.finish(job, null, unsupported);
    }
    return true;
  }

  private async finish(job: Job, artifacts: Job['artifacts'], terminal = false) {
    const status = artifacts ? 'READY' : terminal || job.attempts >= 3 ? 'FAILED' : 'QUEUED';
    await this.db.query(`WITH finished AS (UPDATE sobatnira.report_exports SET status=$3,artifacts=$4,
      available_at=clock_timestamp()+make_interval(secs => attempts*15),
      finished_at=CASE WHEN $3 IN ('READY','FAILED') THEN clock_timestamp() END,
      claim_token=NULL,lease_until=NULL WHERE id=$1 AND claim_token=$2 AND status='PROCESSING'
      RETURNING id,status,delivery_target)
      INSERT INTO sobatnira.report_export_notices(report_id)
      SELECT id FROM finished WHERE status='READY' AND delivery_target IS NOT NULL ON CONFLICT DO NOTHING`,
    [job.id, job.claim_token, status, artifacts && JSON.stringify(artifacts)]);
  }
}

@Controller('tenants/:tenantId/factories/:factoryId/report-exports')
@FactoryRoles('admin', 'owner')
export class ReportExportsController {
  constructor(private readonly reports: ReportExports) {}

  @Post()
  @HttpCode(202)
  @Header('Cache-Control', 'private, no-store')
  request(@CurrentFactory() a: FactoryAccess, @Headers('idempotency-key') key: string, @Body() body: unknown) {
    return this.reports.request(a, key, body);
  }

  @Get(':id')
  @Header('Cache-Control', 'private, no-store')
  status(@CurrentFactory() a: FactoryAccess, @Param('id') id: string) {
    return this.reports.status(a, uuid(id));
  }

  @Get(':id/snapshot')
  @Header('Cache-Control', 'private, no-store')
  snapshot(@CurrentFactory() a: FactoryAccess, @Param('id') id: string) {
    return this.reports.snapshot(a, uuid(id));
  }

  @Get(':id/files/:format')
  @Header('Cache-Control', 'private, no-store')
  async download(@CurrentFactory() a: FactoryAccess, @Param('id') raw: string, @Param('format') choice: string) {
    const id = uuid(raw), format = lookup(choice);
    return new StreamableFile(await this.reports.download(a, id, format), {
      type: reportMime[format], disposition: `attachment; filename="sobatnira-${id}.${format}"`,
    });
  }
}
