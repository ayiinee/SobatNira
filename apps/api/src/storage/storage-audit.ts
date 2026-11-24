// Read-only review heuristics, deliberately separate from any deletion API.
export const AUDIT_VERSION = 'storage-review-v1';
export type InventoryObject = { key: string; bytes: number; modifiedAt: string | null };
export type ObjectReference = { key: string; source: string; lastAttemptAt?: string };

const uuid = '[a-f0-9-]{36}';
export function objectCategory(key: string) {
  if (/^originals\/[a-f0-9]{64}$/.test(key)) return 'original';
  if (/^reports\/[a-f0-9]{64}$/.test(key)) return 'report';
  if (new RegExp(`^tenants/${uuid}/factories/${uuid}/intake-documents/${uuid}/evidence/${uuid}\\.(jpg|jpeg|png|webp)$`).test(key)) return 'evidence';
  return 'unknown';
}

export function reviewObject(object: InventoryObject, references: ObjectReference[], now: Date, ageHours: number) {
  if (!Number.isFinite(ageHours) || ageHours < 1 || !Number.isFinite(now.getTime()) ||
      !Number.isSafeInteger(object.bytes) || object.bytes < 0) throw new Error('Invalid audit input');
  const category = objectCategory(object.key);
  const attached = references.filter(ref => ref.source !== 'upload_unattached');
  const dates = [object.modifiedAt, ...references.map(ref => ref.lastAttemptAt).filter(Boolean)];
  const invalidDate = dates.some(date => !date || !Number.isFinite(Date.parse(date)));
  const newest = Math.max(...dates.map(date => Date.parse(date!)));
  const old = !invalidDate && newest <= now.getTime() - ageHours * 3_600_000;
  const state = attached.length ? 'protected_reference' : category === 'unknown' ? 'protected_unknown' :
    !old ? 'protected_recent_or_unknown_age' : 'review_candidate';
  return { ...object, category, state, references: [...new Set(references.map(ref => ref.source))],
    reason: state === 'review_candidate' ? 'No known durable reference; manual investigation required' : state,
    policyVersion: AUDIT_VERSION, deletionAllowed: false as const };
}

// All rows protect objects, including abandoned drafts and historical revisions.
// Predictable export keys protect failed/queued jobs whose upload may precede COMMIT.
export async function objectReferences(db: { query(sql: string, args: unknown[]): Promise<{ rows: ObjectReference[] }> }, keys: string[]) {
  const { rows } = await db.query(`
    SELECT object_key AS key,'intake_evidence' AS source FROM sobatnira.intake_evidence WHERE object_key=ANY($1::text[])
    UNION ALL SELECT 'originals/'||object_key,'media_asset' FROM public.media_assets WHERE 'originals/'||object_key=ANY($1::text[])
    UNION ALL SELECT 'originals/'||object_key,
      CASE WHEN attached_asset_id IS NULL THEN 'upload_unattached' ELSE 'upload_attached' END
      FROM public.media_uploads WHERE 'originals/'||object_key=ANY($1::text[])
    UNION ALL SELECT 'reports/'||(a.value->>'key'),'report_artifact'
      FROM sobatnira.report_exports r CROSS JOIN LATERAL jsonb_each(r.artifacts) a
      WHERE ('reports/'||(a.value->>'key'))=ANY($1::text[])
    UNION ALL SELECT 'reports/'||encode(sha256(convert_to(r.id::text||':'||f.format,'UTF8')),'hex'),
      'report_job_'||r.status FROM sobatnira.report_exports r CROSS JOIN (VALUES ('pdf'),('xlsx')) f(format)
      WHERE ('reports/'||encode(sha256(convert_to(r.id::text||':'||f.format,'UTF8')),'hex'))=ANY($1::text[])
    `, [keys]);
  const uploads = await db.query(`SELECT 'originals/'||object_key AS key,'upload_unattached' AS source,
    last_attempt_at::text AS "lastAttemptAt" FROM public.media_uploads
    WHERE attached_asset_id IS NULL AND 'originals/'||object_key=ANY($1::text[])`, [keys]);
  return [...rows, ...uploads.rows];
}
