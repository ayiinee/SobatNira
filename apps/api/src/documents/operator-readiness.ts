import { fields, Issue, Note } from './contracts';

export function operatorChecks(note: Note, issues: Issue[]) {
  const values = new Map(fields(note));
  const questions = new Map<string, string>();
  const requireField = (path: string, valid: boolean, code = 'REQUIRED_FIELD') => {
    if (!valid) questions.set(path, code);
  };
  const read = (path: string) => {
    const field = values.get(path);
    return field?.status === 'READ' ? field.normalized_value : null;
  };
  const hasText = (value: unknown): value is string => typeof value === 'string' && value.trim().length > 0;

  if (note.document_type === 'TRUCK_ARRIVAL_NOTE') {
    for (const key of ['arrival_date', 'supplier_name', 'cane_type']) {
      requireField(`header.${key}`, hasText(read(`header.${key}`)));
    }
    const weight = read('header.net_weight_kg');
    requireField('header.net_weight_kg', typeof weight === 'number' && Number.isFinite(weight) && weight > 0);
  }

  const blocks = Array.isArray(note.cane_blocks) ? note.cane_blocks : [];
  const labels = new Set<string>();
  let documentBlocked = note.document_type === 'PRODUCTION_NOTE' && blocks.length === 0;
  for (const [index] of blocks.entries()) {
    const path = `cane_blocks.${index}.cane_label`;
    const label = read(path);
    if (!hasText(label)) requireField(path, false);
    else if (labels.has(label.trim())) requireField(path, false, 'DUPLICATE_CANE_LABEL');
    else labels.add(label.trim());
  }

  const fieldIssues = new Map(issues.filter(issue => issue.field_path).map(issue => [issue.field_path, issue]));
  for (const [path, field] of values) {
    if (field.status === 'AMBIGUOUS' || field.status === 'ILLEGIBLE') {
      const reason = fieldIssues.get(path)?.code;
      questions.set(path, reason === 'OCR_VISION_DISAGREE' ? reason : `${field.status}_FIELD`);
    }
  }
  for (const issue of issues) {
    if (issue.severity !== 'ERROR' && issue.severity !== 'BLOCKER') continue;
    if (issue.field_path && values.has(issue.field_path)) {
      if (!questions.has(issue.field_path)) questions.set(issue.field_path, issue.code);
    } else documentBlocked = true;
  }
  return { questions, documentBlocked };
}
