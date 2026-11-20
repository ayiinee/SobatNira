const { mkdir, writeFile } = require('node:fs/promises');
const { resolve } = require('node:path');
const { randomUUID } = require('node:crypto');
const { performance } = require('node:perf_hooks');
const { intakeFixture } = require('../test/integration/intake-fixture.cjs');
const { Review } = require('../dist/documents/review');
const { DocumentProcessor } = require('../dist/documents/processing');
const { ACTIVE_REVIEW_ACCESS_SQL } = require('../dist/documents/production-access');

// Baseline projection from commit 553beb0, with the current authorization predicate.
// Keep this only in the synthetic profiler, not as an application fallback.
const legacyReviewSql = `SELECT t.id,t.document_id,t.status,d.document_type,r.id AS revision_id,r.version,
  m.received_at,o.display_name AS sender_name,jsonb_array_length(r.issues) AS issue_count,s.media_asset_id
  FROM admin_review_tasks t JOIN source_documents d ON d.id=t.document_id
  JOIN review_memberships a ON a.factory_id=d.factory_id AND a.user_id=$1 AND a.active AND ${ACTIVE_REVIEW_ACCESS_SQL}
  JOIN document_revisions r ON r.id=t.revision_id JOIN document_submissions s ON s.id=r.submission_id
  JOIN whatsapp_inbound_messages m ON m.id=s.inbound_message_id JOIN operator_contacts o ON o.id=m.operator_id
  WHERE t.status=$2 AND ($5::uuid IS NULL OR d.factory_id=$5) AND ($6::uuid IS NULL OR t.revision_id=$6)
  ORDER BY t.created_at DESC,t.id LIMIT $3 OFFSET $4`;

