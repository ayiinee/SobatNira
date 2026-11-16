import { BadRequestException, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { PoolClient } from 'pg';
import { requireUuid } from './contracts';
import { Database } from './database';

export async function enqueueNotice(db: PoolClient, revisionId: string, kind: 'OCR_RESULT' | 'ADMIN_RETURNED') {
  await db.query(`INSERT INTO whatsapp_notices (revision_id,kind) VALUES ($1,$2) ON CONFLICT DO NOTHING`, [revisionId, kind]);
}

@Injectable()
export class Notices {
  constructor(private readonly db: Database) {}

  async claim() {
    return this.db.transaction(async (db) => {
      await db.query(`UPDATE whatsapp_notices n SET status='FAILED',claim_token=NULL,lease_until=NULL
        WHERE n.status='SENDING' AND n.lease_until<=now() AND n.attempts>=5`);
      const { rows: [notice] } = await db.query(`WITH pick AS (
        SELECT n.id,d.id AS document_id,o.phone_e164,m.provider_message_id AS reply_to_id,
          d.current_revision_id=n.revision_id AND o.active AS eligible
        FROM whatsapp_notices n JOIN document_revisions r ON r.id=n.revision_id JOIN source_documents d ON d.id=r.document_id
        JOIN document_submissions s ON s.id=r.submission_id JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id
        JOIN operator_contacts o ON o.id=m.operator_id AND o.factory_id=d.factory_id
        WHERE (n.status='QUEUED' AND n.available_at<=now()) OR (n.status='SENDING' AND n.lease_until<=now())
        ORDER BY n.available_at,n.id LIMIT 1 FOR UPDATE OF n SKIP LOCKED
      ) UPDATE whatsapp_notices n SET status=CASE WHEN pick.eligible THEN 'SENDING' ELSE 'CANCELLED' END,
        attempts=n.attempts+1,claim_token=CASE WHEN pick.eligible THEN $1::uuid END,
        lease_until=CASE WHEN pick.eligible THEN now()+interval '45 seconds' END FROM pick WHERE n.id=pick.id
      RETURNING n.id,n.revision_id,n.claim_token,n.kind,n.attempts,pick.document_id,pick.phone_e164,pick.reply_to_id,pick.eligible`, [randomUUID()]);
      if (!notice?.eligible) return { notice: null };
      const { eligible, ...result } = notice;
      return { notice: result };
    });
  }

  async result(id: string, body: Record<string, unknown> | undefined) {
    const claim = requireUuid(body?.claim_token);
    const outcome = body?.outcome;
    const receipt = body?.provider_message_id;
    if (typeof outcome !== 'string' || !['SENT','RETRY','CANCELLED'].includes(outcome) ||
      (outcome === 'SENT' && (typeof receipt !== 'string' || !receipt || receipt.length > 255))) {
      throw new BadRequestException('Status pengiriman tidak valid');
    }
    const { rowCount } = await this.db.query(`UPDATE whatsapp_notices SET
      status=CASE WHEN $3='RETRY' THEN CASE WHEN attempts>=5 THEN 'FAILED' ELSE 'QUEUED' END ELSE $3 END,
      available_at=now()+power(2,attempts)*interval '1 second',claim_token=NULL,lease_until=NULL,provider_message_id=$4
      WHERE id=$1 AND claim_token=$2 AND status='SENDING'`, [id, claim, outcome, outcome === 'SENT' ? receipt : null]);
    return { acknowledged: rowCount === 1 };
  }
}
