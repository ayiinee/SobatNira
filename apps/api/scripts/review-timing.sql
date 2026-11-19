WITH opened AS (
  SELECT a.revision_id, a.actor_id, a.created_at AS opened_at,
    a.details->>'task_id' AS task_id,
    (a.details->>'task_created_at')::timestamptz AS task_created_at
  FROM audit_events a JOIN source_documents d ON d.id = a.document_id
  WHERE a.action = 'REVIEW_OPENED' AND d.factory_id = :'factory_id'::uuid
    AND (a.details->>'task_created_at')::timestamptz >= :'from'::timestamptz
), first_open AS (
  SELECT task_id, MIN(opened_at) AS opened_at, MIN(task_created_at) AS task_created_at
  FROM opened GROUP BY task_id
), elapsed AS (
  SELECT 'task_to_first_open' AS metric, task_id,
    EXTRACT(EPOCH FROM opened_at - task_created_at) * 1000 AS ms
  FROM first_open
  UNION ALL
  SELECT 'revision_open_to_decision', o.task_id,
    EXTRACT(EPOCH FROM decision.created_at - o.opened_at) * 1000
  FROM opened o JOIN LATERAL (
    SELECT MIN(a.created_at) AS created_at FROM audit_events a
    WHERE a.revision_id = o.revision_id AND a.actor_id = o.actor_id
      AND a.action IN ('ADMIN_VALIDATED', 'ADMIN_RETURNED') AND a.created_at >= o.opened_at
  ) decision ON decision.created_at IS NOT NULL
)
SELECT metric, COUNT(*) AS samples, COUNT(DISTINCT task_id) AS tasks,
  ROUND(MIN(ms)) AS min_ms, ROUND(MAX(ms)) AS max_ms,
  ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY ms)::numeric) AS median_ms,
  CASE WHEN COUNT(DISTINCT task_id) >= 100
    THEN ROUND(percentile_disc(0.95) WITHIN GROUP (ORDER BY ms)) END AS p95_ms
FROM elapsed GROUP BY metric ORDER BY metric;
