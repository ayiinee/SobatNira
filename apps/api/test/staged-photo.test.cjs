const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { readFile, readdir } = require('node:fs/promises');
const { join } = require('node:path');
const test = require('node:test');
const { Pool } = require('pg');
const { Intake } = require('../dist/documents/intake');

const factoryId = '10000000-0000-4000-8000-000000000001';
const operatorId = '10000000-0000-4000-8000-000000000002';
const bytes = Buffer.from('synthetic-upload-fixture');
const event = (id = randomUUID()) => ({ provider: 'BAILEYS', provider_message_id: id,
  chat_id: 'SYNTHETIC-CHAT', sender_phone_e164: '+12025550101',
  provider_timestamp: '2026-11-16T03:30:00Z', message_type: 'IMAGE', caption: 'BARU' });

// Exercise transaction boundaries and rollback without requiring PostgreSQL locally.
function harness() {
  let state = { active: true, factoryId, uploads: [], inbound: [], assets: [], jobs: [] };
  let open = false;
  let failAttachment = false;
  const query = async (sql, args) => {
    assert.equal(open, true);
    const rows = value => ({ rows: value, rowCount: value.length });
    if (sql.includes('FROM operator_contacts')) return rows(state.active ? [{ id: operatorId, factory_id: state.factoryId }] : []);
    if (sql.includes('pg_advisory_xact_lock')) return rows([]);
    if (sql.includes('SELECT * FROM whatsapp_inbound_messages')) return rows(state.inbound.filter(row => row.messageId === args[0]));
    if (sql.includes('count(*)')) return rows([{ count: state.inbound.length }]);
    if (sql.includes('SELECT DISTINCT s.document_id')) return rows([]);
    if (sql.includes('INSERT INTO media_uploads')) {
      if (!state.uploads.some(row => row.key === args[0])) state.uploads.push({ key: args[0], attached: false });
      return rows([]);
    }
    if (sql.includes('INSERT INTO whatsapp_inbound_messages')) {
      const row = { id: randomUUID(), messageId: args[1], operator_id: args[0], fingerprint: args[3], outcome: null };
      state.inbound.push(row);
      return rows([row]);
    }
    if (sql.includes('INSERT INTO source_documents')) return rows([{ id: randomUUID() }]);
    if (sql.includes('INSERT INTO media_assets')) {
      if (failAttachment) throw new Error('synthetic database failure');
      const row = { id: randomUUID() };
      state.assets.push(row);
      return rows([row]);
    }
    if (sql.includes('UPDATE media_uploads')) {
      state.uploads.find(row => row.key === args[0]).attached = true;
      return rows([]);
    }
    if (sql.includes('INSERT INTO document_submissions')) return rows([{ id: randomUUID() }]);
    if (sql.includes('INSERT INTO document_revisions')) return rows([{ id: randomUUID(), document_id: args[0] }]);
    if (sql.includes('INSERT INTO document_jobs')) { state.jobs.push(args[0]); return rows([]); }
    if (sql.includes('UPDATE whatsapp_inbound_messages')) {
      const row = state.inbound.find(row => row.id === args[0]);
      row.outcome = JSON.parse(args[1]);
      return rows([{ outcome: row.outcome }]);
    }
    if (sql.includes('UPDATE source_documents') || sql.includes('UPDATE admin_review_tasks') || sql.includes('INSERT INTO audit_events')) return rows([]);
    throw new Error(`Unexpected fixture query: ${sql}`);
  };
  const db = { async transaction(work) {
    assert.equal(open, false);
    const before = structuredClone(state);
    open = true;
    try { return await work({ query }); }
    catch (error) { state = before; throw error; }
    finally { open = false; }
  } };
  let upload = async () => {};
  let calls = 0;
  const storage = { async put(key) {
    calls++;
    assert.equal(open, false, 'storage must not hold a database transaction');
    assert.ok(state.uploads.some(row => row.key === key && !row.attached));
    assert.equal(state.inbound.length, 0, 'upload preparation must not accept an inbound message');
    await upload();
  } };
  return { intake: new Intake(db, storage), state: () => state, calls: () => calls,
    upload: callback => { upload = callback; }, failAttachment: value => { failAttachment = value; } };
}

test('photo upload releases its transaction, attaches once and replays without another upload', async () => {
  const f = harness(), input = event();
  const first = await f.intake.photo(input, 'image/png', bytes);
  assert.equal(first.accepted, true);
  assert.equal(f.state().uploads[0].attached, true);
  const replay = await f.intake.photo(input, 'image/png', bytes);
  assert.equal(replay.duplicate, true);
  assert.equal(replay.revision_id, first.revision_id);
  assert.equal(f.calls(), 1);
  assert.equal(f.state().jobs.length, 1);
  await assert.rejects(f.intake.photo({ ...input, caption: 'changed' }, 'image/png', bytes), /IDEMPOTENCY_MISMATCH/);
  assert.equal(f.calls(), 1);
});

test('failed storage leaves a retryable manifest without accepting or queuing the photo', async () => {
  const f = harness(), input = event();
  f.upload(async () => { throw new Error('synthetic storage failure'); });
  await assert.rejects(f.intake.photo(input, 'image/png', bytes), /storage failure/);
  assert.equal(f.state().uploads.length, 1);
  assert.equal(f.state().uploads[0].attached, false);
  assert.equal(f.state().inbound.length, 0);
  assert.equal(f.state().jobs.length, 0);
  f.upload(async () => {});
  assert.equal((await f.intake.photo(input, 'image/png', bytes)).accepted, true);
  assert.equal(f.state().uploads.length, 1);
  assert.equal(f.state().jobs.length, 1);
});

