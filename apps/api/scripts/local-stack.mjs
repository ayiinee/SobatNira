import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { randomUUID, randomBytes } from 'node:crypto';
import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import assert from 'node:assert/strict';
import { Pool } from 'pg';
import plugin, { createBridge } from '../integrations/openclaw/index.mjs';
import database from '../dist/documents/database.js';

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
Object.assign(process.env, { SOBATNIRA_MODE: 'local', NODE_ENV: 'development', DATABASE_URL: scoped.href,
  API_HOST: '127.0.0.1', API_PORT: String(ports.api), DOCUMENT_WORKER_ENABLED: 'true', CORS_ORIGINS: 'http://127.0.0.1:8080,http://localhost:8080',
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
  try { await initial.query(`CREATE SCHEMA IF NOT EXISTS ${schema}`); }
  finally { await initial.end(); }
  await db.migrate();
  await db.query(`INSERT INTO operator_contacts (factory_id,phone_e164,display_name,active)
    VALUES ($1,$2,'Operator Demo',true),($1,$3,'Operator Demo nonaktif',false) ON CONFLICT DO NOTHING`, [factory, phone(101), phone(102)]);
  await db.query(`INSERT INTO review_memberships (user_id,factory_id,role) VALUES ($1,$2,'ADMIN'),($3,$4,'ADMIN') ON CONFLICT DO NOTHING`,
    [admin, factory, outsider, outsideFactory]);
  authServer = createServer(async (request, response) => {
    response.setHeader('Access-Control-Allow-Origin', 'http://127.0.0.1:8080');
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
      if (request.headers.authorization === `Bearer ${userTokens['admin@example.invalid']}`) return response.end(JSON.stringify({ id: admin }));
      if (request.headers.authorization === `Bearer ${userTokens['other@example.invalid']}`) return response.end(JSON.stringify({ id: outsider }));
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
  await waitFor(async () => (await fetch(`${url(ports.api)}/health`,{ signal: AbortSignal.timeout(1_000) })).ok, 'NestJS belum aktif');
  await waitFor(async () => (await fetch(`${url(ports.ai)}/health`,{ signal: AbortSignal.timeout(1_000) })).ok, 'FastAPI belum aktif');
  const readiness = await fetch(`${url(ports.ai)}/internal/v1/ocr/ready`, { signal: AbortSignal.timeout(120_000),
    headers: { 'X-Internal-Service-Token': process.env.AI_SERVICE_INTERNAL_TOKEN } });
  if (!readiness.ok) throw new Error('PaddleOCR belum siap');
  plugin.register({ config: {}, pluginConfig: { accountId: 'local', mediaDir: staging }, logger: { warn: () => {} },
    on(name, callback) { assert.equal(name,'reply_dispatch'); handler = callback; }, registerService(value) { service = value; },
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

async function smoke() {
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
  const parse = (reply) => {
    const result = /STATUS ([a-f0-9-]{36}) ([a-f0-9-]{36})/.exec(reply);
    if (!result) throw new Error('Adapter tidak mengembalikan referensi nota');
    return { document: result[1], revision: result[2] };
  };
  const inactive = await receive(photo('truck.png', '', { SenderE164: phone(102) }));
  assert.match(inactive, /belum aktif/);
  const input = photo('truck.png', 'BARU');
  const first = parse(await receive(input));
  assert.deepEqual(parse(await receive(input)), first);
  assert.deepEqual(parse(await receive(photo('truck.png'))), first);
  const client = createBridge({ apiUrl: url(ports.api), token: process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN, mediaDir: staging });
  const ready = (target) => waitFor(async () => {
    const status = await client.status(phone(101), target.document, target.revision);
    return ['EXTRACTED','NEEDS_CLARIFICATION','MANUAL_REVIEW_REQUIRED','FAILED_FINAL'].includes(status.processing_status) && status;
  }, 'OCR belum menyelesaikan nota', 180_000);
  const truck = await ready(first);
  assert.equal(truck.extraction.header.net_weight_kg.normalized_value,1250);
  await waitFor(() => receipts.some(({ text }) => text.includes(first.revision)), 'Ringkasan WhatsApp tidak dikirim');
  assert.match(await receive(body(randomUUID(),`KONFIRMASI ${first.document} ${first.revision}`)),/masuk antrean/);
  const production = photo('production.png', 'BARU');
  const initial = parse(await receive(production));
  assert.equal((await ready(initial)).extraction.cane_blocks.length,2);
  const botReceipt = await waitFor(() => receipts.find(({ text }) => text.includes(initial.revision)),
    'Ringkasan produksi WhatsApp belum terkirim');
  const updated = parse(await receive(photo('update.png', '', { ReplyToId: botReceipt.id })));
  assert.equal(updated.document,initial.document);
  assert.notEqual(updated.revision,initial.revision);
  assert.equal((await ready(updated)).extraction.cane_blocks[0].batches[0].output.hasil_kg.normalized_value,26);
  assert.doesNotMatch(await receive(body(randomUUID(),`KONFIRMASI ${initial.document} ${initial.revision}`)),/masuk antrean/);
  const ambiguous = parse(await receive(photo('ambiguous.png', 'BARU')));
  const question = (await ready(ambiguous)).pending_question;
  assert.equal(question.field_path,'header.net_weight_kg');
  const answer = `JAWAB ${ambiguous.document} ${ambiguous.revision} ${question.id} 1250`;
  assert.match(await receive(body(randomUUID(), answer)), /OPERATOR|1250 kg/);
  assert.match(await receive(body(randomUUID(), answer)), /revisi berubah/);
  const invalid = parse(await receive(photo('unreadable.png', 'BARU')));
  const failed = await ready(invalid);
  assert.equal(failed.processing_status,'MANUAL_REVIEW_REQUIRED');
  const retake = parse(await receive(photo('truck.png', `FOTO ULANG ${invalid.document} ${invalid.revision}`)));
  assert.equal(retake.document,invalid.document);
  assert.equal((await ready(retake)).extraction.document_type,'TRUCK_ARRIVAL_NOTE');
  const manual = parse(await receive(photo('manual.png', 'BARU')));
  assert.equal((await ready(manual)).processing_status,'MANUAL_REVIEW_REQUIRED');
  const task = await db.query('SELECT id FROM admin_review_tasks WHERE revision_id=$1', [first.revision]);
  assert.equal(task.rowCount,1);
  const forbidden = await fetch(`${url(ports.api)}/api/v1/mobile/review-tasks/${task.rows[0].id}`, { headers: {
    Authorization: `Bearer ${userTokens['other@example.invalid']}`,
  } });
  assert.equal(forbidden.status,404);
  console.log(`Smoke adapter + OCR lulus. Validasi Nota Kedatangan Truk di Flutter (task ${task.rows[0].id}).`);
  await waitFor(async () => (await db.query('SELECT status FROM admin_review_tasks WHERE id=$1',[task.rows[0].id])).rows[0]?.status === 'VALIDATED',
    'Smoke menunggu validasi dari Flutter', 300_000);
  console.log('Smoke Flutter + PostgreSQL lulus. Status VALIDATED tercatat.');
}

async function stop() {
  if (stopping) return;
  stopping = true;
  await service?.stop();
  for (const process of children) if (process.exitCode === null) process.kill();
  authServer?.closeAllConnections();
  await new Promise((resolve) => authServer ? authServer.close(resolve) : resolve());
  await db.onModuleDestroy();
}

for (const signal of ['SIGINT','SIGTERM']) process.on(signal, () => { void stop().then(() => process.exit(0)); });
try { await boot(); if (process.argv.includes('--smoke')) await smoke(); }
catch (error) { console.error(error.message); await stop(); process.exitCode = 1; }
