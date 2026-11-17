CREATE OR REPLACE FUNCTION sobatnira.record_batch_nira_contribution(
  p_tenant_id uuid, p_factory_id uuid, p_user_id uuid, p_batch_id uuid,
  p_lot_id uuid, p_request_id uuid, p_quantity_ml numeric, p_occurred_at timestamptz
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE available numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(format('sobatnira:b1:%s:%s:%s', p_tenant_id, p_factory_id, p_request_id), 0));
  IF EXISTS (SELECT 1 FROM sobatnira.juice_reservations WHERE tenant_id=p_tenant_id AND factory_id=p_factory_id AND request_id=p_request_id) THEN RETURN; END IF;
  SELECT COALESCE(sum(on_hand_ml - reserved_ml), 0) INTO available FROM sobatnira.juice_balance_entries
    WHERE tenant_id=p_tenant_id AND factory_id=p_factory_id AND lot_id=p_lot_id AND is_synthetic=false;
  IF available < p_quantity_ml THEN RAISE EXCEPTION 'NIRA_STOCK_INSUFFICIENT' USING ERRCODE='23514'; END IF;
  INSERT INTO sobatnira.juice_reservations(tenant_id,factory_id,lot_id,request_id,batch_id,quantity_ml,is_synthetic,state,created_by,origin_lot_id,finalized_by,finalized_at)
    VALUES(p_tenant_id,p_factory_id,p_lot_id,p_request_id,p_batch_id,p_quantity_ml,false,'consumed',p_user_id,p_lot_id,p_user_id,clock_timestamp());
  INSERT INTO batch_nira_contributions(tenant_id,factory_id,batch_id,kloter_id,volume_ml,occurred_at)
    VALUES(p_tenant_id,p_factory_id,p_batch_id,p_lot_id,round(p_quantity_ml),p_occurred_at);
END $$;