async function main() {
  const url = new URL(process.env.PERF_DATABASE_URL ?? '');
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || !['localhost', '127.0.0.1'].includes(url.hostname) ||
    !/^\/sobatnira_perf_[a-z0-9_]+$/.test(url.pathname)) throw new Error('Use a disposable local sobatnira_perf_* database');
  const count = Number(process.env.PERF_QUEUE_ROWS ?? 30000);
  if (!Number.isSafeInteger(count) || count < 3000 || count > 100000) throw new Error('PERF_QUEUE_ROWS must be 3000..100000');
  process.env.DATABASE_URL = url.href; process.env.NODE_ENV = 'test';
  process.env.DOCUMENT_WORKER_ENABLED = 'false'; process.env.REPORT_EXPORT_ENABLED = 'false';
  const f = await intakeFixture();
  try {
    const db = f.client;
    const installed = await db.query("SELECT to_regclass('public.document_jobs') AS name");
    if (!installed.rows[0].name) throw new Error('Install OCR migrations on the disposable database first');
    await db.query(`CREATE TEMP TABLE perf_queue_data ON COMMIT DROP AS SELECT n,
      gen_random_uuid() AS document,gen_random_uuid() AS revision,gen_random_uuid() AS submission,
      gen_random_uuid() AS inbound,gen_random_uuid() AS asset,
      CASE WHEN n%4=0 THEN $2::uuid ELSE $1::uuid END AS factory
      FROM generate_series(1,$3) n`, [f.ids.factory, f.ids.siblingFactory, count]);
    const operator = randomUUID(), siblingOperator = randomUUID();
    await db.query("INSERT INTO operator_contacts(id,factory_id,display_name,phone_e164) VALUES($1,$2,'Synthetic profile','+12025550999'),($3,$4,'Synthetic sibling','+12025550998')", [operator, f.ids.factory, siblingOperator, f.ids.siblingFactory]);
    await db.query("INSERT INTO review_memberships(user_id,factory_id,role) VALUES($1,$2,'ADMIN'),($1,$3,'ADMIN')", [f.ids.admin, f.ids.factory, f.ids.siblingFactory]);
    await db.query(`INSERT INTO whatsapp_inbound_messages(id,operator_id,provider_message_id,event,fingerprint)
      SELECT inbound,CASE WHEN factory=$3 THEN $1::uuid ELSE $2::uuid END,inbound::text,'{}',inbound::text FROM perf_queue_data`, [operator, siblingOperator, f.ids.factory]);
    await db.query(`INSERT INTO media_assets(id,factory_id,object_key,mime_type,size_bytes,sha256)
      SELECT asset,factory,encode(sha256(convert_to(asset::text,'UTF8')),'hex'),'image/png',100,
      encode(sha256(convert_to(asset::text,'UTF8')),'hex') FROM perf_queue_data`);
    await db.query(`INSERT INTO source_documents(id,factory_id,document_type)
      SELECT document,factory,'TRUCK_ARRIVAL_NOTE' FROM perf_queue_data`);
    await db.query(`INSERT INTO document_submissions(id,document_id,inbound_message_id,media_asset_id)
      SELECT submission,document,inbound,asset FROM perf_queue_data`);
    await db.query(`INSERT INTO document_revisions(id,document_id,submission_id,version)
      SELECT revision,document,submission,1 FROM perf_queue_data`);
    await db.query(`UPDATE source_documents d SET current_revision_id=p.revision FROM perf_queue_data p WHERE d.id=p.document`);
    await db.query(`INSERT INTO document_jobs(revision_id,status,available_at,lease_until,claim_token,attempts)
      SELECT revision,CASE WHEN n%10=0 THEN 'QUEUED' WHEN n%10=1 THEN 'PROCESSING' ELSE 'COMPLETED' END,
      now()-n*interval '1 second',CASE WHEN n%10=1 THEN now()+(CASE WHEN n%20=1 THEN -1 ELSE 1 END)*interval '1 hour' END,
      CASE WHEN n%10=1 THEN gen_random_uuid() END,CASE WHEN n%10=1 THEN 1 ELSE 0 END FROM perf_queue_data`);
    await db.query(`INSERT INTO admin_review_tasks(document_id,revision_id,status,created_at)
      SELECT document,revision,CASE WHEN n%10=0 THEN 'PENDING_VALIDATION' ELSE 'VALIDATED' END,
      now()-n*interval '1 second' FROM perf_queue_data`);
    for (const table of ['source_documents','document_revisions','document_submissions','media_assets',
      'whatsapp_inbound_messages','operator_contacts','review_memberships','admin_review_tasks','document_jobs','perf_queue_data']) await db.query(`ANALYZE ${table}`);

    const captured = [];
    const capture = { query: async (sql, args) => { captured.push({ sql, args }); return { rows: [] }; } };
    const review = new Review(capture, {}, {}, {});
    await review.list(f.ids.admin, 'PENDING_VALIDATION', 1, 20, f.ids.factory);
    await review.list(f.ids.admin, 'VALIDATED', 100, 20, f.ids.factory);
    const claim = [];
    const processor = new DocumentProcessor({ transaction: async work => work({ query: async (sql, args) => { claim.push({ sql, args }); throw new Error('captured'); } }) });
    await processor.processOne().catch(() => {});
    const active = [];
    await new DocumentProcessor({ query: async (sql, args) => { active.push({ sql, args }); return { rows: [{}] }; } }).queueStatistics();
    const reads = [['review_first', captured[0]], ['review_offset_1980', captured[1]], ['claim', claim[0]], ['active_queue', active[0]]];
    const writes = [
      ['insert_500', { sql: `INSERT INTO admin_review_tasks(document_id,revision_id,status) SELECT document,revision,'VALIDATED' FROM perf_queue_data WHERE n<=500`, args: [] }],
      ['update_500', { sql: `UPDATE admin_review_tasks t SET created_at=t.created_at+interval '1 microsecond' FROM perf_queue_data p WHERE t.document_id=p.document AND p.n<=500`, args: [] }],
    ];
    const results = [];
    async function sample(phase, selectedReads = reads) {
      for (const [name, query] of [...selectedReads, ...writes]) {
        const timings = []; let plan;
        for (let n = 0; n < 5; n++) {
          await db.query('SAVEPOINT profile_operation');
          const start = performance.now(); await db.query(query.sql, query.args); timings.push(performance.now() - start);
          const explained = await db.query('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + query.sql, query.args);
          plan = explained.rows[0]['QUERY PLAN'];
          await db.query('ROLLBACK TO SAVEPOINT profile_operation'); await db.query('RELEASE SAVEPOINT profile_operation');
        }
        timings.sort((a, b) => a - b);
        results.push({ phase, name, medianMs: timings[2], timings, plan });
      }
    }
    // Verify the new query returns exactly the same rows/order, including factory scope.
    for (const [, query] of reads.filter(([name]) => name.startsWith('review'))) {
      const before = (await db.query(legacyReviewSql, query.args)).rows;
      const after = (await db.query(query.sql, query.args)).rows;
      require('node:assert/strict').deepEqual(after, before);
    }
    await sample('baseline', reads.map(([name, query]) => [name, name.startsWith('review') ? { ...query, sql: legacyReviewSql } : query]));
    await sample('paged_enrichment');
    await db.query('CREATE INDEX perf_review_status_created_idx ON admin_review_tasks(status,created_at DESC,id)');
    const size = (await db.query("SELECT pg_relation_size('perf_review_status_created_idx') AS bytes")).rows[0].bytes;
    await sample('review_index_candidate');
    const output = resolve(__dirname, '../../../.tmp/performance/queue-query-profile.json');
    await mkdir(resolve(output, '..'), { recursive: true });
    await writeFile(output, JSON.stringify({ synthetic: true, rows: count, targetFactoryFraction: 0.75,
      note: 'Five warm single-client samples with savepoint rollback; seed and candidate index rolled back. SQL captured from repositories. Not production p95.', candidateBytes: size, results }, null, 2));
    console.log(JSON.stringify({ output, rows: count, candidateBytes: size,
      results: results.map(({ phase, name, medianMs }) => ({ phase, name, medianMs })) }));
  } finally { await f.close(); }
}
main().catch(() => { console.error('Queue profiling failed; check disposable database, migrations and connectivity.'); process.exitCode = 1; });
