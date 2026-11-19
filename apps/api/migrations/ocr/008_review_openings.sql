CREATE UNIQUE INDEX audit_events_first_review_open
  ON audit_events (revision_id, actor_id)
  WHERE action = 'REVIEW_OPENED';
