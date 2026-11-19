import { createServer } from 'node:http';
import { execFile, spawn } from 'node:child_process';
import { randomUUID, randomBytes } from 'node:crypto';
import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import assert from 'node:assert/strict';
import { Pool } from 'pg';
import plugin, { createBridge } from '../integrations/openclaw/index.mjs';
import database from '../dist/documents/database.js';
import migrations from '../dist/database/migrations.js';

const root = resolve(import.meta.dirname, '../../..');
const scratch = resolve(root, '.tmp/local-ai');
const staging = resolve(scratch, 'staging');
const local = new URL(process.env.LOCAL_DATABASE_URL ?? 'postgres://postgres:sobatnira-local@127.0.0.1:55437/postgres');
if (!['127.0.0.1','localhost','[::1]'].includes(local.hostname) || !['postgres:', 'postgresql:'].includes(local.protocol)) {
  throw new Error('LOCAL_DATABASE_URL harus menunjuk PostgreSQL lokal');
}
const schema = 'sobatnira_local';
const scoped = new URL(local);
scoped.searchParams.set('options', `-c search_path=${schema}`);
const factory = '10000000-0000-4000-8000-000000000001';
const admin = '10000000-0000-4000-8000-000000000002';
const outsider = '10000000-0000-4000-8000-000000000003';
const outsideFactory = '10000000-0000-4000-8000-000000000004';
const tenant = '10000000-0000-4000-8000-000000000005';
const supplier = '10000000-0000-4000-8000-000000000006';
const lotFixtures = ['A','B'].map((label) => {
  const id = randomUUID();
  return { id, label: `DEMO-${label}`, code: `OCR-${label}-${id.slice(0, 8)}` };
});
const phone = (suffix) => '+' + [1, 202, 555, String(suffix).padStart(4, '0')].join('');
const authKey = 'local-synthetic-publishable';
const passwords = { 'admin@example.invalid': 'sobatnira-demo', 'other@example.invalid': 'sobatnira-demo' };
const userTokens = Object.fromEntries(Object.keys(passwords).map((key) => [key, randomBytes(32).toString('hex')]));
const clearProviders = ['GEMINI_API_KEY','GEMINI_VISION_MODEL','OPENROUTER_API_KEY','OPENROUTER_AGENT_MODEL',
  'OPENROUTER_ALLOWED_PROVIDERS','OPENROUTER_AGENT_FALLBACK_MODEL','R2_ENDPOINT','R2_BUCKET_NAME','R2_BUCKET','R2_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID','R2_SECRET_ACCESS_KEY','DATABASE_SSL_CA_FILE','REDIS_URL','SUPABASE_SECRET_KEY','BATCH_API_BASE_URL'];
for (const key of clearProviders) process.env[key] = '';
const ports = { api: +(process.env.LOCAL_API_PORT ?? 3000), ai: +(process.env.LOCAL_AI_PORT ?? 8000), auth: +(process.env.LOCAL_AUTH_PORT ?? 8077) };
const url = (port) => `http://127.0.0.1:${port}`;
const webPort = +(process.env.LOCAL_WEB_PORT ?? 8080);
if (!Number.isInteger(webPort) || webPort < 1 || webPort > 65535) throw new Error('LOCAL_WEB_PORT tidak valid');
const webOrigin = url(webPort);
Object.assign(process.env, { SOBATNIRA_MODE: 'local', NODE_ENV: 'development', DATABASE_URL: scoped.href,
  API_HOST: '127.0.0.1', API_PORT: String(ports.api), DOCUMENT_WORKER_ENABLED: 'true',
  LOG_LEVEL: process.env.LOCAL_LOG_LEVEL ?? 'info', CORS_ORIGINS: `${webOrigin},http://localhost:${webPort}`,
  AI_BASE_URL: url(ports.ai), AI_SERVICE_BASE_URL: url(ports.ai), OCR_MEDIA_BASE_URL: url(ports.api), DOCUMENT_MEDIA_DIR: resolve(scratch,'media'),
  SUPABASE_URL: url(ports.auth), SUPABASE_PUBLISHABLE_KEY: authKey, SOBATNIRA_API_URL: url(ports.api),
  AI_SERVICE_INTERNAL_TOKEN: randomBytes(32).toString('hex'), WHATSAPP_ADAPTER_INTERNAL_TOKEN: randomBytes(32).toString('hex') });