test('attachment rollback keeps the manifest and retry queues only one job', async () => {
  const f = harness(), input = event();
  f.failAttachment(true);
  await assert.rejects(f.intake.photo(input, 'image/png', bytes), /database failure/);
  assert.equal(f.state().uploads[0].attached, false);
  assert.equal(f.state().inbound.length, 0);
  assert.equal(f.state().assets.length, 0);
  f.failAttachment(false);
  await f.intake.photo(input, 'image/png', bytes);
  assert.equal(f.state().jobs.length, 1);
});

test('operator revocation or factory reassignment during upload prevents attachment', async () => {
  for (const change of [state => { state.active = false; }, state => { state.factoryId = randomUUID(); }]) {
    const f = harness();
    f.upload(async () => change(f.state()));
    await assert.rejects(f.intake.photo(event(), 'image/png', bytes), error => [403, 409].includes(error.getStatus()));
    assert.equal(f.state().inbound.length, 0);
    assert.equal(f.state().assets.length, 0);
    assert.equal(f.state().uploads[0].attached, false);
  }
});

test('PostgreSQL staged upload releases operator locks and preserves concurrent retry and photo aliases',
  { skip: !process.env.TEST_DATABASE_URL, timeout: 30_000 }, async t => {
    const schema = `sobatnira_upload_${randomUUID().replaceAll('-', '')}`;
    const admin = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
    let pool;
    t.after(async () => {
      await pool?.end();
      try { await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`); }
      finally { await admin.end(); }
    });
    await admin.query(`CREATE SCHEMA ${schema}`);
    const url = new URL(process.env.TEST_DATABASE_URL);
    url.searchParams.set('options', `-c search_path=${schema}`);
    pool = new Pool({ connectionString: url.toString(), max: 4, statement_timeout: 2_000 });
    const directory = join(__dirname, '../migrations/ocr');
    for (const name of (await readdir(directory)).filter(name => /^\d+_.*\.sql$/.test(name)).sort()) {
      await pool.query(await readFile(join(directory, name), 'utf8'));
    }
    await pool.query('INSERT INTO operator_contacts(id,factory_id,display_name,phone_e164) VALUES($1,$2,$3,$4)',
      [operatorId, factoryId, 'Synthetic operator', '+12025550101']);
    const db = { async transaction(work) {
      const client = await pool.connect();
      try { await client.query('BEGIN'); const result = await work(client); await client.query('COMMIT'); return result; }
      catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    } };
    let revoke = false;
    let duringUpload = async () => {};
    const storage = { async put() {
      // This independent connection would time out if upload still held the operator lock.
      await pool.query('UPDATE operator_contacts SET active=$2 WHERE id=$1', [operatorId, !revoke]);
      await duringUpload();
    } };
    const intake = new Intake(db, storage), input = event();
    const results = await Promise.all([intake.photo(input, 'image/png', bytes), intake.photo(input, 'image/png', bytes)]);
    assert.equal(results[0].revision_id, results[1].revision_id);
    assert.equal(results.filter(result => result.duplicate).length, 1);
    const alias = await intake.photo({ ...event(), caption: null }, 'image/png', bytes);
    assert.equal(alias.duplicate, true);
    assert.equal(alias.revision_id, results[0].revision_id);
    assert.equal((await pool.query('SELECT count(*)::int AS n FROM document_jobs')).rows[0].n, 1);
    assert.equal((await pool.query('SELECT count(*)::int AS n FROM whatsapp_inbound_messages')).rows[0].n, 2);
    assert.equal((await pool.query('SELECT count(*)::int AS n FROM media_uploads WHERE attached_asset_id IS NOT NULL')).rows[0].n, 1);
    await pool.query("UPDATE source_documents SET document_type='PRODUCTION_NOTE' WHERE id=$1", [results[0].document_id]);
    await pool.query("UPDATE document_revisions SET extraction='{}',processing_status='EXTRACTED' WHERE id=$1", [results[0].revision_id]);
    duringUpload = async () => {
      await pool.query(`WITH next AS (INSERT INTO document_revisions
        (document_id,submission_id,parent_revision_id,version,processing_status,extraction)
        SELECT document_id,submission_id,id,version+1,'EXTRACTED','{}' FROM document_revisions WHERE id=$1
        RETURNING id,document_id)
        UPDATE source_documents d SET current_revision_id=next.id FROM next WHERE d.id=next.document_id`, [results[0].revision_id]);
    };
    await assert.rejects(intake.photo({ ...event(), caption: `REVISI ${results[0].document_id}` }, 'image/png', Buffer.concat([bytes, Buffer.from('-revision')])),
      error => error.getStatus() === 409 && /Revisi dokumen berubah/.test(error.message));
    duringUpload = async () => {};
    revoke = true;
    await assert.rejects(intake.photo(event(), 'image/png', bytes), error => error.getStatus() === 403);
    assert.equal((await pool.query('SELECT count(*)::int AS n FROM media_uploads WHERE attached_asset_id IS NULL')).rows[0].n, 2);
    assert.equal((await pool.query('SELECT count(*)::int AS n FROM document_jobs')).rows[0].n, 1);
  });
