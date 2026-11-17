CREATE TABLE operator_contact_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id uuid NOT NULL REFERENCES operator_contacts(id),
  actor_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('created', 'updated')),
  before_data jsonb,
  after_data jsonb NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX operator_contacts_factory_idx ON operator_contacts (factory_id, display_name, id);
CREATE INDEX operator_contact_events_operator_idx ON operator_contact_events (operator_id, occurred_at DESC, id);
ALTER TABLE operator_contact_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON operator_contact_events FROM PUBLIC, anon, authenticated;
