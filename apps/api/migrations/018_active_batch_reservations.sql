CREATE INDEX juice_reservations_active_batch_idx
  ON sobatnira.juice_reservations (tenant_id, factory_id, batch_id, request_id)
  WHERE state <> 'released';
