import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from 'node:crypto';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService } from '../database/database.service';

export type ReportTarget = { phone: string; messageId: string };

function key() {
  const secret = process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN;
  if (!secret || secret.length < 32) throw new ServiceUnavailableException('Pengiriman laporan belum tersedia.');
  return createHash('sha256').update('sobatnira/report-notice/v1\0').update(secret).digest();
}

export function sealReportTarget(target: ReportTarget) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key(), nonce);
  const bytes = Buffer.concat([cipher.update(JSON.stringify(target)), cipher.final()]);
  return Buffer.concat([nonce, cipher.getAuthTag(), bytes]).toString('base64url');
}

function openTarget(value: string): ReportTarget {
  const bytes = Buffer.from(value, 'base64url');
  const cipher = createDecipheriv('aes-256-gcm', key(), bytes.subarray(0, 12));
  cipher.setAuthTag(bytes.subarray(12, 28));
  return JSON.parse(Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString());
}

@Injectable()
export class ReportDelivery {
  constructor(private readonly db: DatabaseService) {}

  private enabled() {
    if (process.env.REPORT_EXPORT_ENABLED !== 'true' || process.env.OWNER_AGENT_ENABLED !== 'true') {
      throw new ServiceUnavailableException('Pengiriman laporan belum tersedia.');
    }
  }

  async claim(accessFor: (phone: string) => Promise<FactoryAccess>) {
    this.enabled();
    const claim = randomUUID();
    await this.db.query(`UPDATE sobatnira.report_export_notices SET status='FAILED',claim_token=NULL,lease_until=NULL
      WHERE status='PROCESSING' AND lease_until<=clock_timestamp() AND attempts=3`, []);
    const { rows: [row] } = await this.db.query<{ report_id: string; delivery_target: string; tenant_id: string;
      factory_id: string; requested_by: string }>(`WITH next AS (
      SELECT n.report_id FROM sobatnira.report_export_notices n
      JOIN sobatnira.report_exports r ON r.id=n.report_id AND r.status='READY'
      WHERE n.attempts<3 AND ((n.status='QUEUED' AND n.available_at<=clock_timestamp()) OR
        (n.status='PROCESSING' AND n.lease_until<=clock_timestamp()))
      ORDER BY n.available_at,n.report_id FOR UPDATE OF n SKIP LOCKED LIMIT 1
    ), claimed AS (
      UPDATE sobatnira.report_export_notices n SET status='PROCESSING',attempts=attempts+1,
        claim_token=$1,lease_until=clock_timestamp()+interval '45 seconds'
      FROM next WHERE n.report_id=next.report_id RETURNING n.report_id
    ) SELECT r.id AS report_id,r.delivery_target,r.tenant_id,r.factory_id,r.requested_by
      FROM sobatnira.report_exports r JOIN claimed c ON c.report_id=r.id`, [claim]);
    if (!row) return { notice: null };
    let target: ReportTarget | undefined;
    let access: FactoryAccess | undefined;
    try {
      target = openTarget(row.delivery_target);
      access = await accessFor(target.phone);
    } catch (error) {
      const status = (error as { getStatus?: () => number })?.getStatus?.();
      await this.complete(row.report_id, claim, null, !target || status === 403);
      return { notice: null };
    }
    if (access.tenantId !== row.tenant_id || access.factoryId !== row.factory_id ||
      access.userId !== row.requested_by || access.role !== 'owner') {
      await this.complete(row.report_id, claim, null, true);
      return { notice: null };
    }
    return { notice: { reportId: row.report_id, claim, to: target.phone, replyToId: target.messageId,
      text: `Laporan ${row.report_id} siap dalam PDF dan XLSX. Unduh dengan sesi owner di SobatNira.` } };
  }

  async complete(id: string, claim: string, receipt: string | null, terminal = false) {
    this.enabled();
    const { rowCount } = await this.db.query(`UPDATE sobatnira.report_export_notices SET
      status=CASE WHEN $3::text IS NOT NULL THEN 'SENT' WHEN $4::boolean OR attempts=3 THEN 'FAILED' ELSE 'QUEUED' END,
      provider_receipt=$3,claim_token=NULL,lease_until=NULL,available_at=clock_timestamp()+make_interval(secs => attempts*15)
      WHERE report_id=$1 AND status='PROCESSING' AND claim_token=$2`, [id, claim, receipt, terminal]);
    return { recorded: rowCount === 1 };
  }
}
