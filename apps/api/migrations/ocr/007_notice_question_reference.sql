ALTER TABLE whatsapp_notices
  ADD COLUMN question_id uuid REFERENCES clarification_requests(id);
