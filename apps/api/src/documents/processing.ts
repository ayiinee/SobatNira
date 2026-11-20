import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { SCHEMA_VERSION, DocumentType, Envelope, Issue, Note, readEnvelope } from './contracts';
import { Database } from './database';
import { audit, Revision } from './intake';
import { mergeProduction } from './revisions';
import { openClarifications } from './clarifications';
import { operatorChecks } from './operator-readiness';
import { enqueueNotice } from './notices';

type Job = { id: string; revision_id: string; attempts: number; claim_token: string; eligible_at: Date };
type Work = Revision & { created_at: Date; factory_id: string; document_type: DocumentType; parent_revision_id: string | null;
  media_asset_id: string; object_key: string; mime_type: string; explicit_new: boolean };
const MAX_ATTEMPTS = 3;
const TIMEOUT = 240_000;
const LEASE = TIMEOUT + 30_000;

@Injectable()
export class DocumentProcessor implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DocumentProcessor.name);
  private timer?: ReturnType<typeof setInterval>;
  private busy?: Promise<unknown>;

  constructor(private readonly db: Database) {}

  onModuleInit() {
    if (process.env.DOCUMENT_WORKER_ENABLED !== 'true') return;
    this.timer = setInterval(() => {
      if (this.busy) return;
      this.busy = this.processOne().catch(() => { this.logger.warn('Pekerjaan dokumen belum dapat diproses'); })
        .finally(() => { this.busy = undefined; });
    }, 500);
    this.timer.unref();
  }

  async onModuleDestroy() {
    clearInterval(this.timer);
    await this.busy;
  }

  async processOne() {
    const task = await this.db.transaction(async (db) => {
      const { rows: [job] } = await db.query<Job>(`WITH candidate AS (
        SELECT id,CASE WHEN status='PROCESSING' THEN lease_until ELSE available_at END AS eligible_at
        FROM document_jobs WHERE (status='QUEUED' AND available_at<=now()) OR
          (status='PROCESSING' AND lease_until<=now()) ORDER BY available_at LIMIT 1 FOR UPDATE SKIP LOCKED
        ) UPDATE document_jobs j SET status='PROCESSING',attempts=j.attempts+1,lease_until=now()+$2*interval '1 millisecond',
          claim_token=$1 FROM candidate WHERE j.id=candidate.id RETURNING j.*,candidate.eligible_at`, [randomUUID(), LEASE]);
      if (!job) return null;
      const { rows: [work] } = await db.query<Work>(`SELECT r.*,d.factory_id,d.document_type,s.media_asset_id,s.explicit_new,a.object_key,a.mime_type
        FROM document_revisions r JOIN source_documents d ON d.id=r.document_id
        JOIN document_submissions s ON s.id=r.submission_id JOIN media_assets a ON a.id=s.media_asset_id
        WHERE r.id=$1`, [job.revision_id]);
      await db.query(`UPDATE document_revisions SET processing_status='PROCESSING' WHERE id=$1`, [work.id]);
      return { job, work };
    });
    if (!task) return false;
    const { job, work } = task;
    const requestId = randomUUID();
    const startedAt = Date.now();
    const queueMs = Math.max(0, startedAt - work.created_at.getTime());
    const eligibleWaitMs = Math.max(0, startedAt - job.eligible_at.getTime());
    const started = performance.now();
    let result: Envelope | undefined;
    let errorCode: string | undefined;
    try {
      if (job.attempts > MAX_ATTEMPTS) throw new Error('OCR_LEASE_EXHAUSTED');
      result = await this.extract(work, requestId);
    } catch (error) {
      const code = error instanceof Error ? error.message : '';
      errorCode = error instanceof Error && error.name === 'TimeoutError' ? 'OCR_TIMEOUT' :
        ['INVALID_OCR_CONTRACT', 'OCR_LEASE_EXHAUSTED'].includes(code) ? code : 'OCR_UNAVAILABLE';
    }
    const extractionMs = Math.round(performance.now() - started);

    const outcome = await this.db.transaction(async (db) => {
      const { rowCount } = await db.query(`SELECT id FROM document_jobs WHERE id=$1 AND claim_token=$2 AND status='PROCESSING' FOR UPDATE`, [job.id, job.claim_token]);
      if (!rowCount) return;
      await db.query(`INSERT INTO extraction_attempts (id,job_id,attempt,envelope,error_code) VALUES ($1,$2,$3,$4,$5)`,
        [requestId, job.id, job.attempts, result ? JSON.stringify(result) : null, errorCode ?? null]);
      if (!result && job.attempts < MAX_ATTEMPTS) {
        const delay = 1_000 * 2 ** job.attempts + Math.floor(Math.random() * 500);
        await db.query(`UPDATE document_jobs SET status='QUEUED',available_at=now()+$2*interval '1 millisecond',lease_until=NULL,claim_token=NULL WHERE id=$1`, [job.id, delay]);
        await db.query(`UPDATE document_revisions SET processing_status='QUEUED' WHERE id=$1`, [work.id]);
        await audit(db, work, 'OCR_RETRY_SCHEDULED', null, { attempt: job.attempts, code: errorCode });
        return 'QUEUED';
      }

      let extraction = result?.extraction ?? null;
      const issues: Issue[] = (result?.issues ?? []).filter((issue) => typeof issue?.code === 'string' &&
        typeof issue.message === 'string' && ['INFO','WARNING','ERROR','BLOCKER'].includes(issue.severity));
      let status = !result ? 'FAILED_FINAL' : !extraction ? 'MANUAL_REVIEW_REQUIRED'
        : result.status === 'COMPLETED' ? 'EXTRACTED' : 'NEEDS_CLARIFICATION';
      if (!result) issues.push({ code: errorCode ?? 'OCR_UNAVAILABLE', severity: 'ERROR', message: 'Layanan ekstraksi tidak tersedia.' });
      if (extraction && work.document_type !== 'UNKNOWN' && work.document_type !== extraction.document_type) {
        issues.push({ code: 'DOCUMENT_TYPE_MISMATCH', severity: 'BLOCKER', message: 'Jenis foto berbeda dari dokumen yang dirujuk.' });
        extraction = null;
        status = 'MANUAL_REVIEW_REQUIRED';
      }
      if (extraction?.document_type === 'PRODUCTION_NOTE') {
        await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`production:${work.factory_id}`]);
        const { rows: [previous] } = await db.query<{ extraction: Note }>(`SELECT r.extraction FROM document_revisions r
          WHERE r.document_id=$1 AND r.version<$2 AND r.extraction->>'document_type'='PRODUCTION_NOTE'
            AND NOT EXISTS (SELECT FROM jsonb_array_elements(r.issues) i WHERE i->>'severity'='BLOCKER')
          ORDER BY r.version DESC LIMIT 1`, [work.document_id, work.version]);
        if (previous) {
          const merged = mergeProduction(previous.extraction, extraction);
          extraction = merged.note;
          issues.push(...merged.issues);
        } else if (!work.explicit_new) {
          const { rowCount: candidates } = await db.query(`SELECT 1 FROM source_documents d
            JOIN document_revisions r ON r.id=d.current_revision_id
            WHERE d.factory_id=$1 AND d.id<>$2 AND d.document_type='PRODUCTION_NOTE'
            AND NOT EXISTS (SELECT FROM jsonb_array_elements(r.issues) i WHERE i->>'code'='DOCUMENT_REFERENCE_REQUIRED') LIMIT 1`,
          [work.factory_id, work.document_id]);
          if (candidates) issues.push({ code: 'DOCUMENT_REFERENCE_REQUIRED', severity: 'BLOCKER',
            message: 'Tentukan apakah foto ini dokumen baru atau revisi dari dokumen yang sudah ada.' });
        }
      }
      const checks = extraction && operatorChecks(extraction, issues);
      if (checks && (checks.questions.size || checks.documentBlocked)) status = 'NEEDS_CLARIFICATION';
      const operatorStatus = checks && !checks.documentBlocked ? 'PENDING' : 'NOT_REQUESTED';
      if (extraction) await db.query('UPDATE source_documents SET document_type=$2 WHERE id=$1 AND current_revision_id=$3',
        [work.document_id, extraction.document_type, work.id]);
      await db.query(`UPDATE document_revisions SET extraction=$2,issues=$3,processing_status=$4,operator_status=$5 WHERE id=$1`,
        [work.id, extraction ? JSON.stringify(extraction) : null, JSON.stringify(issues), status, operatorStatus]);
      if (extraction && operatorStatus === 'PENDING') await openClarifications(db, work.id, extraction, issues);
      await db.query(`UPDATE document_jobs SET status=$2,lease_until=NULL,claim_token=NULL WHERE id=$1`,
        [job.id, !result || result.status === 'FAILED' ? 'FAILED' : 'COMPLETED']);
      if (status === 'MANUAL_REVIEW_REQUIRED' || status === 'FAILED_FINAL') {
        await db.query(`INSERT INTO admin_review_tasks (document_id,revision_id,status)
          SELECT id,$2,'MANUAL_REVIEW_REQUIRED' FROM source_documents WHERE id=$1 AND current_revision_id=$2`,
        [work.document_id, work.id]);
      }
      await enqueueNotice(db, work.id, 'OCR_RESULT');
      await audit(db, work, status, null, { attempt: job.attempts, request_id: requestId });
      return status;
    });
    if (outcome) this.logger.log({ event: 'ocr_attempt', revisionId: work.id, requestId, attempt: job.attempts,
      queueMs, eligibleWaitMs, extractionMs, outcome, errorCode, documentType: result?.extraction?.document_type ?? work.document_type,
      mediaMs: result?.processing.media_duration_ms, inferParseMs: result?.processing.infer_parse_duration_ms,
      serviceMs: result?.processing.duration_ms, rereadAttempts: result?.processing.reread_attempts,
      rereadMs: result?.processing.reread_duration_ms, visionModel: result?.processing.vision_model,
      visionPromptVersion: result?.processing.prompt_version });
    return true;
  }

  private async extract(work: Work, requestId: string) {
    const token = process.env.AI_SERVICE_INTERNAL_TOKEN;
    if (!token) throw new Error('OCR_UNAVAILABLE');
    const base = process.env.AI_SERVICE_BASE_URL || process.env.AI_BASE_URL || 'http://127.0.0.1:8000';
    const ids = { request_id: requestId, document_id: work.document_id, submission_id: work.submission_id,
      revision_id: work.id, source_asset_id: work.media_asset_id };
    const response = await fetch(new URL('/internal/v1/ocr/extract', base), {
      method: 'POST', signal: AbortSignal.timeout(TIMEOUT), redirect: 'error',
      headers: { 'Content-Type': 'application/json', 'X-Internal-Service-Token': token },
      body: JSON.stringify({ request_id: ids.request_id, document_id: ids.document_id, submission_id: ids.submission_id,
        revision_id: ids.revision_id, factory_id: work.factory_id, schema_version: SCHEMA_VERSION, template_version: '1.0.0',
        document_type_hint: work.document_type === 'UNKNOWN' ? null : work.document_type,
        image: { asset_id: work.media_asset_id, object_key: work.object_key, mime_type: work.mime_type } }),
    });
    if (!response.ok) throw new Error('OCR_UNAVAILABLE');
    return readEnvelope(await response.json(), ids);
  }
}
