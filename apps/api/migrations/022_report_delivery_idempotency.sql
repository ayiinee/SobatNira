CREATE UNIQUE INDEX report_exports_whatsapp_event_idx ON sobatnira.report_exports (idempotency_key)
  WHERE delivery_target IS NOT NULL;
