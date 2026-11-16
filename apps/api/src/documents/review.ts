import { BadRequestException, ConflictException, Injectable, NotFoundException, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { fields, requireUuid, UUID } from './contracts';
import { parsePage } from '../production/production.dto';
import { Database } from './database';
import { audit, editRevision, Revision } from './intake';
import { correctField } from './revisions';
import { manualNote } from './manual-note';
import { enqueueNotice } from './notices';
import { supabaseKey } from './config';
import { PostedIntake, postedIntakeColumns, TruckIntake } from './truck-intake';
import { ProductionMilling } from './production-milling';

@Injectable()
export class Review {
  constructor(private readonly db: Database, private readonly truckIntake: TruckIntake,
    private readonly productionMilling: ProductionMilling) {}

  async user(authorization?: string) {
    if (!authorization || !/^Bearer \S{1,8192}$/.test(authorization)) throw new UnauthorizedException();
    const project = process.env.SUPABASE_URL;
    const apiKey = supabaseKey();
    if (!project || !apiKey) throw new ServiceUnavailableException('Autentikasi mobile belum dikonfigurasi');
    let response: Response;
    try {
      const url = new URL('/auth/v1/user', project);
      if (process.env.NODE_ENV === 'production' && url.protocol !== 'https:') throw new Error('HTTPS required');
      response = await fetch(url, { headers: { authorization, apikey: apiKey }, signal: AbortSignal.timeout(5_000), redirect: 'error' });
    } catch {
      throw new ServiceUnavailableException('Autentikasi mobile tidak tersedia');
    }
    if (response.status === 401 || response.status === 403) throw new UnauthorizedException();
    if (!response.ok) throw new ServiceUnavailableException('Autentikasi mobile tidak tersedia');
    const { id } = await response.json();
    if (typeof id !== 'string' || !UUID.test(id)) throw new UnauthorizedException();
    return id;
  }

  async list(user: string, status: string, page: number, limit: number) {
    if (!['PENDING_VALIDATION', 'VALIDATED', 'RETURNED_FOR_CORRECTION', 'MANUAL_REVIEW_REQUIRED'].includes(status) ||
        !Number.isSafeInteger(page) || page < 1 || page > 10000 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
      throw new BadRequestException('Filter antrean tidak valid');
    }
    const { rows } = await this.db.query(`SELECT t.id,t.document_id,t.status,d.document_type,r.id AS revision_id,r.version,
      m.received_at,o.display_name AS sender_name,jsonb_array_length(r.issues) AS issue_count,s.media_asset_id
      FROM admin_review_tasks t JOIN source_documents d ON d.id=t.document_id
      JOIN review_memberships a ON a.factory_id=d.factory_id AND a.user_id=$1 AND a.active
      JOIN document_revisions r ON r.id=t.revision_id JOIN document_submissions s ON s.id=r.submission_id
      JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id JOIN operator_contacts o ON o.id=m.operator_id
      WHERE t.status=$2 ORDER BY t.created_at DESC,t.id LIMIT $3 OFFSET $4`, [user, status, limit, (page - 1) * limit]);
    return { items: rows, page, page_size: limit };
  }

  async detail(user: string, id: string) {
    return this.db.transaction(async (db) => {
      await db.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const { rows: [task] } = await db.query(`SELECT t.*,d.factory_id,d.document_type,r.version,r.extraction,r.issues,r.operator_status,
        r.processing_status,s.media_asset_id,d.current_revision_id,m.received_at,o.display_name AS sender_name,a.role
        FROM admin_review_tasks t JOIN source_documents d ON d.id=t.document_id
        JOIN review_memberships a ON a.factory_id=d.factory_id AND a.user_id=$1 AND a.active
        JOIN document_revisions r ON r.id=t.revision_id JOIN document_submissions s ON s.id=r.submission_id
        JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id JOIN operator_contacts o ON o.id=m.operator_id
        WHERE t.id=$2`, [user, id]);
      if (!task) throw new NotFoundException('Pekerjaan tidak ditemukan');
      const { rows: history } = await db.query(`SELECT r.id,r.version,r.parent_revision_id,r.processing_status,r.operator_status,
        s.media_asset_id,r.created_at,c.confirmed_at,o.display_name AS confirmed_by
        FROM document_revisions r JOIN document_submissions s ON s.id=r.submission_id
        LEFT JOIN operator_confirmations c ON c.revision_id=r.id LEFT JOIN operator_contacts o ON o.id=c.operator_id
        WHERE r.document_id=$1 AND r.version<=$2 ORDER BY r.version DESC`, [task.document_id, task.version]);
      const { rows: auditTrail } = await db.query(`SELECT e.action,e.revision_id,e.created_at FROM audit_events e
        JOIN document_revisions r ON r.id=e.revision_id WHERE e.document_id=$1 AND r.version<=$2
        ORDER BY e.created_at,e.id`, [task.document_id, task.version]);
      let intake: PostedIntake | null = null;
      if (task.document_type === 'TRUCK_ARRIVAL_NOTE' && task.status === 'VALIDATED') {
        const result = await db.query<PostedIntake>(`SELECT ${postedIntakeColumns} FROM sobatnira.intake_records
          WHERE factory_id=$1 AND ocr_document_id=$2 AND ocr_revision_id=$3`,
        [task.factory_id, task.document_id, task.revision_id]);
        intake = result.rows[0] ?? null;
      }
      const milling = task.document_type === 'PRODUCTION_NOTE'
        ? await this.productionMilling.posted(db, task.factory_id, task.document_id, task.version) : [];
      return { ...task, revisions: history, operator_confirmation: history.find((row) => row.confirmed_at) ?? null,
        intake, milling, audit: auditTrail, actions: task.current_revision_id !== task.revision_id ? [] : task.status === 'PENDING_VALIDATION'
          ? ['CORRECT', 'VALIDATE', 'RETURN'] : task.status === 'MANUAL_REVIEW_REQUIRED' ? ['MANUAL_ENTRY', 'RETURN'] : [] };
    });
  }

  intakeLots(user: string, id: string, query: unknown) {
    return this.productionLots(user, id, query, 'TRUCK_ARRIVAL_NOTE');
  }

  productionLots(user: string, id: string, query: unknown, documentType: 'TRUCK_ARRIVAL_NOTE' | 'PRODUCTION_NOTE') {
    const page = parsePage(query);
    return this.db.transaction(async (db) => {
      const { rows: [task] } = await db.query<{ factory_id: string }>(`SELECT d.factory_id
        FROM admin_review_tasks t JOIN source_documents d ON d.id=t.document_id
        JOIN review_memberships a ON a.factory_id=d.factory_id AND a.user_id=$1 AND a.active
        WHERE t.id=$2 AND d.document_type=$3 AND t.status='PENDING_VALIDATION'
          AND d.current_revision_id=t.revision_id FOR SHARE OF a`, [user, id, documentType]);
      if (!task) throw new NotFoundException('Pekerjaan produksi tidak ditemukan.');
      return documentType === 'TRUCK_ARRIVAL_NOTE' ? this.truckIntake.choices(db, user, task.factory_id, page)
        : this.productionMilling.choices(db, user, task.factory_id, page);
    });
  }

  async unreadNotifications(user: string) {
    const { rows: [result] } = await this.db.query<{ unread_count: number }>(`SELECT count(*)::int AS unread_count
      FROM admin_review_notifications n JOIN admin_review_tasks t ON t.id=n.task_id AND t.status='PENDING_VALIDATION'
      JOIN source_documents d ON d.id=t.document_id
      JOIN review_memberships a ON a.factory_id=d.factory_id AND a.user_id=n.user_id AND a.active AND a.role='ADMIN'
      WHERE n.user_id=$1 AND n.read_at IS NULL`, [user]);
    return result;
  }

  async markNotificationRead(user: string, id: string) {
    await this.db.query(`UPDATE admin_review_notifications n SET read_at=now()
      FROM admin_review_tasks t JOIN source_documents d ON d.id=t.document_id JOIN review_memberships a ON a.factory_id=d.factory_id
      WHERE n.task_id=t.id AND n.task_id=$2 AND n.user_id=$1 AND a.user_id=n.user_id AND a.active AND a.role='ADMIN'
        AND n.read_at IS NULL`, [user, id]);
    return { acknowledged: true };
  }

  async asset(user: string, task: string, asset: string) {
    const { rows: [record] } = await this.db.query(`SELECT m.object_key,m.mime_type FROM admin_review_tasks t
      JOIN source_documents d ON d.id=t.document_id JOIN review_memberships a ON a.factory_id=d.factory_id AND a.user_id=$1 AND a.active
      JOIN document_revisions tr ON tr.id=t.revision_id
      JOIN document_revisions r ON r.document_id=d.id AND r.version<=tr.version
      JOIN document_submissions s ON s.id=r.submission_id JOIN media_assets m ON m.id=s.media_asset_id AND m.factory_id=d.factory_id
      WHERE t.id=$2 AND m.id=$3 LIMIT 1`, [user, task, asset]);
    if (!record) throw new NotFoundException('Foto tidak ditemukan');
    return record as { object_key: string; mime_type: string };
  }

  async change(user: string, document: string, action: 'CORRECT' | 'VALIDATE' | 'RETURN' | 'MANUAL_ENTRY', key: string | undefined,
    body: Record<string, unknown> | undefined) {
    if (!body || !key || !/^[A-Za-z0-9_-]{12,128}$/.test(key) || !Number.isSafeInteger(body.expected_version)) {
      throw new BadRequestException('Versi revisi dan Idempotency-Key wajib');
    }
    const revisionId = requireUuid(body.revision_id);
    const lotSelection = body.lot_id === undefined && body.supplier_id === undefined ? [] : [body.lot_id, body.supplier_id];
    const fingerprint = createHash('sha256').update(JSON.stringify([document, action, revisionId, body.expected_version,
      body.field_path, body.value, body.decision, body.reason_code, body.comment, body.request_operator_follow_up, body.note,
      ...(action === 'MANUAL_ENTRY' ? [body.document_type, body.values, body.rows_per_block] : []), ...lotSelection,
      ...(body.milling === undefined ? [] : [body.milling])])).digest('hex');
    return this.db.transaction(async (db) => {
      const { rows: [doc] } = await db.query(`SELECT d.* FROM source_documents d
        JOIN review_memberships a ON a.factory_id=d.factory_id AND a.user_id=$1 AND a.active
        WHERE d.id=$2 FOR UPDATE OF d FOR SHARE OF a`, [user, document]);
      if (!doc) throw new NotFoundException('Dokumen tidak ditemukan');
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`mobile:${user}:${key}`]);
      const { rows: [prior] } = await db.query(`SELECT * FROM mobile_review_actions WHERE user_id=$1 AND idempotency_key=$2`, [user, key]);
      if (prior) {
        if (prior.fingerprint !== fingerprint) throw new ConflictException('IDEMPOTENCY_MISMATCH');
        return prior.outcome;
      }
      if (doc.current_revision_id !== revisionId) throw new ConflictException('STALE_REVISION');
      const { rows: [base] } = await db.query<Revision>('SELECT * FROM document_revisions WHERE id=$1', [revisionId]);
      if (base.version !== body.expected_version) throw new ConflictException('STALE_REVISION');
      const { rows: [task] } = await db.query(`SELECT * FROM admin_review_tasks WHERE revision_id=$1 AND status IN
        ('PENDING_VALIDATION','MANUAL_REVIEW_REQUIRED') FOR UPDATE`, [revisionId]);
      if (!task) throw new ConflictException('Revisi tidak berada di antrean terbuka');
      if ((action === 'MANUAL_ENTRY' && task.status !== 'MANUAL_REVIEW_REQUIRED') ||
          (['CORRECT','VALIDATE'].includes(action) && task.status !== 'PENDING_VALIDATION')) {
        throw new ConflictException('Aksi tidak tersedia untuk status tugas ini');
      }
      let outcome;
      if (action === 'MANUAL_ENTRY') {
        if (base.extraction || typeof body.note !== 'string' || !body.note.trim() || body.note.length > 1000) {
          throw new BadRequestException('Catatan pemeriksaan foto wajib untuk isian manual');
        }
        const note = manualNote(body);
        if (doc.document_type !== 'UNKNOWN' && note.document_type !== doc.document_type) throw new ConflictException('Jenis nota berbeda dari dokumen sumber');
        const revision = await editRevision(db, { ...base, issues: [] }, note, '', 'ADMIN');
        await db.query('UPDATE source_documents SET document_type=$2 WHERE id=$1', [document, note.document_type]);
        await db.query(`UPDATE admin_review_tasks SET revision_id=$2,status='PENDING_VALIDATION' WHERE id=$1`, [task.id, revision.id]);
        await audit(db, revision, 'ADMIN_MANUAL_DRAFT', user, { note: body.note.trim(), source_revision_id: base.id });
        outcome = { revision_id: revision.id, version: revision.version, status: 'PENDING_VALIDATION' };
      } else if (action === 'CORRECT') {
        if (!base.extraction || typeof body.field_path !== 'string') throw new BadRequestException('Field koreksi wajib');
        const edited = correctField(base.extraction, body.field_path, body.value, 'ADMIN_CORRECTION');
        const revision = await editRevision(db, base, edited, body.field_path, 'ADMIN');
        await db.query('UPDATE admin_review_tasks SET revision_id=$2 WHERE id=$1', [task.id, revision.id]);
        const previous = fields(base.extraction).find(([path]) => path === body.field_path)?.[1];
        await audit(db, revision, 'ADMIN_CORRECTED', user, { field_path: body.field_path,
          previous_revision_id: base.id, before: previous?.normalized_value ?? null, after: body.value });
        outcome = { revision_id: revision.id, version: revision.version, status: 'PENDING_VALIDATION' };
      } else if (action === 'VALIDATE') {
        if (body.decision !== 'VALIDATED' || (body.note !== undefined && (typeof body.note !== 'string' || body.note.length > 1000))) {
          throw new BadRequestException('Keputusan validasi tidak valid');
        }
        if (!base.extraction || base.issues.some(({ severity }) => ['ERROR', 'BLOCKER'].includes(severity)) ||
            fields(base.extraction).some(([, field]) => ['AMBIGUOUS','ILLEGIBLE'].includes(field.status)) ||
            !fields(base.extraction).some(([, field]) => field.status === 'READ' && field.normalized_value !== null)) {
          throw new ConflictException('Selesaikan konflik hasil ekstraksi sebelum validasi');
        }
        if (base.extraction.document_type === 'TRUCK_ARRIVAL_NOTE') {
          const header = new Map(fields(base.extraction.header, 'header'));
          const value = (path: string) => {
            const field = header.get(`header.${path}`);
            return field?.status === 'READ' ? field.normalized_value : null;
          };
          const weight = value('net_weight_kg');
          if (!value('arrival_date') || !value('supplier_name') || !value('cane_type') || typeof weight !== 'number' || weight <= 0) {
            throw new ConflictException('Lengkapi tanggal kedatangan, pemasok, jenis tebu, dan berat bersih positif sebelum validasi');
          }
        }
        await db.query(`INSERT INTO document_approvals (document_id,revision_id,user_id,note) VALUES ($1,$2,$3,$4)`,
          [document, revisionId, user, body.note ?? null]);
        const intake = doc.document_type === 'TRUCK_ARRIVAL_NOTE'
          ? await this.truckIntake.post(db, {
            documentId: document, revisionId, userId: user, factoryId: doc.factory_id,
            lotId: requireUuid(body.lot_id), supplierId: requireUuid(body.supplier_id), note: base.extraction,
          }) : null;
        const milling = doc.document_type === 'PRODUCTION_NOTE'
          ? await this.productionMilling.post(db, {
            documentId: document, revisionId, version: base.version, userId: user, factoryId: doc.factory_id,
            note: base.extraction, mappings: body.milling,
          }) : null;
        await db.query(`UPDATE admin_review_tasks SET status='VALIDATED' WHERE id=$1`, [task.id]);
        await audit(db, base, 'ADMIN_VALIDATED', user, intake ? { intake_record_id: intake.id, lot_id: intake.lot_id }
          : milling ? { milling_record_ids: milling.map(({ id }) => id) } : undefined);
        outcome = { revision_id: revisionId, version: base.version, status: 'VALIDATED',
          ...(intake ? { intake } : {}), ...(milling ? { milling } : {}) };
      } else {
        if (typeof body.reason_code !== 'string' || !/^[A-Z_]{1,64}$/.test(body.reason_code) ||
            typeof body.comment !== 'string' || body.comment.length < 1 || body.comment.length > 1000 ||
            typeof body.request_operator_follow_up !== 'boolean') throw new BadRequestException('Alasan pengembalian wajib');
        await db.query(`UPDATE admin_review_tasks SET status='RETURNED_FOR_CORRECTION' WHERE id=$1`, [task.id]);
        // The previous confirmation and its audit remain bound to the old revision.
        if (body.request_operator_follow_up && base.extraction) {
          const revision = await editRevision(db, base, base.extraction, '', 'OPERATOR');
          await audit(db, revision, 'OPERATOR_FOLLOW_UP_REQUESTED', user, { reason_code: body.reason_code, comment: body.comment });
          await enqueueNotice(db, revision.id, 'ADMIN_RETURNED');
        } else if (body.request_operator_follow_up) {
          await audit(db, base, 'OPERATOR_FOLLOW_UP_REQUESTED', user, { reason_code: body.reason_code, comment: body.comment });
          await enqueueNotice(db, base.id, 'ADMIN_RETURNED');
        }
        await audit(db, base, 'ADMIN_RETURNED', user, { reason_code: body.reason_code, comment: body.comment,
          request_operator_follow_up: body.request_operator_follow_up });
        outcome = { revision_id: revisionId, version: base.version, status: 'RETURNED_FOR_CORRECTION' };
      }
      await db.query(`INSERT INTO mobile_review_actions (user_id,idempotency_key,fingerprint,outcome) VALUES ($1,$2,$3,$4)`,
        [user, key, fingerprint, JSON.stringify(outcome)]);
      return outcome;
    });
  }
}