const db = new database.Database();
const children = [];
let service;
let handler;
let authServer;
let stopping = false;
const receipts = [];

function child(binary, args, cwd) {
  const process = spawn(binary, args, { cwd, stdio: 'inherit' });
  process.on('error', () => console.error('Program lokal tidak dapat dijalankan. Periksa Node/uv dan PATH.'));
  children.push(process);
  return process;
}

function requireExit(proc, message) {
  return new Promise((resolve, reject) => proc.once('error', () => reject(new Error(message)))
    .once('exit', (code) => code === 0 ? resolve() : reject(new Error(message))));
}

async function boot() {
  await mkdir(staging, { recursive: true });
  const initial = new Pool({ connectionString: local.href, connectionTimeoutMillis: 5_000 });
  try {
    await initial.query(`CREATE SCHEMA IF NOT EXISTS ${schema};
      DO $$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
      END $$;
      CREATE SCHEMA IF NOT EXISTS auth;
      CREATE TABLE IF NOT EXISTS auth.users(id uuid PRIMARY KEY, aud text, role text, email text)`);
    const client = await initial.connect();
    try { await migrations.applyMigrations(client); }
    finally { client.release(); }
  } finally { await initial.end(); }
  await db.migrate();
  await db.transaction(async (client) => {
    await client.query(`INSERT INTO auth.users (id,aud,role,email)
      VALUES ($1,'authenticated','authenticated','admin@example.invalid') ON CONFLICT (id) DO NOTHING`, [admin]);
    await client.query("INSERT INTO sobatnira.tenants (id,name) VALUES ($1,'Tenant Demo') ON CONFLICT DO NOTHING", [tenant]);
    await client.query("INSERT INTO sobatnira.factories (id,tenant_id,name) VALUES ($1,$2,'Pabrik Demo') ON CONFLICT DO NOTHING",
      [factory, tenant]);
    await client.query('INSERT INTO sobatnira.tenant_memberships (tenant_id,user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING',
      [tenant, admin]);
    await client.query(`INSERT INTO sobatnira.factory_memberships (tenant_id,factory_id,user_id,role)
      VALUES ($1,$2,$3,'admin') ON CONFLICT DO NOTHING`, [tenant, factory, admin]);
    await client.query("INSERT INTO sobatnira.suppliers (id,tenant_id,name) VALUES ($1,$2,'PEMASOK DEMO') ON CONFLICT DO NOTHING",
      [supplier, tenant]);
    for (const lot of lotFixtures) {
      await client.query(`INSERT INTO sobatnira.lots (id,tenant_id,factory_id,supplier_id,received_at,display_code)
        VALUES ($1,$2,$3,$4,'2026-11-16T01:00:00Z',$5)`, [lot.id, tenant, factory, supplier, lot.code]);
    }
  });
  await db.query(`INSERT INTO operator_contacts (factory_id,phone_e164,display_name,active)
    VALUES ($1,$2,'Operator Demo',true),($1,$3,'Operator Demo nonaktif',false) ON CONFLICT DO NOTHING`, [factory, phone(101), phone(102)]);
  await db.query(`INSERT INTO review_memberships (user_id,factory_id,role) VALUES ($1,$2,'ADMIN'),($3,$4,'ADMIN') ON CONFLICT DO NOTHING`,
    [admin, factory, outsider, outsideFactory]);
  authServer = createServer(async (request, response) => {
    response.setHeader('Access-Control-Allow-Origin', webOrigin);
    response.setHeader('Access-Control-Allow-Headers', 'apikey,content-type');
    response.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    response.setHeader('Content-Type','application/json');
    if (request.method === 'OPTIONS') return response.writeHead(204).end();
    if (request.headers.apikey !== authKey) return response.writeHead(401).end('{}');
    if (request.url === '/auth/v1/settings') return response.end('{}');
    if (request.method === 'POST' && request.url === '/auth/v1/token?grant_type=password') {
      try {
        const parts = [];
        for await (const chunk of request) parts.push(chunk);
        const { email, password } = JSON.parse(Buffer.concat(parts));
        if (Object.hasOwn(passwords, email) && passwords[email] === password) return response.end(JSON.stringify({ access_token: userTokens[email] }));
      } catch { return response.writeHead(400).end('{}'); }
    }
    if (request.url === '/auth/v1/user') {
      if (request.headers.authorization === `Bearer ${userTokens['admin@example.invalid']}`) return response.end(JSON.stringify({ id: admin, aud: 'authenticated' }));
      if (request.headers.authorization === `Bearer ${userTokens['other@example.invalid']}`) return response.end(JSON.stringify({ id: outsider, aud: 'authenticated' }));
    }
    response.writeHead(401).end('{}');
  });
  await new Promise((resolve, reject) => authServer.once('error', reject).listen(ports.auth,'127.0.0.1',resolve));
  const uv = process.env.UV_BIN ?? 'uv';
  const ai = resolve(root, 'apps/ai');
  const api = resolve(root, 'apps/api');
  await requireExit(child(uv, ['run','--locked','--extra','paddle','python','synthetic_notes.py',staging], ai), 'Pembuatan fixture gagal');
  child(process.execPath, ['dist/main.js'], api);
  child(uv, ['run','--locked','--extra','paddle','uvicorn','main:app','--host','127.0.0.1','--port',String(ports.ai)], ai);
  await waitFor(async () => (await fetch(`${url(ports.api)}/internal/v1/whatsapp/ready`, { signal: AbortSignal.timeout(1_000),
    headers: { 'X-Internal-Service-Token': process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN },
  })).ok, 'NestJS intake belum siap. Periksa worker, token adapter, dan migration OCR.');
  await waitFor(async () => (await fetch(`${url(ports.ai)}/health`,{ signal: AbortSignal.timeout(1_000) })).ok, 'FastAPI belum aktif');
  const readiness = await fetch(`${url(ports.ai)}/internal/v1/ocr/ready`, { signal: AbortSignal.timeout(120_000),
    headers: { 'X-Internal-Service-Token': process.env.AI_SERVICE_INTERNAL_TOKEN } });
  if (!readiness.ok) throw new Error('PaddleOCR belum siap');
  plugin.register({ config: {}, pluginConfig: { accountId: 'local', mediaDir: staging }, logger: { warn: () => {}, info: console.log },
    on(name, callback) { if (name === 'reply_dispatch') handler = callback; }, registerService(value) { service = value; },
    runtime: { channel: { outbound: { async loadAdapter(channel) {
      assert.equal(channel,'whatsapp');
      return { async sendText(args) {
        assert.equal(args.accountId,'local');
        const receipt = { id: randomUUID(), text: args.text };
        receipts.push(receipt);
        return { messageId: receipt.id };
      } };
    } } } } });
  service.start();
  console.log(`Mode local aktif. API ${url(ports.api)} | Auth sintetis ${url(ports.auth)}`);
}

