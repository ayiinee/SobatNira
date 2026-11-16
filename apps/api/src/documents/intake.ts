import { BadRequestException, ConflictException, ForbiddenException, HttpException, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { PoolClient } from 'pg';
import { fields, Inbound, Issue, Note, requireUuid, UUID } from './contracts';
import { Database } from './database';
import { MediaStorage } from './media';
import { correctField } from './revisions';
import { closeClarifications, describeQuestion, openClarifications, Question } from './clarifications';

type Operator = { id: string; factory_id: string };
export type Revision = { id: string; document_id: string; submission_id: string; version: number;
  processing_status: string; operator_status: string; extraction: Note | null; issues: Issue[] };
type Action = { action: 'CONFIRM' | 'CORRECT' | 'ANSWER'; document_id: string; revision_id: string;
  question_id?: string; field_path?: string; value?: unknown };
const digest = (value: Buffer | string) => createHash('sha256').update(value).digest('hex');
const json = (value: unknown) => JSON.stringify(value);

// Only inbound photos and provider-acknowledged bot notices can identify a quoted submission.
const quotedSubmission = `SELECT s.* FROM document_submissions s
  JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id
  WHERE m.provider_message_id=$1 AND m.event->>'chat_id'=$2
  UNION
  SELECT s.* FROM whatsapp_notices n JOIN document_revisions r ON r.id=n.revision_id
  JOIN document_submissions s ON s.id=r.submission_id JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id
  WHERE n.provider_message_id=$1 AND n.status='SENT' AND m.event->>'chat_id'=$2`;

function canRetake(revision: Revision) {
  return revision.operator_status !== 'CONFIRMED' &&
    ['NEEDS_CLARIFICATION','MANUAL_REVIEW_REQUIRED','FAILED_FINAL'].includes(revision.processing_status) &&
    !revision.issues.some(({ code }) => code === 'DOCUMENT_REFERENCE_REQUIRED');
}

export async function audit(db: PoolClient, revision: Revision, action: string, actor: string | null = null, details: object = {}) {
  await db.query(`INSERT INTO audit_events (document_id, revision_id, action, actor_id, details)
    VALUES ($1, $2, $3, $4, $5)`, [revision.document_id, revision.id, action, actor, json(details)]);
}

export async function editRevision(db: PoolClient, base: Revision, next: Note, path: string, source: 'OPERATOR' | 'ADMIN') {
  const issues = base.issues.filter((issue) => issue.field_path !== path);
  const uncertain = fields(next).some(([, field]) => ['AMBIGUOUS','ILLEGIBLE'].includes(field.status));
  const { rows: [revision] } = await db.query<Revision>(`INSERT INTO document_revisions
    (document_id, submission_id, parent_revision_id, version, processing_status, operator_status, extraction, issues)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`, [base.document_id, base.submission_id, base.id, base.version + 1,
    uncertain || issues.some(({ severity }) => severity === 'BLOCKER' || severity === 'ERROR') ? 'NEEDS_CLARIFICATION' : 'EXTRACTED',
    source === 'ADMIN' ? 'NOT_REQUESTED' : 'PENDING', json(next), json(issues)]);
  await db.query('UPDATE source_documents SET current_revision_id=$2 WHERE id=$1', [base.document_id, revision.id]);
  await closeClarifications(db, base.id);
  if (source === 'OPERATOR') await openClarifications(db, revision.id, next, issues);
  return revision;
}

@Injectable()
export class Intake {
  constructor(private readonly db: Database, private readonly media: MediaStorage) {}

  private async operator(db: PoolClient, event: Inbound) {
    const { rows: [operator] } = await db.query<Operator>(`SELECT id, factory_id FROM operator_contacts
      WHERE phone_e164=$1 AND active FOR UPDATE`, [event.sender_phone_e164]);
    if (!operator) throw new ForbiddenException('OPERATOR_NOT_ACTIVE');
    return operator;
  }

  private async inbound(db: PoolClient, operator: Operator, event: Inbound, fingerprint: string) {
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`inbound:${event.provider_message_id}`]);
    const { rows: [existing] } = await db.query(`SELECT * FROM whatsapp_inbound_messages WHERE provider_message_id=$1`, [event.provider_message_id]);
    if (existing) {
      if (existing.operator_id !== operator.id || existing.fingerprint !== fingerprint) throw new ConflictException('IDEMPOTENCY_MISMATCH');
      return { id: existing.id as string, duplicate: true, outcome: existing.outcome };
    }
    const { rows: [window] } = await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM whatsapp_inbound_messages
      WHERE operator_id=$1 AND received_at>now()-interval '1 minute'`, [operator.id]);
    const limit = Number(process.env.WHATSAPP_MAX_INBOUND_PER_MINUTE ?? 30);
    if (window.count >= (Number.isSafeInteger(limit) && limit > 0 ? limit : 30)) throw new HttpException('OPERATOR_RATE_LIMIT', 429);
    const { rows: [created] } = await db.query<{ id: string }>(`INSERT INTO whatsapp_inbound_messages
      (operator_id, provider_message_id, event, fingerprint) VALUES ($1,$2,$3,$4) RETURNING id`,
    [operator.id, event.provider_message_id, json(event), fingerprint]);
    return { id: created.id, duplicate: false, outcome: null };
  }

  async photo(event: Inbound, mime: string, media: Buffer) {
    const sha = digest(media);
    const command = event.caption?.trim() ?? '';
    const reference = /^REVISI\s+(.+)$/i.exec(command)?.[1];
    const retake = /^FOTO ULANG\s+(\S+)\s+(\S+)$/i.exec(command);
    if (/^FOTO ULANG\b/i.test(command) && !retake) throw new BadRequestException('Rujukan foto ulang tidak valid');
    const requested = retake ? requireUuid(retake[1]) : reference ? requireUuid(reference) : null;
    const retakeRevision = retake ? requireUuid(retake[2]) : null;
    const explicitNew = /^BARU$/i.test(command);
    return this.db.transaction(async (db) => {
      const operator = await this.operator(db, event);
      const fingerprint = digest(json([event.chat_id, event.provider_timestamp, event.quoted_message_id ?? null, command, mime, sha]));
      const inbound = await this.inbound(db, operator, event, fingerprint);
      if (inbound.duplicate) return { ...inbound.outcome, duplicate: true };

      const { rows: quotes } = await db.query<{ document_id: string }>(`SELECT DISTINCT s.document_id FROM (${quotedSubmission}) s
        JOIN source_documents d ON d.id=s.document_id WHERE d.factory_id=$3`,
      [event.quoted_message_id ?? null, event.chat_id, operator.factory_id]);
      if (quotes.length > 1) throw new ConflictException('DOCUMENT_REFERENCE_REQUIRED');
      const [quoted] = quotes;
      if ((quoted && requested && quoted.document_id !== requested) || (explicitNew && (quoted || requested))) {
        throw new ConflictException('DOCUMENT_REFERENCE_CONFLICT');
      }
      if (event.quoted_message_id && !quoted && !requested && !explicitNew) throw new ConflictException('DOCUMENT_REFERENCE_REQUIRED');
      const target = requested ?? quoted?.document_id;
      let docId: string;
      let previous: Revision | undefined;
      let submissionExplicitNew = explicitNew;
      if (target) {
        const { rows: [document] } = await db.query(`SELECT * FROM source_documents WHERE id=$1 AND factory_id=$2 FOR UPDATE`,
          [target, operator.factory_id]);
        if (!document) throw new NotFoundException('Dokumen tidak ditemukan');
        docId = document.id;
        const result = await db.query<Revision>('SELECT * FROM document_revisions WHERE id=$1', [document.current_revision_id]);
        previous = result.rows[0];
        if (retakeRevision) {
          if (previous?.id !== retakeRevision || !canRetake(previous)) throw new ConflictException('STALE_OR_UNAVAILABLE_RETAKE');
          const { rows: [source] } = await db.query(`SELECT s.explicit_new FROM document_submissions s
            JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id
            WHERE s.id=$1 AND m.operator_id=$2 AND m.event->>'chat_id'=$3`, [previous.submission_id, operator.id, event.chat_id]);
          if (!source) throw new NotFoundException('Rujukan foto ulang tidak tersedia pada percakapan ini');
          submissionExplicitNew = source.explicit_new;
        } else {
          if (document.document_type !== 'PRODUCTION_NOTE') throw new ConflictException('Hanya nota produksi mendukung foto revisi');
          if (!previous?.extraction || previous.issues.some(({ code }) => code === 'DOCUMENT_REFERENCE_REQUIRED') ||
              ['QUEUED', 'PROCESSING'].includes(previous.processing_status)) throw new ConflictException('Revisi sebelumnya belum siap');
        }
      } else {
        const { rows: [document] } = await db.query(`INSERT INTO source_documents (factory_id) VALUES ($1) RETURNING id`, [operator.factory_id]);
        docId = document.id;
      }
      const key = digest(json([operator.factory_id, event.provider_message_id, sha]));
      await this.media.put(key, mime, media);
      const { rows: [asset] } = await db.query(`INSERT INTO media_assets (factory_id, object_key, mime_type, size_bytes, sha256)
        VALUES ($1,$2,$3,$4,$5) RETURNING id`, [operator.factory_id, key, mime, media.length, sha]);
      const { rows: [submission] } = await db.query(`INSERT INTO document_submissions (document_id, inbound_message_id, media_asset_id, explicit_new)
        VALUES ($1,$2,$3,$4) RETURNING id`, [docId, inbound.id, asset.id, submissionExplicitNew]);
      const { rows: [revision] } = await db.query<Revision>(`INSERT INTO document_revisions
        (document_id, submission_id, parent_revision_id, version) VALUES ($1,$2,$3,$4) RETURNING *`,
      [docId, submission.id, previous?.id ?? null, (previous?.version ?? 0) + 1]);
      await db.query('UPDATE source_documents SET current_revision_id=$2 WHERE id=$1', [docId, revision.id]);
      if (previous) await closeClarifications(db, previous.id);
      await db.query(`UPDATE admin_review_tasks SET status='SUPERSEDED' WHERE document_id=$1
        AND status IN ('PENDING_VALIDATION','MANUAL_REVIEW_REQUIRED')`, [docId]);
      await db.query('INSERT INTO document_jobs (revision_id) VALUES ($1)', [revision.id]);
      await audit(db, revision, retakeRevision ? 'PHOTO_RETAKE_QUEUED' : 'PHOTO_QUEUED', operator.id);
      const outcome = { accepted: true, inbound_message_id: inbound.id, submission_id: submission.id, document_id: docId,
        revision_id: revision.id, processing_status: 'QUEUED', duplicate: false };
      await db.query('UPDATE whatsapp_inbound_messages SET outcome=$2 WHERE id=$1', [inbound.id, json(outcome)]);
      return outcome;
    });
  }

  async status(phone: string, documentId: string, revisionId: string) {
    const { rows: [revision] } = await this.db.query<Revision & { factory_id: string; follow_up: unknown; question: Question | null }>(`SELECT r.*,
      (SELECT jsonb_build_object('id',q.id,'field_path',q.field_path,'issue_code',q.issue_code) FROM clarification_requests q
       WHERE q.revision_id=r.id AND q.status='OPEN' ORDER BY q.created_at,q.field_path LIMIT 1) AS question,
      d.factory_id,(SELECT e.details FROM audit_events e WHERE e.revision_id=r.id AND e.action='OPERATOR_FOLLOW_UP_REQUESTED' LIMIT 1) AS follow_up
      FROM source_documents d JOIN document_revisions r ON r.id=d.current_revision_id
      JOIN document_revisions requested ON requested.id=$3 AND requested.document_id=d.id AND requested.submission_id=r.submission_id
      JOIN operator_contacts o ON o.factory_id=d.factory_id
      JOIN document_submissions s ON s.id=r.submission_id JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id
      WHERE o.phone_e164=$1 AND o.active AND d.id=$2 AND m.operator_id=o.id`,
    [phone, documentId, revisionId]);
    if (!revision) throw new NotFoundException('Revisi aktif tidak ditemukan');
    const { factory_id, question, ...stored } = revision;
    const result = { ...stored, pending_question: describeQuestion(question, revision.extraction, revision.issues),
      photo_retake_allowed: canRetake(revision) };
    if (!revision.issues.some(({ code }) => code === 'DOCUMENT_REFERENCE_REQUIRED')) return result;
    const { rows } = await this.db.query<{ id: string }>(`SELECT d.id FROM source_documents d
      JOIN document_revisions r ON r.id=d.current_revision_id WHERE d.factory_id=$1 AND d.id<>$2 AND d.document_type='PRODUCTION_NOTE'
      AND NOT EXISTS (SELECT FROM jsonb_array_elements(r.issues) i WHERE i->>'code'='DOCUMENT_REFERENCE_REQUIRED')
      ORDER BY d.created_at DESC LIMIT 5`, [factory_id, documentId]);
    return { ...result, candidate_documents: rows.map(({ id }) => id) };
  }

  async quotedContext(phone: string, chat: string, quotedMessageId: string) {
    const { rows: [reference] } = await this.db.query<{ document_id: string; revision_id: string }>(`SELECT s.document_id,r.id AS revision_id
      FROM (${quotedSubmission}) s JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id
      JOIN operator_contacts o ON o.id=m.operator_id AND o.active JOIN source_documents d ON d.id=s.document_id AND d.factory_id=o.factory_id
      JOIN document_revisions r ON r.id=d.current_revision_id AND r.submission_id=s.id
      WHERE o.phone_e164=$3`, [quotedMessageId, chat, phone]);
    if (!reference) throw new NotFoundException('Rujukan foto tidak tersedia pada percakapan ini');
    return reference;
  }

  async reply(event: Inbound, action: Action) {
    if (!action || !['CONFIRM', 'CORRECT', 'ANSWER'].includes(action.action) || !UUID.test(action.document_id) || !UUID.test(action.revision_id) ||
        (action.action === 'CORRECT' && typeof action.field_path !== 'string') ||
        (action.action === 'ANSWER' && (!action.question_id || !UUID.test(action.question_id)))) throw new BadRequestException('Aksi operator tidak valid');
    return this.db.transaction(async (db) => {
      const operator = await this.operator(db, event);
      const fingerprint = digest(json([event.chat_id, event.provider_timestamp, event.quoted_message_id ?? null,
        event.caption ?? null, action.action, action.document_id, action.revision_id, action.field_path, action.value,
        ...(action.action === 'ANSWER' ? [action.question_id] : [])]));
      const inbound = await this.inbound(db, operator, event, fingerprint);
      if (inbound.duplicate) return { ...inbound.outcome, duplicate: true };
      const { rows: [doc] } = await db.query(`SELECT id,current_revision_id FROM source_documents WHERE id=$1 AND factory_id=$2 FOR UPDATE`,
        [action.document_id, operator.factory_id]);
      if (!doc) throw new NotFoundException('Dokumen tidak ditemukan');
      if (doc.current_revision_id !== action.revision_id) throw new ConflictException('STALE_REVISION');
      const { rows: [base] } = await db.query<Revision>(`SELECT r.* FROM document_revisions r
        JOIN document_submissions s ON s.id=r.submission_id JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id
        WHERE r.id=$1 AND m.operator_id=$2 AND m.event->>'chat_id'=$3`, [action.revision_id, operator.id, event.chat_id]);
      if (!base) throw new NotFoundException('Revisi operator tidak ditemukan');
      if (!base.extraction || base.issues.some(({ severity, field_path }) => severity === 'BLOCKER' && !field_path)) {
        throw new ConflictException('Revisi memerlukan tinjauan dokumen');
      }
      let outcome;
      if (action.action !== 'CONFIRM') {
        if (base.operator_status !== 'PENDING') throw new ConflictException('Revisi operator sudah ditutup');
        let question: Question | undefined;
        if (action.action === 'ANSWER') {
          const pending = await db.query<Question>(`SELECT id,field_path,issue_code FROM clarification_requests
            WHERE id=$1 AND revision_id=$2 AND status='OPEN' FOR UPDATE`, [action.question_id, base.id]);
          question = pending.rows[0];
          if (!question) throw new ConflictException('STALE_QUESTION');
        }
        const path = question?.field_path ?? action.field_path!;
        const revision = await editRevision(db, base, correctField(base.extraction, path, action.value, 'OPERATOR_CORRECTION'), path, 'OPERATOR');
        if (question) await db.query(`UPDATE clarification_requests SET status='ANSWERED',answered_at=now(),answer_message_id=$2,
          resolved_by=$3,result_revision_id=$4 WHERE id=$1`, [question.id, inbound.id, operator.id, revision.id]);
        await audit(db, revision, question ? 'CLARIFICATION_ANSWERED' : 'OPERATOR_CORRECTED', operator.id,
          { field_path: path, inbound_message_id: inbound.id, question_id: question?.id });
        outcome = { document_id: doc.id, revision_id: revision.id, operator_status: revision.operator_status };
      } else {
        if (base.operator_status !== 'PENDING') throw new ConflictException('Revisi operator sudah ditutup');
        await db.query(`INSERT INTO operator_confirmations (revision_id, operator_id, inbound_message_id) VALUES ($1,$2,$3)`,
          [base.id, operator.id, inbound.id]);
        await db.query(`UPDATE document_revisions SET operator_status='CONFIRMED' WHERE id=$1`, [base.id]);
        await closeClarifications(db, base.id);
        const { rows: [task] } = await db.query(`INSERT INTO admin_review_tasks (document_id, revision_id) VALUES ($1,$2) RETURNING id`,
          [doc.id, base.id]);
        await db.query(`INSERT INTO admin_review_notifications (task_id,user_id)
          SELECT $1,user_id FROM review_memberships WHERE factory_id=$2 AND active AND role='ADMIN'`, [task.id, operator.factory_id]);
        await audit(db, base, 'OPERATOR_CONFIRMED', operator.id);
        outcome = { document_id: doc.id, revision_id: base.id, task_id: task.id, operator_status: 'CONFIRMED' };
      }
      await db.query('UPDATE whatsapp_inbound_messages SET outcome=$2 WHERE id=$1', [inbound.id, json(outcome)]);
      return { ...outcome, duplicate: false };
    });
  }
}
