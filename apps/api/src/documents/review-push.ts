import { BadRequestException, ForbiddenException, Injectable, Logger, OnModuleDestroy, OnModuleInit, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { GoogleAuth } from 'google-auth-library';
import { PoolClient } from 'pg';
import { AdaptivePoller } from './adaptive-poller';
import { requireUuid } from './contracts';
import { Database } from './database';
import { ACTIVE_REVIEW_ACCESS_SQL } from './production-access';

const scope = 'https://www.googleapis.com/auth/firebase.messaging';
type Delivery = { installation_id: string; user_id: string; task_id: string; claim_id: string; registration_id: string; attempts: number };
type Outcome = 'SENT' | 'RETRY' | 'FAILED' | 'UNREGISTERED';

function pushProject() {
  const project = process.env.ANDROID_REVIEW_PUSH_PROJECT_ID;
  return process.env.ANDROID_REVIEW_PUSH_ENABLED === 'true' && project && /^[a-z][a-z0-9-]{5,29}$/.test(project)
    ? project : undefined;
}

export async function enqueueReviewPush(db: PoolClient, task: string, factory: string) {
  if (!pushProject()) return;
  await db.query(`INSERT INTO review_push_deliveries (installation_id,user_id,task_id,registration_id)
    SELECT i.installation_id,n.user_id,n.task_id,i.registration_id
    FROM admin_review_notifications n JOIN review_push_installations i ON i.user_id=n.user_id AND i.factory_id=$2
    JOIN review_memberships a ON a.user_id=n.user_id AND a.factory_id=i.factory_id AND a.active AND a.role='ADMIN'
      AND ${ACTIVE_REVIEW_ACCESS_SQL}
    WHERE n.task_id=$1 AND i.refreshed_at > now()-interval '30 days' ON CONFLICT DO NOTHING`, [task, factory]);
}

function requireInstallation(input: unknown) {
  if (typeof input !== 'string' || !/^[\w-]{22}$/.test(input)) throw new BadRequestException('Instalasi Android tidak valid.');
  return input;
}

@Injectable()
export class ReviewPush implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ReviewPush.name);
  private readonly google = new GoogleAuth({ scopes: [scope] });
  private poller?: AdaptivePoller;

  constructor(private readonly db: Database) {}

  onModuleInit() {
    if (!pushProject() || process.env.DOCUMENT_WORKER_ENABLED !== 'true') return;
    this.poller = new AdaptivePoller(() => this.processOne(), { minMs: 2_000, maxMs: 10_000 },
      () => this.logger.warn('Antrean push Android belum dapat diproses.'));
    this.poller.start();
  }

  async onModuleDestroy() { await this.poller?.stop(); }

  async register(user: string, input: unknown, factoryInput: unknown) {
    if (!pushProject()) throw new ServiceUnavailableException('Push Android belum tersedia.');
    const installation = requireInstallation(input);
    const factory = requireUuid(factoryInput);
    const { rowCount } = await this.db.query(`INSERT INTO review_push_installations AS i
      (installation_id,user_id,factory_id,registration_id)
      SELECT $1,a.user_id,a.factory_id,$4 FROM review_memberships a
      WHERE a.user_id=$2 AND a.factory_id=$3 AND a.active AND a.role='ADMIN' AND ${ACTIVE_REVIEW_ACCESS_SQL}
      ON CONFLICT (installation_id) DO UPDATE SET user_id=excluded.user_id,factory_id=excluded.factory_id,
        registration_id=CASE WHEN (i.user_id,i.factory_id)=(excluded.user_id,excluded.factory_id)
          THEN i.registration_id ELSE excluded.registration_id END,refreshed_at=now()`, [installation, user, factory, randomUUID()]);
    if (!rowCount) throw new ForbiddenException('Akses admin pada pabrik ini diperlukan.');
    return { acknowledged: true };
  }

  async revoke(user: string, input: unknown) {
    await this.db.query('DELETE FROM review_push_installations WHERE installation_id=$1 AND user_id=$2', [requireInstallation(input), user]);
    return { acknowledged: true };
  }

  async processOne() {
    const project = pushProject();
    if (!project) return false;
    const { rows: [delivery] } = await this.db.query<Delivery>(`WITH candidate AS (
      SELECT installation_id,user_id,task_id FROM review_push_deliveries
      WHERE status IN ('QUEUED','SENDING') AND available_at<=now() ORDER BY available_at,task_id
      LIMIT 1 FOR UPDATE SKIP LOCKED
    ) UPDATE review_push_deliveries p SET status='SENDING',available_at=now()+interval '90 seconds',claim_id=$1
      FROM candidate c WHERE (p.installation_id,p.user_id,p.task_id)=(c.installation_id,c.user_id,c.task_id)
      RETURNING p.*`, [randomUUID()]);
    if (!delivery) return false;
    const { installation_id, user_id, task_id, claim_id, registration_id, attempts } = delivery;
    const args = [installation_id, user_id, task_id, claim_id];
    const eligible = attempts < 3 && (await this.db.query(`UPDATE review_push_deliveries p SET attempts=attempts+1
      FROM review_push_installations i,admin_review_notifications n,admin_review_tasks t,source_documents d,review_memberships a
      WHERE (p.installation_id,p.user_id,p.task_id,p.claim_id)=($1,$2,$3,$4) AND p.expires_at>now()
        AND (i.installation_id,i.user_id,i.registration_id)=(p.installation_id,p.user_id,p.registration_id)
        AND i.refreshed_at>now()-interval '30 days' AND (n.task_id,n.user_id)=(p.task_id,p.user_id) AND n.read_at IS NULL
        AND t.id=p.task_id AND t.status='PENDING_VALIDATION' AND d.id=t.document_id AND d.current_revision_id=t.revision_id
        AND i.factory_id=d.factory_id AND a.factory_id=d.factory_id AND a.user_id=p.user_id AND a.active AND a.role='ADMIN'
        AND ${ACTIVE_REVIEW_ACCESS_SQL}`, args)).rowCount;
    const outcome = eligible ? await this.send(project, delivery) : 'SKIPPED';
    if (outcome === 'UNREGISTERED') {
      await this.db.query('DELETE FROM review_push_installations WHERE installation_id=$1 AND registration_id=$2', [installation_id, registration_id]);
      return true;
    }
    const state = outcome === 'RETRY' ? (attempts < 2 ? 'QUEUED' : 'FAILED') : outcome;
    await this.db.query(`UPDATE review_push_deliveries SET status=$5,claim_id=NULL,available_at=now()+$6*interval '1 second'
      WHERE (installation_id,user_id,task_id,claim_id)=($1,$2,$3,$4)`, [...args, state, 30 * 2 ** attempts]);
    return true;
  }

  async send(project: string, delivery: Delivery): Promise<Outcome> {
    try {
      const client = await this.google.getClient();
      const response = await client.request<{ error?: { details?: Array<{ errorCode?: string }> } }>({
        url: `https://fcm.googleapis.com/v1/projects/${project}/messages:send`,
        method: 'POST', timeout: 8_000, retry: false, maxRedirects: 0, validateStatus: () => true,
        data: { message: { fid: delivery.installation_id, data: { screen: 'review' },
          notification: { title: 'SobatNira', body: 'Ada pekerjaan baru untuk ditinjau.' },
          android: { ttl: '900s', priority: 'HIGH', notification: { tag: 'sobatnira-review', visibility: 'PRIVATE' } } } },
      });
      if (response.status >= 200 && response.status < 300) return 'SENT';
      if (response.data?.error?.details?.some((detail) => detail.errorCode === 'UNREGISTERED')) return 'UNREGISTERED';
      return response.status === 429 || response.status >= 500 ? 'RETRY' : 'FAILED';
    } catch {
      return 'RETRY';
    }
  }
}
