ALTER TABLE clarification_requests
  ADD COLUMN status text NOT NULL DEFAULT 'CLOSED' CHECK (status IN ('OPEN', 'ANSWERED', 'CLOSED')),
  ADD COLUMN answered_at timestamptz,
  ADD COLUMN answer_message_id uuid REFERENCES whatsapp_inbound_messages,
  ADD COLUMN resolved_by uuid REFERENCES operator_contacts,
  ADD COLUMN result_revision_id uuid REFERENCES document_revisions,
  ADD CONSTRAINT clarification_answer_complete CHECK (
    (status = 'ANSWERED' AND answered_at IS NOT NULL AND answer_message_id IS NOT NULL
      AND resolved_by IS NOT NULL AND result_revision_id IS NOT NULL)
    OR (status <> 'ANSWERED' AND num_nonnulls(answered_at, answer_message_id, resolved_by, result_revision_id) = 0)
  );

-- Restore one answerable question for each uncertain field on an active draft.
WITH pending_questions AS (
  SELECT DISTINCT ON (q.revision_id, q.field_path) q.id
  FROM clarification_requests q
  JOIN document_revisions r ON r.id = q.revision_id
  JOIN source_documents d ON d.current_revision_id = r.id
  WHERE q.issue_code IN ('AMBIGUOUS_FIELD', 'ILLEGIBLE_FIELD', 'OCR_VISION_DISAGREE')
    AND r.operator_status = 'PENDING'
    AND r.extraction #>> (string_to_array(q.field_path, '.') || ARRAY['status']) IN ('AMBIGUOUS', 'ILLEGIBLE')
  ORDER BY q.revision_id, q.field_path, q.created_at, q.id
)
UPDATE clarification_requests SET status = 'OPEN' WHERE id IN (SELECT id FROM pending_questions);

CREATE UNIQUE INDEX clarification_open_field ON clarification_requests (revision_id, field_path)
  WHERE status = 'OPEN';
CREATE UNIQUE INDEX clarification_answer_message ON clarification_requests (answer_message_id)
  WHERE answer_message_id IS NOT NULL;