async function waitFor(check, message, timeout = 35_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    try { const result = await check(); if (result) return result; } catch { /* next poll */ }
    await delay(600);
  }
  throw new Error(message);
}

async function smoke(ocrOnly = false) {
  const body = (id, text, meta = {}) => ({ MessageSid: id, BodyForCommands: text, Timestamp: Date.now(), SenderE164: phone(101), ...meta });
  const receive = async (ctx) => {
    let reply;
    const result = await handler({ ctx, originatingChannel: 'whatsapp', originatingAccountId: 'local',
      originatingChatType: 'direct', sendPolicy: 'allow' }, {
      dispatcher: { sendFinalReply: ({ text }) => { reply = text; return true; }, getQueuedCounts: () => ({ final: 1, block: 0, tool: 0 }) },
      recordProcessed() {},
    });
    assert.equal(result.handled, true);
    return reply;
  };
  const photo = (file, caption = '', meta = {}) => body(randomUUID(), caption, { media: [{ path: resolve(staging, file), contentType: 'image/png' }], ...meta });
  const submitPhoto = async (event) => {
    assert.match(await receive(event), /Foto diterima\. Sedang membaca nota|sudah tercatat/);
    const { rows: [message] } = await db.query('SELECT outcome FROM whatsapp_inbound_messages WHERE provider_message_id=$1', [event.MessageSid]);
    return { document: message.outcome.document_id, revision: message.outcome.revision_id };
  };
  const receiptFor = (target) => waitFor(async () => {
    const { rows: [notice] } = await db.query("SELECT provider_message_id FROM whatsapp_notices WHERE revision_id=$1 AND status='SENT'", [target.revision]);
    return notice && receipts.find(({ id }) => id === notice.provider_message_id);
  }, 'Ringkasan WhatsApp belum dikirim');
  const inactive = await receive(photo('truck.png', '', { SenderE164: phone(102) }));
  assert.match(inactive, /belum aktif/);
  const input = photo('truck.png', 'BARU');
  const first = await submitPhoto(input);
  assert.deepEqual(await submitPhoto(input), first);
  assert.deepEqual(await submitPhoto(photo('truck.png')), first);
  const client = createBridge({ apiUrl: url(ports.api), token: process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN, mediaDir: staging });
  const ready = (target) => waitFor(async () => {
    const status = await client.status(phone(101), target.document, target.revision);
    return ['EXTRACTED','NEEDS_CLARIFICATION','MANUAL_REVIEW_REQUIRED','FAILED_FINAL'].includes(status.processing_status) && status;
  }, 'OCR belum menyelesaikan nota', 750_000);
  const truck = await ready(first);
  assert.equal(truck.extraction.header.net_weight_kg.normalized_value,1250);
  assert.equal(truck.can_confirm, true);
  assert.match(await receive(body(randomUUID(),'STATUS')), /Nota Kedatangan Truk/);
  const truckReceipt = await receiptFor(first);
  assert.match(await receive(body(randomUUID(),'KONFIRMASI', { ReplyToId: truckReceipt.id })),/masuk antrean/);
  const production = photo('production.png', 'BARU');
  const initial = await submitPhoto(production);
  assert.equal((await ready(initial)).extraction.cane_blocks.length,2);
  const botReceipt = await receiptFor(initial);
  const updated = await submitPhoto(photo('update.png', '', { ReplyToId: botReceipt.id }));
  assert.equal(updated.document,initial.document);
  assert.notEqual(updated.revision,initial.revision);
  const updatedDraft = await ready(updated);
  assert.ok(updatedDraft.extraction, `OCR foto lanjutan berakhir dengan status ${updatedDraft.processing_status}`);
  assert.equal(updatedDraft.extraction.cane_blocks[0].batches[0].output.hasil_kg.normalized_value,26);
  const updatedReceipt = await receiptFor(updated);
  assert.match(updatedReceipt.text, /Perubahan pada revisi ini/);
  assert.doesNotMatch(await receive(body(randomUUID(),`KONFIRMASI ${initial.document} ${initial.revision}`)),/masuk antrean/);
  assert.match(await receive(body(randomUUID(),'KONFIRMASI', { ReplyToId: updatedReceipt.id })),/masuk antrean/);
  const repeatedTruck = photo('truck.png');
  assert.deepEqual(await submitPhoto(repeatedTruck), first);
  assert.match(await receive(body(randomUUID(),'STATUS', { ReplyToId: repeatedTruck.MessageSid })), /Nota Kedatangan Truk/);
  const ambiguous = await submitPhoto(photo('ambiguous.png', 'BARU'));
  const ambiguousDraft = await ready(ambiguous);
  const question = ambiguousDraft.pending_question;
  assert.ok(question, `Nota ambigu tidak menghasilkan pertanyaan (${ambiguousDraft.processing_status})`);
  assert.equal(question.field_path,'header.net_weight_kg');
  const ambiguousReceipt = await receiptFor(ambiguous);
  assert.match(ambiguousReceipt.text, /Perlu dicek/);
  assert.doesNotMatch(ambiguousReceipt.text, /KONFIRMASI/);
  assert.match(await receive(body(randomUUID(),'KONFIRMASI', { ReplyToId: ambiguousReceipt.id })), /data yang perlu diperiksa/);
  assert.match(await receive(body(randomUUID(),'JAWAB 1.250', { ReplyToId: ambiguousReceipt.id })), /tanpa pemisah ribuan/);
  assert.match(await receive(body(randomUUID(),'JAWAB 1250', { ReplyToId: ambiguousReceipt.id })), /Jawaban tersimpan/);
  assert.match(await receive(body(randomUUID(),'JAWAB 1250', { ReplyToId: ambiguousReceipt.id })), /ringkasan otomatis yang terbaru/);
  const invalid = await submitPhoto(photo('unreadable.png', 'BARU'));
  const failed = await ready(invalid);
  assert.equal(failed.processing_status,'MANUAL_REVIEW_REQUIRED');
  const invalidReceipt = await receiptFor(invalid);
  const retake = await submitPhoto(photo('truck.png', 'FOTO ULANG', { ReplyToId: invalidReceipt.id }));
  assert.equal(retake.document,invalid.document);
  assert.equal((await ready(retake)).extraction.document_type,'TRUCK_ARRIVAL_NOTE');
  const manual = await submitPhoto(photo('manual.png', 'BARU'));
  assert.equal((await ready(manual)).processing_status,'MANUAL_REVIEW_REQUIRED');
  const taskFor = async ({ revision }) => {
    const { rows } = await db.query('SELECT id FROM admin_review_tasks WHERE revision_id=$1', [revision]);
    assert.equal(rows.length, 1);
    return rows[0].id;
  };
  const [truckTask, manualTask, productionTask] = await Promise.all([first, manual, updated].map(taskFor));
  const forbidden = await fetch(`${url(ports.api)}/api/v1/mobile/review-tasks/${truckTask}`, { headers: {
    Authorization: `Bearer ${userTokens['other@example.invalid']}`,
  } });
  assert.equal(forbidden.status,404);
  if (ocrOnly) {
    console.log('Smoke adapter WhatsApp dan PaddleOCR lulus sampai antrean Pekerjaan.');
    return;
  }
  const [lotA, lotB] = lotFixtures;
  console.log('Smoke adapter + OCR lulus. Selesaikan tiga tugas di Flutter.');
  console.log(`1. Nota Kedatangan Truk ${truckTask} → ${lotA.code}`);
  console.log(`2. Draf manual ${manualTask} → ${lotB.code}`);
  console.log(`3. Nota Produksi ${productionTask} → ${lotA.label} : ${lotA.code} : 90 L, ${lotB.label} : ${lotB.code} : 85 L`);
  const approved = async (tasks, timeout) => waitFor(async () =>
    (await db.query("SELECT count(*)::int AS count FROM admin_review_tasks WHERE id=ANY($1::uuid[]) AND status='VALIDATED'",
      [tasks])).rows[0].count === tasks.length, 'Smoke menunggu validasi dari Flutter', timeout);
  await approved([truckTask, manualTask], 600_000);
  const { rows: intake } = await db.query(`SELECT i.lot_id,i.ocr_revision_id,s.quantity_delta_kg::text AS weight
    FROM sobatnira.intake_records i JOIN sobatnira.sugarcane_stock_movements s ON s.intake_record_id=i.id
    WHERE i.ocr_document_id=ANY($1::uuid[]) ORDER BY i.ocr_document_id`, [[first.document, manual.document]]);
  assert.equal(intake.length, 2);
  assert.deepEqual(intake.find((row) => row.ocr_revision_id === first.revision), { lot_id: lotA.id, ocr_revision_id: first.revision, weight: '1250' });
  assert.equal(intake.find((row) => row.lot_id === lotB.id)?.weight, '1250');
  console.log('Kedua penerimaan sah dan masing-masing mencatat 1250 kg tebu.');
  await approved([productionTask], 600_000);
  const { rows: milling } = await db.query(`SELECT m.ocr_cane_label AS label,m.lot_id,m.ocr_revision_id,
      s.quantity_delta_kg::text AS cane,j.quantity_delta_liters::text AS juice
    FROM sobatnira.milling_records m
    JOIN sobatnira.sugarcane_stock_movements s ON s.milling_record_id=m.id
    JOIN sobatnira.juice_stock_movements j ON j.milling_record_id=m.id
    WHERE m.ocr_document_id=$1 ORDER BY m.ocr_cane_label`, [updated.document]);
  assert.deepEqual(milling, [lotA, lotB].map((lot, index) => ({
    label: lot.label, lot_id: lot.id, ocr_revision_id: updated.revision, cane: '-1250', juice: index === 0 ? '90' : '85',
  })));
  for (const [lot, source] of [[lotA, first], [lotB, manual]]) {
    const response = await fetch(`${url(ports.api)}/tenants/${tenant}/factories/${factory}/lots/${lot.id}`, {
      headers: { Authorization: `Bearer ${userTokens['admin@example.invalid']}` }, signal: AbortSignal.timeout(5_000),
    });
    assert.equal(response.status, 200);
    const detail = await response.json();
    const receipt = intake.find((row) => row.lot_id === lot.id);
    assert.equal(detail.netWeightGrams, '1250000');
    assert.deepEqual(detail.intake.document, {
      source: 'ocr', documentId: source.document, revisionId: receipt.ocr_revision_id, revisionNumber: null,
    });
    assert.deepEqual(detail.milling.document, {
      source: 'ocr', documentId: updated.document, revisionId: updated.revision, revisionNumber: null,
    });
  }
  const summaries = await fetch(`${url(ports.api)}/tenants/${tenant}/factories/${factory}/lots?includeSummary=true&limit=100&q=${lotA.code.slice(4)}`, {
    headers: { Authorization: `Bearer ${userTokens['admin@example.invalid']}` }, signal: AbortSignal.timeout(5_000),
  });
  assert.equal(summaries.status, 200);
  const summary = (await summaries.json()).items.find((item) => item.id === lotA.id);
  assert.equal(summary.netWeightGrams, '1250000');
  assert.equal(summary.juiceProducedLiters, '90');
  const factoryRoot = `${url(ports.api)}/tenants/${tenant}/factories/${factory}`;
  const scopedRequest = async (path, method = 'GET', body, token = userTokens['admin@example.invalid']) => {
    const response = await fetch(factoryRoot + path, { method, headers: { Authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(5_000) });
    return { status: response.status, data: await response.json() };
  };
  const code = `SMOKE-${lotA.id.slice(0, 8)}`;
  console.log(`Nota sah. Pada detail ${lotA.code}, buat batch ${code}, wajan 1, masak setelah penggilingan, 40000 mL, hasil fisik 26 kg, grade A 25 kg, Rp20000/kg.`);
  console.log('Isi biaya Rp100000, Rp20000, Rp5000, Rp0. Reservasi nira lalu sahkan batch.');
  const batch = await waitFor(async () => (await db.query(`SELECT id, quantity_ml::text AS volume
      FROM sobatnira.production_batches WHERE lot_id=$1 AND code=$2 AND status='approved'`, [lotA.id, code])).rows[0],
    'Smoke menunggu pengesahan batch dari Flutter', 600_000);
  assert.equal(batch.volume, '40000');
  const reservation = (await db.query(`SELECT request_id, origin_lot_id, quantity_ml::text AS volume
      FROM sobatnira.juice_reservations WHERE batch_id=$1 AND state='consumed'`, [batch.id])).rows;
  assert.deepEqual(reservation, [{ request_id: batch.id, origin_lot_id: lotA.id, volume: '40000' }]);
  const approvePath = `/production/batches/${batch.id}/approve`;
  const snapshot = await scopedRequest(approvePath, 'POST');
  assert.equal(snapshot.status, 200);
  assert.equal(snapshot.data.output_snapshot.productionMarginRupiah, '375000');
  assert.equal((await scopedRequest(approvePath, 'POST')).data.id, snapshot.data.id);
  assert.equal((await scopedRequest(approvePath, 'POST', undefined, userTokens['other@example.invalid'])).status, 403);
  assert.equal((await scopedRequest(`/lots/${lotA.id}/juice/availability`)).data.onHandMl, '50000');
  const recap = await scopedRequest('/production/recap');
  const profit = await scopedRequest('/production/profit-report');
  assert.equal(recap.status, 200);
  const lotReport = recap.data.items.find((item) => item.lotId === lotA.id);
  assert.equal(lotReport.snapshotId, snapshot.data.id);
  assert.equal(lotReport.batches[0].id, batch.id);
  assert.equal(lotReport.calculation.finalSugarKg, '25');
  assert.equal(profit.data.items.find((item) => item.lotId === lotA.id).snapshotId, snapshot.data.id);
  console.log('Smoke Flutter dan PostgreSQL lulus. Batch, stok, pengiriman ulang, dan snapshot laporan cocok.');
}

async function stop() {
  if (stopping) return;
  stopping = true;
  await service?.stop();
  await Promise.all(children.filter((p) => p.pid && p.exitCode === null).map((p) => {
    if (process.platform === 'win32') {
      return new Promise((resolve) => execFile('taskkill.exe', ['/pid', String(p.pid), '/t', '/f'],
        { windowsHide: true }, resolve));
    }
    p.kill();
  }));
  authServer?.closeAllConnections();
  await new Promise((resolve) => authServer ? authServer.close(resolve) : resolve());
  await db.onModuleDestroy();
}

for (const signal of ['SIGINT','SIGTERM']) process.on(signal, () => { void stop().then(() => process.exit(0)); });
try {
  const ocrOnly = process.argv.includes('--ocr-smoke');
  await boot();
  if (ocrOnly || process.argv.includes('--smoke')) await smoke(ocrOnly);
  if (ocrOnly) await stop();
}
catch (error) { console.error(error.message); await stop(); process.exitCode = 1; }
