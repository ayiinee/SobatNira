-- SELECT only. No query text, user data, connection URLs or secrets in output.
SELECT jsonb_build_object(
  'sampledAt', clock_timestamp(),
  'statsReset', (SELECT stats_reset FROM pg_stat_database WHERE datname=current_database()),
  'canReadAllStats', pg_has_role(current_user,'pg_read_all_stats','MEMBER'),
  'settings', (SELECT jsonb_object_agg(name,setting) FROM pg_settings WHERE name IN
    ('max_connections','superuser_reserved_connections','autovacuum','autovacuum_analyze_scale_factor',
     'autovacuum_vacuum_scale_factor','statement_timeout','idle_in_transaction_session_timeout')),
  'connections', (SELECT COALESCE(jsonb_agg(to_jsonb(a)),'[]'::jsonb) FROM (
    SELECT application_name,state,wait_event_type,count(*) AS connections,
      max(extract(epoch FROM clock_timestamp()-xact_start)) AS oldest_transaction_seconds
    FROM pg_stat_activity WHERE datname=current_database()
    GROUP BY application_name,state,wait_event_type) a),
  'tables', (SELECT COALESCE(jsonb_agg(to_jsonb(t)),'[]'::jsonb) FROM (
    SELECT schemaname,relname,n_live_tup,n_dead_tup,n_mod_since_analyze,seq_scan,idx_scan,
      last_analyze,last_autoanalyze,last_vacuum,last_autovacuum,
      pg_total_relation_size(relid) AS total_bytes,pg_relation_size(relid) AS table_bytes
    FROM pg_stat_user_tables WHERE schemaname IN ('sobatnira','public') ORDER BY pg_total_relation_size(relid) DESC) t),
  'indexes', (SELECT COALESCE(jsonb_agg(to_jsonb(i)),'[]'::jsonb) FROM (
    SELECT s.schemaname,s.relname,s.indexrelname,s.idx_scan,s.idx_tup_read,s.idx_tup_fetch,
      pg_relation_size(s.indexrelid) AS bytes,p.indisunique,p.indisprimary,p.indisvalid
    FROM pg_stat_user_indexes s JOIN pg_index p ON p.indexrelid=s.indexrelid
    WHERE s.schemaname IN ('sobatnira','public') ORDER BY pg_relation_size(s.indexrelid) DESC) i)
) AS diagnostics;
