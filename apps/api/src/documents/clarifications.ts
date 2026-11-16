import { PoolClient } from 'pg';
import { fields, Issue, Note } from './contracts';

export type Question = { id: string; field_path: string; issue_code: string };

export async function openClarifications(db: PoolClient, revisionId: string, note: Note, issues: Issue[]) {
  const openFields = fields(note).filter(([, field]) => field.status === 'AMBIGUOUS' || field.status === 'ILLEGIBLE');
  if (!openFields.length) return;
  const conflicts = new Set(issues.filter((issue) => issue.code === 'OCR_VISION_DISAGREE').map((issue) => issue.field_path));
  const paths = openFields.map(([path]) => path);
  const codes = openFields.map(([path, field]) => conflicts.has(path) ? 'OCR_VISION_DISAGREE' : `${field.status}_FIELD`);
  await db.query(`INSERT INTO clarification_requests (revision_id,field_path,issue_code,status)
    SELECT $1,path,code,'OPEN' FROM unnest($2::text[],$3::text[]) AS v(path,code)`, [revisionId, paths, codes]);
}

export async function closeClarifications(db: PoolClient, revisionId: string) {
  await db.query(`UPDATE clarification_requests SET status='CLOSED' WHERE revision_id=$1 AND status='OPEN'`, [revisionId]);
}

export function describeQuestion(question: Question | null, note: Note | null, issues: Issue[]) {
  if (!question || !note) return null;
  const field = fields(note).find(([path]) => path === question.field_path)?.[1];
  if (!field) return null;
  const disagreement = issues.find((issue) => issue.field_path === question.field_path && issue.code === 'OCR_VISION_DISAGREE');
  const alternatives: unknown[] = Array.isArray(disagreement?.candidates) ? disagreement.candidates : field.alternatives ?? [];
  const values = alternatives.flatMap((candidate) => {
    const value = (candidate as { value?: unknown } | null)?.value;
    return typeof value === 'number' || (typeof value === 'string' && value.length <= 120) ? [value] : [];
  });
  const candidates = [...new Set(values)].slice(0, 4);
  return { ...question, unit: field.unit, candidates, raw_value: field.raw_value };
}
