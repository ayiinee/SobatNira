const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { Logger } = require('@nestjs/common');
const { once } = require('node:events');
const { mkdtemp, readFile, rm, writeFile } = require('node:fs/promises');
const { createServer } = require('node:http');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const test = require('node:test');
const { Pool } = require('pg');
const { createApplication } = require('../dist/application.js');
const { Database } = require('../dist/documents/database.js');
const { assertBusinessMigrationsApplied } = require('../dist/database/migrations.js');
const { DocumentProcessor } = require('../dist/documents/processing.js');
const { mergeProduction } = require('../dist/documents/revisions.js');
const { intakeFixture } = require('./integration/intake-fixture.cjs');

const fixture = (name) => readFile(join(__dirname, '../../../docs/ai/examples', `${name}.example.json`), 'utf8').then(JSON.parse);
const phone = (suffix) => '+' + [1, 202, 555, String(suffix).padStart(4, '0')].join('');
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAADklEQVQImWP4DwYMEAoAU7oL9W/sIDEAAAAASUVORK5CYII=', 'base64');
const imageFor = (id) => Buffer.concat([png, Buffer.from(id)]);
const tokenHeaders = { 'X-Internal-Service-Token': 'synthetic-adapter-test' };

test('combined application routes OCR requests through their service and review authentication', async (t) => {
  const adapterToken = process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN;
  process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN = tokenHeaders['X-Internal-Service-Token'];
  t.after(() => {
    if (adapterToken === undefined) delete process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN;
    else process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN = adapterToken;
  });
  const app = await createApplication({ envFile: false, env: { LOG_LEVEL: 'silent' } });
  t.after(() => app.close());
  await app.listen(0, '127.0.0.1');
  const base = await app.getUrl();
  const inbound = base + '/internal/v1/whatsapp/inbound';
  assert.equal((await fetch(inbound, { method: 'POST' })).status, 401);
  assert.equal((await fetch(inbound, { method: 'POST', headers: tokenHeaders })).status, 400);
  assert.equal((await fetch(base + '/api/v1/mobile/review-tasks')).status, 401);
  assert.equal((await fetch(base + '/auth/me')).status, 401);
});

function event(messageId, kind = 'IMAGE', from = phone(101), quoted = null, caption = null) {
  return { provider: 'BAILEYS', provider_message_id: messageId, chat_id: 'SYNTHETIC-CHAT', sender_phone_e164: from,
    provider_timestamp: '2026-11-16T03:30:00Z', message_type: kind, quoted_message_id: quoted, caption };
}

function form(metadata, image = png) {
  const body = new FormData();
  body.append('event', JSON.stringify(metadata));
  body.append('media', new Blob([image], { type: 'image/png' }), 'synthetic.png');
  return body;
}

test('operator management scopes contacts and gates new WhatsApp photos', {
  skip: !process.env.TEST_DATABASE_URL, timeout: 30_000,
}, async () => {
  const schema = 'sobatnira_operator_test_' + randomUUID().replaceAll('-', '');
  const admin = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
  const connection = new URL(process.env.TEST_DATABASE_URL);
  connection.searchParams.set('options', '-c search_path=' + schema);
  const folder = await mkdtemp(join(tmpdir(), 'sobatnira-operator-media-'));
  const env = {
    DATABASE_URL: connection.toString(),
    DOCUMENT_WORKER_ENABLED: 'false',
    DOCUMENT_MEDIA_DIR: folder,
    WHATSAPP_ADAPTER_INTERNAL_TOKEN: tokenHeaders['X-Internal-Service-Token'],
    SOBATNIRA_MODE: 'legacy',
    R2_ENDPOINT: '', R2_ACCOUNT_ID: '', R2_ACCESS_KEY_ID: '', R2_SECRET_ACCESS_KEY: '',
  };
  const prior = Object.fromEntries(Object.keys(env).map((name) => [name, process.env[name]]));
  let f;
  try {
    await admin.query('CREATE SCHEMA ' + schema);
    Object.assign(process.env, env);
    f = await intakeFixture(true);
    await f.app.get(Database).migrate();

    const path = f.root + '/operators';
    assert.equal((await f.request(path, 'GET', undefined, null)).status, 401);
    assert.equal((await f.request(f.siblingRoot + '/operators', 'GET', undefined, 'fixture-owner')).status, 403);
    assert.equal((await f.request(path, 'POST', { displayName: 'Synthetic operator', phoneE164: '081234567890' })).status, 400);

    const input = { displayName: 'Synthetic operator', phoneE164: phone(742) };
    const created = await f.request(path, 'POST', input, 'fixture-owner');
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const { id } = created.body;
    assert.deepEqual(created.body, { id, factoryId: f.ids.factory, ...input, isActive: true });
    const contactPath = path + '/' + id;
    const list = await f.request(path + '?q=OPERATOR&isActive=true&limit=1');
    assert.equal(list.status, 200);
    assert.deepEqual(list.body, { items: [created.body], total: 1, limit: 1, offset: 0 });
    const otherPath = f.otherRoot + '/operators';
    assert.deepEqual((await f.request(otherPath)).body.items, []);
    assert.equal((await f.request(otherPath + '/' + id + '/history')).status, 404);
    assert.equal((await f.request(f.siblingRoot + '/operators/' + id, 'PATCH', { isActive: false })).status, 404);
    assert.equal((await f.request(otherPath, 'POST', input)).status, 409);
    assert.equal((await f.request(contactPath, 'PATCH', { phoneE164: phone(743) })).status, 400);

    const photo = (messageId) => fetch(f.base + '/internal/v1/whatsapp/inbound', {
      method: 'POST',
      body: form(event(messageId, 'IMAGE', input.phoneE164), imageFor(messageId)),
      headers: { ...tokenHeaders, 'Idempotency-Key': 'baileys:' + messageId },
    });
    const accepted = await photo('synthetic-active-operator');
    assert.equal(accepted.status, 202, await accepted.text());
    const updated = await f.request(contactPath, 'PATCH', { displayName: 'Renamed operator', isActive: false });
    assert.equal(updated.status, 200, JSON.stringify(updated.body));
    assert.equal(updated.body.isActive, false);
    assert.equal((await f.request(path + '?isActive=true')).body.total, 0);
    assert.deepEqual((await f.request(path + '?isActive=false')).body.items, [updated.body]);
    const blocked = await photo('synthetic-deactivated-operator');
    assert.equal(blocked.status, 403);
    assert.equal((await blocked.json()).message, 'OPERATOR_NOT_ACTIVE');

    assert.equal((await f.request(contactPath, 'PATCH', { isActive: false })).status, 200);
    const history = await f.request(contactPath + '/history');
    assert.equal(history.status, 200);
    assert.deepEqual(history.body.items.map(({ action, actorId, before, after }) => ({ action, actorId, before, after })), [
      { action: 'updated', actorId: f.ids.admin, before: { displayName: input.displayName, isActive: true },
        after: { displayName: 'Renamed operator', isActive: false } },
      { action: 'created', actorId: f.ids.owner, before: null, after: { displayName: input.displayName, isActive: true } },
    ]);

    assert.equal((await f.request(contactPath, 'PATCH', { isActive: true }, 'fixture-owner')).status, 200);
    const reactivated = await photo('synthetic-reactivated-operator');
    assert.equal(reactivated.status, 202, await reactivated.text());
  } finally {
    try {
      await f?.close();
    } finally {
      for (const [name, value] of Object.entries(prior)) {
        if (value === undefined) delete process.env[name];
        else process.env[name] = value;
      }
      try { await admin.query('DROP SCHEMA IF EXISTS ' + schema + ' CASCADE'); }
      finally { await admin.end(); await rm(folder, { recursive: true, force: true }); }
    }
  }
});

test('progressive merge preserves evidence and distinct runs with reused wajan', async () => {
  const { summary } = await import('../integrations/openclaw/operator-copy.mjs');
  const original = await fixture('production-note-progressive-update');
  const block = original.cane_blocks[0];
  block.cane_label.normalized_value = 'SYNTHETIC-A';
  const initialRow = block.batches[0];
  initialRow.cooking.isi_kg.evidence = [{ asset_id: 'prior', coordinate_space: 'ORIGINAL_IMAGE_NORMALIZED', bbox: [0, 0, 1, 1] }];
  const incoming = structuredClone(original);
  const batch = incoming.cane_blocks[0].batches[0];
  Object.assign(batch.cooking.isi_kg, { raw_value: null, normalized_value: null, status: 'NOT_PRESENT', evidence: [] });
  Object.assign(batch.output.hasil_kg, { raw_value: '25', normalized_value: 25, status: 'READ' });
  const repeatedPan = structuredClone(batch);
  repeatedPan.cooking.jam_turun.normalized_value = '16:35';
  incoming.cane_blocks[0].batches.push(repeatedPan);
  const { note, issues } = mergeProduction(original, incoming);
  const [first, second] = note.cane_blocks[0].batches;
  assert.equal(first.cooking.isi_kg.normalized_value, 115);
  assert.equal(first.cooking.isi_kg.evidence[0].asset_id, 'prior');
  assert.equal(first.output.hasil_kg.normalized_value, 25);
  assert.equal(first.pan_number.normalized_value, second.pan_number.normalized_value);
  assert.notEqual(first.row_reference, second.row_reference);
  assert.deepEqual(issues.map(({ code, field_path }) => [code, field_path]), [
    ['REVISION_FIELD_ADDED', 'cane_blocks.0.batches.0.output.hasil_kg'],
    ['REVISION_FIELD_ADDED', 'cane_blocks.0.batches.1.pan_number'],
  ]);
  const review = summary({ extraction: note, processing_status: 'NEEDS_CLARIFICATION', can_confirm: false,
    pending_question: { field_path: 'cane_blocks.0.batches.1.output.hasil_kg', candidates: [25, 26] },
    changed_fields: ['cane_blocks.0.batches.0.output.hasil_kg'] });
  assert.match(review, /Blok SYNTHETIC-A · Wajan .* · Berat hasil/);
  assert.match(review, /Perubahan pada revisi ini/);
  assert.ok(review.indexOf('*JAWAB*') < review.indexOf('Perubahan pada revisi ini'));
  assert.match(review, /Belum dicatat/);
  assert.doesNotMatch(review, /KONFIRMASI/);
  assert.match(summary({ processing_status: 'QUEUED' }), /menunggu giliran baca/);
  assert.match(summary({ processing_status: 'PROCESSING' }), /sedang dibaca/);
  const lengthy = structuredClone(note);
  lengthy.cane_blocks[0].batches = Array(7).fill(first);
  const ready = { extraction: lengthy, processing_status: 'EXTRACTED', can_confirm: true };
  assert.match(summary(ready), /STATUS 2/);
  assert.match(summary(ready, 2, { fromStatus: true }), /ringkasan otomatis nota ini dengan \*KONFIRMASI\*/);
  incoming.cane_blocks[0].batches.push(structuredClone(repeatedPan));
  assert.equal(mergeProduction(original, incoming).issues[0].code, 'ROW_MATCH_REQUIRED');
});

test('OpenClaw bridge rejects multiple attachments and formats revision-bound commands', async () => {
  const { createBridge } = await import('../integrations/openclaw/index.mjs');
  const ids = [randomUUID(), randomUUID()];
  let calls = 0;
  const bridge = createBridge({ apiUrl: 'http://127.0.0.1', token: 'synthetic', mediaDir: tmpdir(),
    request(url, options) {
      calls++;
      assert.equal(options.headers['Idempotency-Key'], 'baileys:provider-msg');
      const body = JSON.parse(options.body);
      assert.equal(body.action.revision_id, ids[1]);
      assert.equal(body.event.sender_phone_e164, phone(101));
      return Response.json({ operator_status: 'CONFIRMED' });
    } });
  const metadata = { senderId: phone(101), conversationId: 'SYNTHETIC', messageId: 'provider-msg', timestamp: 1794799800000 };
  assert.match((await bridge.handle({ ...metadata, media: [{}, {}] }, {})).text, /tepat satu/);
  assert.equal(calls, 0);
  assert.match((await bridge.handle({ ...metadata, body: `KONFIRMASI ${ids.join(' ')}` }, {})).text, /masuk antrean/);
  assert.equal(calls, 1);
});

test('OpenClaw reply dispatch uses the WhatsApp context and owns only the configured account', async (t) => {
  const { default: plugin } = await import('../integrations/openclaw/index.mjs');
  t.mock.method(globalThis, 'fetch', (url, options) => {
    assert.equal(url.pathname, '/internal/v1/whatsapp/text-events');
    const { event } = JSON.parse(options.body);
    assert.equal(event.provider_message_id, 'provider-message');
    assert.equal(event.quoted_message_id, 'provider-quote');
    assert.equal(event.chat_id, phone(101));
    assert.equal(event.sender_phone_e164, phone(101));
    return Response.json({ operator_status: 'CONFIRMED' });
  });
  const names = ['SOBATNIRA_API_URL', 'WHATSAPP_ADAPTER_INTERNAL_TOKEN', 'SOBATNIRA_MODE'];
  const before = names.map((key) => process.env[key]);
  t.after(() => names.forEach((key, index) => {
    if (before[index] === undefined) delete process.env[key];
    else process.env[key] = before[index];
  }));
  Object.assign(process.env, { SOBATNIRA_API_URL: 'http://127.0.0.1', WHATSAPP_ADAPTER_INTERNAL_TOKEN: 'x'.repeat(32), SOBATNIRA_MODE: 'local' });
  let dispatch;
  const hooks = new Map();
  const adapter = { config: {}, pluginConfig: { accountId: 'work', mediaDir: tmpdir() }, logger: { warn() {} },
    registerService(service) { assert.equal(service.id, 'sobatnira-notices'); },
    on(name, callback, opts) {
      hooks.set(name, callback);
      if (name === 'reply_dispatch') {
        assert.deepEqual(opts.eligibleDispatchKinds, ['agent', 'acp']);
        dispatch = callback;
      }
    },
    runtime: { channel: { outbound: { loadAdapter() {} } } },
  };
  process.env.SOBATNIRA_API_URL = 'http://gateway.example.invalid';
  assert.throws(() => plugin.register(adapter), /SOBATNIRA_API_URL/);
  process.env.SOBATNIRA_API_URL = 'http://127.0.0.1';
  plugin.register(adapter);
  const target = { ctx: { MessageSid: 'provider-message', Timestamp: Date.now(), SenderE164: phone(101),
    SenderId: '123@lid', ReplyToId: 'provider-quote', BodyForCommands: `KONFIRMASI ${randomUUID()} ${randomUUID()}` },
    originatingChannel: 'whatsapp', originatingChatType: 'direct', sendPolicy: 'allow' };
  const sent = [];
  const context = { recordProcessed() {}, dispatcher: {
    sendFinalReply({ text }) { sent.push(text); return true; },
    getQueuedCounts: () => ({ final: sent.length, block: 0, tool: 0 }),
  } };
  assert.equal(await dispatch({ ...target, originatingAccountId: 'other' }, context), undefined);
  assert.equal((await dispatch({ ...target, originatingAccountId: 'work', originatingChatType: 'group' }, context)).queuedFinal, false);
  assert.equal((await dispatch({ ...target, originatingAccountId: 'work' }, context)).queuedFinal, true);
  assert.match(sent[0], /masuk antrean/);
  assert.equal(fetch.mock.callCount(), 1);
  assert.equal(hooks.get('before_agent_run')({ channelId: 'whatsapp', accountId: 'work' }, {}).outcome, 'block');
  assert.equal(hooks.get('before_agent_run')({ channelId: 'whatsapp', accountId: 'other' }, {}), undefined);
  const failure = { payload: { text: "Couldn't sign in to the AI service." }, channel: 'whatsapp' };
  assert.match(hooks.get('reply_payload_sending')(failure, { accountId: 'work' }).payload.text, /STATUS/);
  assert.equal(hooks.get('reply_payload_sending')(failure, { accountId: 'other' }), undefined);
});

test('short WhatsApp commands keep status readable and bind writes to a quoted revision', async () => {
  const { createBridge } = await import('../integrations/openclaw/index.mjs');
  const [document_id, revision_id, question_id] = Array.from({ length: 3 }, () => randomUUID());
  const calls = [];
  const bridge = createBridge({ apiUrl: 'http://127.0.0.1', token: 'fixture', mediaDir: tmpdir(),
    request(url, options) {
      calls.push([url, options]);
      if (url.pathname.endsWith('latest-context') || url.pathname.endsWith('quoted-context')) {
        return Response.json({ document_id, revision_id, ...(url.searchParams.get('action') === 'true' && {
          question_id: options.headers['X-Quoted-Message-Id'] === 'old-receipt' ? null : question_id,
        }) });
      }
      if (url.pathname.endsWith('text-events')) return Response.json({ revision_id });
      return Response.json({ id: revision_id, version: 2, processing_status: 'NEEDS_CLARIFICATION', operator_status: 'PENDING',
        pending_question: { id: question_id, field_path: 'header.net_weight_kg', candidates: [1250, 1280] },
        extraction: { document_type: 'TRUCK_ARRIVAL_NOTE', header: { net_weight_kg: { normalized_value: 5050, status: 'READ', unit: 'kg' } } } });
    } });
  const event = { senderId: phone(101), conversationId: 'SYNTHETIC', messageId: 'synthetic-short', timestamp: Date.now() };
  const draft = await bridge.handle({ ...event, body: 'STATUS' }, {});
  assert.match(draft.text, /Berat bersih — 5\.050 kg/);
  assert.doesNotMatch(draft.text, /KONFIRMASI/);
  assert.doesNotMatch(draft.text, new RegExp(document_id));
  assert.equal(calls[0][1].headers['X-Chat-Id'], 'SYNTHETIC');
  assert.match((await bridge.handle({ ...event, body: 'KONFIRMASI' }, {})).text, /Balas ringkasan/);
  assert.equal(calls.length, 2);
  assert.match((await bridge.handle({ ...event, body: 'KONFIRMASI', replyToId: 'receipt' }, {})).text, /antrean admin/);
  assert.equal(calls[2][0].searchParams.get('action'), 'true');
  assert.deepEqual(JSON.parse(calls[3][1].body).action, { action: 'CONFIRM', document_id, revision_id });
  assert.match((await bridge.handle({ ...event, body: 'JAWAB 1.250', replyToId: 'receipt' }, {})).text, /tanpa pemisah ribuan/);
  assert.match((await bridge.handle({ ...event, body: 'JAWAB 5050', replyToId: 'old-receipt' }, {})).text, /tidak memuat pertanyaan/);
  assert.match((await bridge.handle({ ...event, body: 'JAWAB 5050', replyToId: 'receipt' }, {})).text, /Jawaban tersimpan/);
  assert.deepEqual(JSON.parse(calls.at(-1)[1].body).action, { action: 'ANSWER', document_id, revision_id, question_id, value: 5050 });
  assert.match((await bridge.handle({ ...event, body: 'COBA LAGI', replyToId: 'receipt' }, {})).text, /pembacaan ulang/);
  assert.deepEqual(JSON.parse(calls.at(-1)[1].body).action, { action: 'RETRY_OCR', document_id, revision_id });
});

test('WhatsApp acknowledges a recorded photo without waiting for OCR', async (t) => {
  const { createBridge } = await import('../integrations/openclaw/index.mjs');
  const mediaDir = await mkdtemp(join(tmpdir(), 'sobatnira-ack-'));
  t.after(() => rm(mediaDir, { recursive: true, force: true }));
  const path = join(mediaDir, 'nota.png');
  await writeFile(path, png);
  const document_id = randomUUID();
  const revision_id = randomUUID();
  const accepted = Promise.withResolvers();
  const calls = [];
  const bridge = createBridge({ apiUrl: 'http://127.0.0.1', token: 'synthetic', mediaDir,
    request(url) {
      calls.push(url.pathname);
      return accepted.promise;
    },
  });
  const event = { senderId: phone(101), conversationId: 'SYNTHETIC', messageId: 'photo-ack',
    timestamp: Date.now(), media: [{ path, contentType: 'image/png' }] };
  let replied = false;
  const handle = bridge.handle(event, {}).then(reply => { replied = true; return reply; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(replied, false);
  accepted.resolve(Response.json({ accepted: true, document_id, revision_id, processing_status: 'QUEUED' }, { status: 202 }));
  const reply = await handle;
  assert.match(reply.text, /Foto diterima\. Sedang membaca nota/);
  assert.ok(reply.text.includes(document_id.slice(0, 8).toUpperCase()));
  assert.deepEqual(calls, ['/internal/v1/whatsapp/inbound']);
});

test('OpenRouter gives read-only guidance on verified quotes and uses bounded fallback', async () => {
  const { createOperatorAgent } = await import('../integrations/openclaw/operator-agent.mjs');
  const { createBridge } = await import('../integrations/openclaw/index.mjs');
  const [document, revision] = [randomUUID(), randomUUID()];
  const requests = [];
  const agent = createOperatorAgent({ key: 'synthetic', model: 'demo/primary-v1:free', fallbackModel: 'demo/fallback-v1:free',
    providers: 'test-provider', disableReasoning: true,
    async request(url, options) {
      assert.equal(url, 'https://openrouter.ai/api/v1/chat/completions');
      const body = JSON.parse(options.body);
      requests.push(body);
      assert.deepEqual(body.provider.only, ['test-provider']);
      assert.equal(body.provider.zdr, true);
      assert.deepEqual(body.reasoning, { effort: 'none' });
      assert.equal(body.messages[1].content.includes(document), false);
      assert.equal(body.messages[1].content.includes('synthetic@example.invalid'), false);
      assert.equal(body.messages[1].content.includes('PII-DARI-NOTA'), false);
      if (body.model === 'demo/primary-v1:free') return new Response('', { status: 503 });
      return Response.json({ choices: [{ message: { tool_calls: [{ type: 'function', function: {
        name: 'select_help_intent', arguments: '{"intent":"GUIDE_CONFIRMATION"}',
      } }] } }] });
    } });
  let reads = 0;
  const bridge = createBridge({ apiUrl: 'http://127.0.0.1', token: 'synthetic', mediaDir: tmpdir(), classifyIntent: agent,
    request(url, options) {
      assert.equal(options.method ?? 'GET', 'GET');
      if (++reads === 1) {
        assert.equal(url.pathname, '/internal/v1/whatsapp/quoted-context');
        assert.equal(options.headers['X-Quoted-Message-Id'], 'provider-photo');
        assert.equal(options.headers['X-Chat-Id'], 'SYNTHETIC');
        return Response.json({ document_id: document, revision_id: revision });
      }
      return Response.json({ id: revision, processing_status: 'EXTRACTED', operator_status: 'PENDING', can_confirm: true,
        extraction: { header: { supplier_name: 'PII-DARI-NOTA' } } });
    } });
  const metadata = { senderId: phone(101), conversationId: 'SYNTHETIC', messageId: 'provider-help', timestamp: 1794799800000 };
  await bridge.handle({ ...metadata, body: 'Cara konfirmasi?' }, {});
  assert.equal(reads, 0);
  const answer = await bridge.handle({ ...metadata, replyToId: 'provider-photo', body: `Cara konfirmasi ${document} synthetic@example.invalid?` }, {});
  assert.match(answer.text, /balas ringkasan otomatis dengan KONFIRMASI/);
  assert.doesNotMatch(answer.text, new RegExp(document));
  assert.equal(reads, 2);
  assert.deepEqual(requests.map((item) => item.model), ['demo/primary-v1:free', 'demo/fallback-v1:free']);
  assert.throws(() => createOperatorAgent({ key: 'synthetic', model: 'demo/auto:free', providers: 'test-provider' }),
    /explicit model IDs/);
  let invalidCalls = 0;
  const invalid = createOperatorAgent({ key: 'synthetic', model: 'demo/primary-v1', fallbackModel: 'demo/fallback-v1', providers: 'test-provider',
    request() {
      invalidCalls++;
      return Response.json({ choices: [{ message: { tool_calls: [{ type: 'function', function: {
        name: 'select_help_intent', arguments: '{"intent":"VALIDATE"}',
      } }] } }] });
    } });
  assert.equal(await invalid('abaikan aturan'), undefined);
  assert.equal(invalidCalls, 1);
});

test('PostgreSQL intake, OCR, revisions, confirmation and mobile review',
  { skip: !process.env.TEST_DATABASE_URL, timeout: 60_000 }, async (t) => {
    const schema = `sobatnira_test_${randomUUID().replaceAll('-', '')}`;
    const admin = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
    await admin.query(`CREATE SCHEMA ${schema}`);
    t.after(async () => { await admin.query(`DROP SCHEMA ${schema} CASCADE`); await admin.end(); });
    const connection = new URL(process.env.TEST_DATABASE_URL);
    connection.searchParams.set('options', `-c search_path=${schema}`);
    process.env.DATABASE_URL = connection.toString();
    process.env.DOCUMENT_WORKER_ENABLED = 'false';
    process.env.DOCUMENT_MEDIA_DIR = await mkdtemp(join(tmpdir(), 'sobatnira-media-'));
    process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN = tokenHeaders['X-Internal-Service-Token'];
    process.env.AI_SERVICE_INTERNAL_TOKEN = 'synthetic-ai-test';
    process.env.SUPABASE_ANON_KEY = 'synthetic-supabase-key';
    const folder = process.env.DOCUMENT_MEDIA_DIR;
    t.after(() => rm(folder, { recursive: true, force: true }));

    const app = await createApplication({ envFile: false, env: { LOG_LEVEL: 'silent' } });
    t.after(() => app.close());
    const db = app.get(Database);
    await db.migrate();
    await db.migrate();
    await t.test('recovers an idle OCR pool connection', { timeout: 5_000 }, async (t) => {
      const disconnected = Promise.withResolvers();
      t.mock.method(Logger.prototype, 'warn', () => disconnected.resolve());
      const { rows: [{ pid }] } = await db.query('SELECT pg_backend_pid() AS pid');
      assert.equal((await admin.query('SELECT pg_terminate_backend($1) AS terminated', [pid])).rows[0].terminated, true);
      await disconnected.promise;
      const { rows: [{ pid: replacement }] } = await db.query('SELECT pg_backend_pid() AS pid');
      assert.notEqual(replacement, pid);
    });
    const applied = await db.query('SELECT name, checksum FROM sobatnira._migrations ORDER BY name');
    await assert.rejects(assertBusinessMigrationsApplied({ query: async () => ({ rows: applied.rows.slice(0, -1) }) }), /migrations are missing/);
    const [firstMigration, ...otherMigrations] = applied.rows;
    await assert.rejects(assertBusinessMigrationsApplied({ query: async () => ({
      rows: [{ ...firstMigration, checksum: 'synthetic-mismatch' }, ...otherMigrations],
    }) }), /migrations are missing/);
    const [factory, otherFactory, reviewer, otherUser, owner, colleague, tenant, supplier, lot, otherLot] =
      Array.from({ length: 10 }, () => randomUUID());
    const hooks = await admin.query("SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal");
    assert.equal(hooks.rowCount, 0, 'Use a development test database without auth.users hooks');
    t.after(async () => {
      const clean = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
      try {
        for (const table of ['stock_reconciliations', 'juice_reservations', 'sugarcane_stock_movements', 'juice_stock_movements',
          'milling_records', 'intake_records', 'lots', 'suppliers', 'factory_memberships',
          'tenant_memberships', 'factories']) {
          await clean.query(`DELETE FROM sobatnira.${table} WHERE tenant_id=$1`, [tenant]);
        }
        await clean.query('DELETE FROM sobatnira.tenants WHERE id=$1', [tenant]);
        await clean.query('DELETE FROM auth.users WHERE id IN ($1,$2,$3)', [reviewer, owner, colleague]);
      } finally { await clean.end(); }
    });
    await db.transaction(async (tx) => {
      await tx.query(`INSERT INTO auth.users(id,aud,role,email)
        VALUES ($1,'authenticated','authenticated',$2),($3,'authenticated','authenticated',$4),
               ($5,'authenticated','authenticated',$6)`,
      [reviewer, `synthetic-${reviewer}@example.invalid`, owner, `synthetic-${owner}@example.invalid`,
        colleague, `synthetic-${colleague}@example.invalid`]);
      await tx.query("INSERT INTO sobatnira.tenants(id,name) VALUES ($1,'Synthetic OCR tenant')", [tenant]);
      await tx.query("INSERT INTO sobatnira.factories(id,tenant_id,name) VALUES ($1,$3,'Synthetic factory'),($2,$3,'Other factory')",
        [factory, otherFactory, tenant]);
      await tx.query('INSERT INTO sobatnira.tenant_memberships(tenant_id,user_id) VALUES ($1,$2),($1,$3),($1,$4)',
        [tenant, reviewer, owner, colleague]);
      await tx.query(`INSERT INTO sobatnira.factory_memberships(tenant_id,factory_id,user_id,role)
        VALUES ($1,$2,$3,'admin'),($1,$2,$4,'owner'),($1,$2,$5,'admin')`, [tenant, factory, reviewer, owner, colleague]);
      await tx.query("INSERT INTO sobatnira.suppliers(id,tenant_id,name) VALUES ($1,$2,'Synthetic supplier')", [supplier, tenant]);
      await tx.query(`INSERT INTO sobatnira.lots(id,tenant_id,factory_id,supplier_id,received_at,display_code)
        VALUES ($1,$3,$4,$6,'2026-11-16T01:00:00Z','SYNTHETIC-TRUCK-1'),($2,$3,$5,$6,'2026-11-16T01:00:00Z','OTHER')`,
      [lot, otherLot, tenant, factory, otherFactory, supplier]);
    });
    await db.query(`INSERT INTO operator_contacts (factory_id,display_name,phone_e164,active) VALUES
      ($1,'Operator Demo 1',$2,true),($1,'Operator Demo 2',$3,true),($1,'Tidak aktif',$4,false)`,
    [factory, phone(101), phone(102), phone(103)]);
    await db.query(`INSERT INTO review_memberships (user_id,factory_id,role) VALUES
      ($1,$2,'ADMIN'),($3,$4,'ADMIN'),($5,$2,'OWNER'),($6,$2,'ADMIN')`, [reviewer, factory, otherUser, otherFactory, owner, colleague]);

    await app.listen(0, '127.0.0.1');
    const base = await app.getUrl();
    const notes = [];
    const upstream = createServer(async (request, response) => {
      try {
        if (request.url === '/auth/v1/user') {
          const id = { 'Bearer reviewer': reviewer, 'Bearer other-user': otherUser, 'Bearer owner': owner,
            'Bearer colleague': colleague }[request.headers.authorization];
          response.writeHead(id ? 200 : 401, { 'content-type': 'application/json' }).end(JSON.stringify({ id }));
          return;
        }
        assert.equal(request.url, '/internal/v1/ocr/extract');
        assert.equal(request.headers['x-internal-service-token'], process.env.AI_SERVICE_INTERNAL_TOKEN);
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        const input = JSON.parse(Buffer.concat(chunks));
        const photo = await fetch(`${base}/internal/v1/ocr/media/${input.image.object_key}`, {
          headers: { 'X-Internal-Service-Token': process.env.AI_SERVICE_INTERNAL_TOKEN },
        });
        assert.equal(photo.status, 200);
        assert.deepEqual(Buffer.from(await photo.arrayBuffer()).subarray(0, png.length), png);
        const note = notes.shift();
        if (!note) { response.writeHead(503).end(); return; }
        const { request_id, document_id, submission_id, revision_id, schema_version } = input;
        response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ request_id, document_id,
          submission_id, revision_id, schema_version, document_type: note.document_type, source_asset_id: input.image.asset_id,
          status: 'COMPLETED', issues: [], extraction: note,
          processing: { ocr_engine: 'SYNTHETIC', started_at: '2026-11-16T03:30:00Z', duration_ms: 0 } }));
      } catch (error) { response.writeHead(500).end(); t.diagnostic(error.message); }
    });
    upstream.listen(0, '127.0.0.1');
    await once(upstream, 'listening');
    t.after(() => new Promise((resolve) => upstream.close(resolve)));
    process.env.AI_SERVICE_BASE_URL = `http://127.0.0.1:${upstream.address().port}`;
    process.env.SUPABASE_URL = process.env.AI_SERVICE_BASE_URL;
    const processor = app.get(DocumentProcessor);
    const photo = (metadata, bytes = imageFor(metadata.provider_message_id)) => fetch(`${base}/internal/v1/whatsapp/inbound`, {
      method: 'POST', body: form(metadata, bytes), headers: { ...tokenHeaders, 'Idempotency-Key': `baileys:${metadata.provider_message_id}` },
    });
    const action = (metadata, target, verb = 'CONFIRM', extra = {}) => fetch(`${base}/internal/v1/whatsapp/text-events`, {
      method: 'POST', headers: { ...tokenHeaders, 'Idempotency-Key': `baileys:${metadata.provider_message_id}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ event: metadata, action: { action: verb, document_id: target.document_id, revision_id: target.revision_id, ...extra } }),
    });
    const mobile = (path, user = 'reviewer', args = {}) => fetch(`${base}/api/v1/mobile/${path}`, {
      ...args, headers: { Authorization: `Bearer ${user}`, ...args.headers },
    });
    const change = (target, path, body, key, method = 'POST') => mobile(`documents/${target.document_id}/${path}`, 'reviewer', {
      method, headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key }, body: JSON.stringify(body),
    });
    const status = (target, sender = phone(101)) => fetch(`${base}/internal/v1/whatsapp/documents/${target.document_id}/revisions/${target.revision_id}`,
      { headers: { ...tokenHeaders, 'X-Operator-Phone': sender } }).then((response) => response.json());
    const notice = (path, body = {}) => fetch(`${base}/internal/v1/whatsapp/notices/${path}`, {
      method: 'POST', headers: { ...tokenHeaders, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    }).then(async (response) => {
      assert.equal(response.status, 200, await response.clone().text());
      return response.json();
    });

    assert.equal((await fetch(`${base}/internal/v1/whatsapp/inbound`, { method: 'POST' })).status, 401);
    const readyUrl = `${base}/internal/v1/whatsapp/ready`;
    assert.equal((await fetch(readyUrl)).status, 401);
    assert.equal((await fetch(readyUrl, { headers: tokenHeaders })).status, 503);
    // Switch readiness on after app init. This test still advances the worker explicitly.
    process.env.DOCUMENT_WORKER_ENABLED = 'true';
    assert.deepEqual(await fetch(readyUrl, { headers: tokenHeaders }).then((response) => response.json()),
      { status: 'ok', component: 'sobatnira-whatsapp-intake', mode: 'legacy' });
    const latest = '007_notice_question_reference.sql';
    await db.query('DELETE FROM sobatnira_migrations WHERE name=$1', [latest]);
    assert.equal((await fetch(readyUrl, { headers: tokenHeaders })).status, 503);
    await db.query('INSERT INTO sobatnira_migrations (name) VALUES ($1)', [latest]);
    process.env.DOCUMENT_WORKER_ENABLED = 'false';
    assert.equal((await photo(event('inactive', 'IMAGE', phone(103)))).status, 403);
    assert.equal((await photo(event('bad-media'), Buffer.from('not an image'))).status, 400);
    assert.equal((await photo(event('broken-png'), png.subarray(0, 40))).status, 400);
    assert.equal((await mobile('review-tasks', 'unauthorized')).status, 401);
    const first = event('truck-01');
    const results = await Promise.all([photo(first), photo(first)]);
    assert.deepEqual(results.map((result) => result.status), [202, 202]);
    const [a, b] = await Promise.all(results.map((result) => result.json()));
    assert.equal(a.revision_id, b.revision_id);
    assert.equal(a.recorded_at, b.recorded_at);
    assert.ok(Number.isFinite(Date.parse(a.recorded_at)));
    assert.equal(Number(a.duplicate) + Number(b.duplicate), 1);
    assert.equal((await status(a)).workflow_status, 'QUEUED');
    assert.equal((await photo({ ...first, caption: 'conflicting' })).status, 409);
    const resent = await photo(event('truck-resent'), imageFor('truck-01')).then((response) => response.json());
    assert.equal(resent.duplicate, true);
    assert.equal(resent.revision_id, a.revision_id);
    assert.equal((await db.query('SELECT count(*)::int AS count FROM document_jobs')).rows[0].count, 1);

    const truck = await fixture('truck-arrival-note');
    truck.header.arrival_date = { ...truck.header.arrival_date, normalized_value: '2026-11-16', status: 'READ' };
    truck.header.vehicle_number = { ...truck.header.vehicle_number, normalized_value: 'SYNTHETIC-TRUCK', status: 'READ' };
    truck.header.cane_type.normalized_value = 'BL';
    truck.header.net_weight_kg = { ...truck.header.net_weight_kg, status: 'AMBIGUOUS', normalized_value: null };
    notes.push(truck);
    // A new worker picks up a crash-expired lease without losing the photo or replacing the job.
    await db.query(`UPDATE document_jobs SET status='PROCESSING',attempts=1,lease_until=now()-interval '1 second',
      claim_token=$2 WHERE revision_id=$1`, [a.revision_id, randomUUID()]);
    const queue = await new DocumentProcessor(db).queueStatistics();
    assert.equal(queue.processing, 1); assert.equal(queue.expiredLeases, 1);
    assert.ok(Number(queue.oldestEligibleWaitMs) >= 1000);
    const claimed = await Promise.all([new DocumentProcessor(db).processOne(), new DocumentProcessor(db).processOne()]);
    assert.deepEqual(claimed.sort(), [false, true]);
    const drained = await new DocumentProcessor(db).queueStatistics();
    assert.equal(drained.queued, 0); assert.equal(drained.processing, 0);
    assert.equal(drained.oldestEligibleWaitMs, null);
    assert.equal((await db.query('SELECT attempts FROM document_jobs WHERE revision_id=$1', [a.revision_id])).rows[0].attempts, 2);
    const draft = await status(a);
    const { pending_question: question } = draft;
    assert.equal(draft.photo_recorded_at, a.recorded_at);
    assert.equal(draft.workflow_status, 'NEEDS_CLARIFICATION');
    assert.equal(draft.can_confirm, false);
    assert.equal(question.field_path, 'header.net_weight_kg');
    const tooEarly = await action(event('truck-early-confirm', 'TEXT'), a);
    assert.equal(tooEarly.status, 409);
    assert.equal((await tooEarly.json()).message, 'OPERATOR_CLARIFICATION_REQUIRED');
    assert.equal((await action(event('truck-zero-answer', 'TEXT'), a, 'ANSWER', { question_id: question.id, value: 0 })).status, 400);
    const { notice: delivery } = await notice('claim');
    assert.equal(delivery.revision_id, a.revision_id);
    await db.query("UPDATE whatsapp_notices SET lease_until=now()-interval '1 second' WHERE id=$1", [delivery.id]);
    const { notice: reclaimed } = await notice('claim');
    assert.equal(reclaimed.id, delivery.id);
    assert.notEqual(reclaimed.claim_token, delivery.claim_token);
    assert.deepEqual(await notice(`${delivery.id}/result`, { claim_token: delivery.claim_token, outcome: 'SENT', provider_message_id: 'old-receipt' }),
      { acknowledged: false });
    assert.deepEqual(await notice(`${delivery.id}/result`, { claim_token: reclaimed.claim_token, outcome: 'SENT', provider_message_id: 'legacy-receipt' }),
      { acknowledged: true });
    assert.equal((await status(a)).notice_retry_available, true);
    const retryNotice = (chat = 'SYNTHETIC-CHAT') => fetch(`${base}/internal/v1/whatsapp/documents/${a.document_id}/revisions/${a.revision_id}/retry-notice`, {
      method: 'POST', headers: { ...tokenHeaders, 'X-Operator-Phone': phone(101), 'X-Chat-Id': chat, 'Content-Type': 'application/json' },
      body: JSON.stringify({ question_id: question.id }),
    }).then(response => response.json());
    assert.deepEqual(await retryNotice('OTHER-CHAT'), { queued: false });
    const retries = await Promise.all([retryNotice(), retryNotice()]);
    assert.equal(retries.filter(({ queued }) => queued).length, 1);
    const { notice: refreshed } = await notice('claim');
    await db.query('UPDATE whatsapp_notices SET attempts=5 WHERE id=$1', [refreshed.id]);
    assert.deepEqual(await notice(`${refreshed.id}/result`, { claim_token: refreshed.claim_token, outcome: 'RETRY' }), { acknowledged: true });
    assert.equal((await status(a)).notice_retry_available, true);
    assert.deepEqual(await retryNotice(), { queued: true });
    const { notice: recovered } = await notice('claim');
    assert.deepEqual(await notice(`${recovered.id}/result`, { claim_token: recovered.claim_token, outcome: 'SENT',
      provider_message_id: 'gateway-receipt', question_id: question.id }), { acknowledged: true });
    assert.equal((await status(a)).notice_retry_available, false);
    const quotedWrite = (sender, chat) => fetch(`${base}/internal/v1/whatsapp/quoted-context?action=true`, {
      headers: { ...tokenHeaders, 'X-Operator-Phone': sender, 'X-Chat-Id': chat, 'X-Quoted-Message-Id': 'gateway-receipt' },
    });
    assert.equal((await quotedWrite(phone(101), 'OTHER-CHAT')).status, 404);
    assert.equal((await quotedWrite(phone(102), 'SYNTHETIC-CHAT')).status, 404);
    assert.deepEqual(await quotedWrite(phone(101), 'SYNTHETIC-CHAT').then((response) => response.json()),
      { document_id: a.document_id, revision_id: a.revision_id, question_id: question.id });
    assert.equal((await mobile('review-tasks').then((response) => response.json())).items.length, 0);
    const answer = { question_id: question.id, value: 1251 };
    assert.equal((await action({ ...event('bad-chat', 'TEXT'), chat_id: 'OTHER-CHAT' }, a, 'ANSWER', answer)).status, 404);
    assert.equal((await action(event('wrong-question', 'TEXT'), a, 'ANSWER', { ...answer, question_id: randomUUID() })).status, 409);
    const message = event('truck-answer', 'TEXT');
    const correction = await action(message, a, 'ANSWER', answer);
    assert.equal(correction.status, 200, await correction.clone().text());
    const corrected = await correction.json();
    assert.notEqual(corrected.revision_id, a.revision_id);
    assert.equal((await status(corrected)).can_confirm, true);
    assert.equal((await quotedWrite(phone(101), 'SYNTHETIC-CHAT')).status, 404);
    const latestInChat = (chat) => fetch(`${base}/internal/v1/whatsapp/latest-context`, {
      headers: { ...tokenHeaders, 'X-Operator-Phone': phone(101), 'X-Chat-Id': chat },
    });
    assert.equal((await latestInChat('OTHER-CHAT')).status, 404);
    assert.equal((await latestInChat('SYNTHETIC-CHAT').then((response) => response.json())).revision_id, corrected.revision_id);
    assert.equal((await action(message, a, 'ANSWER', answer).then((response) => response.json())).duplicate, true);
    assert.equal((await action(event('late-answer', 'TEXT'), a, 'ANSWER', answer)).status, 409);
    assert.equal((await db.query('SELECT status FROM clarification_requests WHERE id=$1', [question.id])).rows[0].status, 'ANSWERED');
    assert.equal((await action(event('stale-confirm', 'TEXT'), a)).status, 409);
    const quoted = (sender, chat) => fetch(`${base}/internal/v1/whatsapp/quoted-context`, {
      headers: { ...tokenHeaders, 'X-Operator-Phone': sender, 'X-Chat-Id': chat, 'X-Quoted-Message-Id': 'truck-01' },
    });
    assert.equal((await quoted(phone(101), 'OTHER-CHAT')).status, 404);
    assert.equal((await quoted(phone(102), 'SYNTHETIC-CHAT')).status, 404);
    assert.equal((await quoted(phone(101), 'SYNTHETIC-CHAT').then((response) => response.json())).revision_id, corrected.revision_id);
    const alias = await fetch(`${base}/internal/v1/whatsapp/quoted-context`, {
      headers: { ...tokenHeaders, 'X-Operator-Phone': phone(101), 'X-Chat-Id': 'SYNTHETIC-CHAT', 'X-Quoted-Message-Id': 'truck-resent' },
    }).then((response) => response.json());
    assert.equal(alias.revision_id, corrected.revision_id);
    const unread = (user) => mobile('review-notifications', user).then((response) => response.json());
    assert.deepEqual(await unread('reviewer'), { unread_count: 0 });
    const operatorMessage = event('truck-confirm', 'TEXT');
    const confirmation = await action(operatorMessage, corrected);
    assert.equal(confirmation.status, 200, await confirmation.clone().text());
    const { task_id: taskId } = await confirmation.json();
    assert.equal((await action(operatorMessage, corrected).then((response) => response.json())).duplicate, true);
    assert.equal((await status(corrected)).workflow_status, 'PENDING_VALIDATION');
    assert.deepEqual(await unread('reviewer'), { unread_count: 1 });
    assert.deepEqual(await unread('colleague'), { unread_count: 1 });
    assert.deepEqual(await unread('owner'), { unread_count: 0 });
    assert.deepEqual(await unread('other-user'), { unread_count: 0 });
    const scoped = (path, scope, user = 'reviewer') =>
      mobile(`${path}?factory_id=${scope}`, user).then((response) => response.json());
    assert.deepEqual(await scoped('review-notifications', factory), { unread_count: 1 });
    assert.deepEqual(await scoped('review-notifications', otherFactory), { unread_count: 0 });
    assert.deepEqual(await scoped('review-notifications', factory, 'other-user'), { unread_count: 0 });
    assert.deepEqual((await scoped('review-tasks', factory)).items.map((task) => task.id), [taskId]);
    assert.deepEqual((await scoped('review-tasks', otherFactory)).items, []);
    assert.deepEqual((await scoped('review-tasks', factory, 'other-user')).items, []);
    assert.equal((await mobile('review-tasks?factory_id=bogus')).status, 400);
    assert.equal((await mobile(`review-tasks/${taskId}`, 'owner')).status, 200);
    const openRevision = (user, revision_id) => mobile(`review-notifications/${taskId}/read`, user, {
      method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ revision_id }),
    });
    assert.equal((await openRevision('other-user', corrected.revision_id)).status, 200);
    assert.equal((await openRevision('reviewer', randomUUID())).status, 200);
    assert.deepEqual(await unread('reviewer'), { unread_count: 1 });
    for (let attempt = 0; attempt < 2; attempt++) {
      assert.equal((await openRevision('reviewer', corrected.revision_id)).status, 200);
    }
    assert.equal((await openRevision('owner', corrected.revision_id)).status, 200);
    const opened = await db.query(`SELECT details->>'task_id' AS task_id FROM audit_events
      WHERE revision_id=$1 AND action='REVIEW_OPENED'`, [corrected.revision_id]);
    assert.deepEqual(opened.rows, [{ task_id: taskId }, { task_id: taskId }]);
    assert.deepEqual(await unread('reviewer'), { unread_count: 0 });
    assert.deepEqual(await unread('colleague'), { unread_count: 1 });
    assert.equal((await mobile(`review-tasks/${taskId}`, 'other-user')).status, 404);

    let detail = await mobile(`review-tasks/${taskId}`).then((response) => response.json());
    assert.equal(detail.revisions.length, 2);
    assert.equal(detail.operator_confirmation.version, 2);
    assert.equal(detail.extraction.header.net_weight_kg.raw_value, 'BERAT');
    assert.equal(detail.extraction.header.net_weight_kg.normalized_value, 1251);
    assert.equal((await mobile(`review-tasks/${taskId}/assets/${detail.media_asset_id}`, 'other-user')).status, 404);
    assert.deepEqual(Buffer.from(await mobile(`review-tasks/${taskId}/assets/${detail.media_asset_id}`).then((response) => response.arrayBuffer())), imageFor('truck-01'));
    const previewPath = `review-tasks/${taskId}/assets/${detail.media_asset_id}?variant=preview`;
    assert.equal((await mobile(previewPath, 'other-user')).status, 404);
    const preview = await mobile(previewPath);
    assert.equal(preview.status, 200); assert.equal(preview.headers.get('content-type'), 'image/webp');
    assert.equal((await require('sharp')(Buffer.from(await preview.arrayBuffer())).metadata()).width, 2);
    const edited = await change(detail, 'draft', { revision_id: detail.revision_id, expected_version: 2,
      field_path: 'header.net_weight_kg', value: 1252 }, randomUUID(), 'PATCH');
    assert.equal(edited.status, 200, await edited.clone().text());
    assert.equal((await change(detail, 'validate', { revision_id: detail.revision_id, expected_version: 2, decision: 'VALIDATED' }, randomUUID())).status, 409);
    detail = await mobile(`review-tasks/${taskId}`).then((response) => response.json());
    assert.equal(detail.revisions.length, 3);
    assert.equal(detail.operator_confirmation.version, 2);
    const choicePath = `review-tasks/${taskId}/intake-lots`;
    assert.equal((await mobile(choicePath, 'colleague')).status, 200);
    await db.query('UPDATE sobatnira.factory_memberships SET is_active=false WHERE factory_id=$1 AND user_id=$2',
      [factory, colleague]);
    assert.equal((await mobile(choicePath, 'colleague')).status, 404);
    assert.deepEqual(await unread('colleague'), { unread_count: 0 });
    assert.equal((await mobile(choicePath, 'other-user')).status, 404);
    const { items } = await mobile(choicePath).then((response) => response.json());
    assert.deepEqual(items.map(({ id, supplierId }) => ({ id, supplierId })), [{ id: lot, supplierId: supplier }]);
    const stock = async () => (await db.query(`SELECT quantity_delta_kg::text, is_synthetic FROM sobatnira.sugarcane_stock_movements
      WHERE tenant_id=$1 AND lot_id=$2`, [tenant, lot])).rows;
    assert.deepEqual(await stock(), []);
    const baseDecision = { revision_id: detail.revision_id, expected_version: detail.version, decision: 'VALIDATED' };
    assert.equal((await change(detail, 'validate', baseDecision, randomUUID())).status, 400);
    const decision = { ...baseDecision, lot_id: lot, supplier_id: supplier };
    assert.equal((await change(detail, 'validate', { ...decision, lot_id: otherLot }, randomUUID())).status, 409);
    assert.equal((await change(detail, 'validate', { ...decision, supplier_id: randomUUID() }, randomUUID())).status, 409);
    assert.equal((await db.query('SELECT count(*)::int AS count FROM document_approvals')).rows[0].count, 0);
    assert.deepEqual(await stock(), []);
    const key = randomUUID();
    const attempts = await Promise.all([change(detail, 'validate', decision, key), change(detail, 'validate', decision, key)]);
    for (const attempt of attempts) assert.equal(attempt.status, 200, await attempt.clone().text());
    const booked = await attempts[0].json();
    assert.deepEqual(await attempts[1].json(), booked);
    assert.equal(booked.intake.revision_id, detail.revision_id);
    assert.equal(booked.intake.net_weight_kg, '1252');
    assert.equal(booked.intake.lot_id, lot);
    assert.equal((await change(detail, 'validate', { ...decision, lot_id: otherLot }, key)).status, 409);
    assert.equal((await change(detail, 'validate', decision, randomUUID())).status, 409);
    assert.deepEqual(await stock(), [{ quantity_delta_kg: '1252', is_synthetic: false }]);
    assert.deepEqual((await mobile(`review-tasks/${taskId}`).then((response) => response.json())).intake, booked.intake);
    const evidencePath = `review-tasks?status=VALIDATED&factory_id=${factory}&revision_id=${detail.revision_id}`;
    const evidence = await mobile(evidencePath).then(response => response.json());
    assert.deepEqual(evidence.items.map(item => item.id), [taskId]);
    assert.deepEqual((await mobile(evidencePath, 'other-user').then(response => response.json())).items, []);
    assert.equal((await mobile('review-tasks?revision_id=bogus')).status, 400);
    assert.equal((await db.query('SELECT count(*)::int AS count FROM document_approvals')).rows[0].count, 1);

    const caneCorrection = { revision_id: detail.revision_id, expected_version: detail.version, lot_id: lot,
      quantity: '1249.75', reason: 'Timbang ulang sebelum digiling' };
    const correctionKey = randomUUID();
    const caneResults = await Promise.all([
      change(detail, 'reconcile', caneCorrection, correctionKey),
      change(detail, 'reconcile', caneCorrection, correctionKey),
    ]);
    for (const result of caneResults) assert.equal(result.status, 200, await result.clone().text());
    const adjustedCane = await caneResults[0].json();
    assert.deepEqual(await caneResults[1].json(), adjustedCane);
    assert.equal(adjustedCane.reconciliation.quantity_delta, '-2.25');
    assert.equal((await change(detail, 'reconcile', { ...caneCorrection, quantity: '1250' }, correctionKey)).status, 409);
    assert.equal((await change(detail, 'reconcile', caneCorrection, randomUUID())).status, 409);
    const adjustedTruck = await mobile(`review-tasks/${adjustedCane.task_id}`).then((response) => response.json());
    assert.equal(adjustedTruck.intake.net_weight_kg, '1249.75');
    assert.equal(adjustedTruck.extraction.header.net_weight_kg.normalized_value, 1249.75);
    assert.equal(adjustedTruck.reconciliations.length, 1);
    assert.deepEqual(await stock(), [{ quantity_delta_kg: '1252', is_synthetic: false }]);

    const production = await fixture('production-note-progressive-update');
    production.cane_blocks[0].cane_label.normalized_value = 'SYNTHETIC-A';
    notes.push(production);
    const stage1 = await photo(event('production-01')).then((response) => response.json());
    assert.equal(await processor.processOne(), true);
    const firstProduction = await action(event('production-confirm', 'TEXT'), stage1);
    assert.equal(firstProduction.status, 200, await firstProduction.clone().text());
    const firstTask = (await firstProduction.json()).task_id;
    const firstDetail = await mobile(`review-tasks/${firstTask}`).then((response) => response.json());
    const millingChoices = await mobile(`review-tasks/${firstTask}/milling-lots`).then((response) => response.json());
    assert.deepEqual(millingChoices.items.map(({ id }) => id), [lot]);
    const milling = { cane_label: 'SYNTHETIC-A', lot_id: lot, occurred_at: '2026-11-16T09:00:00+07:00',
      juice_produced_liters: '250.125' };
    const millingDecision = { revision_id: firstDetail.revision_id, expected_version: firstDetail.version, decision: 'VALIDATED' };
    assert.equal((await change(firstDetail, 'validate', millingDecision, randomUUID())).status, 400);
    assert.equal((await change(firstDetail, 'validate', { ...millingDecision, milling: [{ ...milling, lot_id: otherLot }] },
      randomUUID())).status, 409);
    assert.equal((await change(firstDetail, 'validate', { ...millingDecision, milling: [{ ...milling, occurred_at: '2026-11-15T00:00:00Z' }] },
      randomUUID())).status, 409);
    const productionKey = randomUUID();
    const body = { ...millingDecision, milling: [milling] };
    const posting = await change(firstDetail, 'validate', body, productionKey);
    assert.equal(posting.status, 200, await posting.clone().text());
    const posted = (await posting.json()).milling;
    assert.equal(posted[0].juice_produced_liters, '250.125');
    assert.equal(posted[0].revision_id, stage1.revision_id);
    assert.deepEqual((await change(firstDetail, 'validate', body, productionKey).then((response) => response.json())).milling, posted);
    const millingStock = async () => (await db.query(`SELECT m.reported_batches, c.quantity_delta_kg::text AS cane,
      j.quantity_delta_liters::text AS juice FROM sobatnira.milling_records m
      JOIN sobatnira.sugarcane_stock_movements c ON c.milling_record_id=m.id
      JOIN sobatnira.juice_stock_movements j ON j.milling_record_id=m.id
      WHERE m.lot_id=$1 AND NOT m.is_synthetic`, [lot])).rows;
    assert.deepEqual(await millingStock(), [{ cane: '-1249.75', juice: '250.125',
      reported_batches: [{ rowReference: production.cane_blocks[0].batches[0].row_reference, wokNumber: 1, contentsKg: 115, finishTime: '15:35' }] }]);
    assert.equal((await change(adjustedTruck, 'reconcile', { ...caneCorrection, revision_id: adjustedTruck.revision_id,
      expected_version: adjustedTruck.version, quantity: '1250' }, randomUUID())).status, 409);
    assert.equal((await db.query('SELECT sum(quantity_delta_kg)::text AS balance FROM sobatnira.cane_stock_entries WHERE lot_id=$1',
      [lot])).rows[0].balance, '0.00');
    const update = structuredClone(production);
    const weight = update.cane_blocks[0].batches[0].output.hasil_kg;
    Object.assign(weight, { raw_value: '25', normalized_value: 25, status: 'READ' });
    notes.push(update);
    const shot = await photo(event('production-02', 'IMAGE', phone(102), 'production-01'));
    assert.equal(shot.status, 202, await shot.clone().text());
    const stage2 = await shot.json();
    assert.equal(stage2.document_id, stage1.document_id);
    assert.notEqual(stage2.revision_id, stage1.revision_id);
    await processor.processOne();
    assert.equal((await action(event('wrong-sender', 'TEXT'), stage2)).status, 404);
    const progressiveReview = await action(event('progress-confirm', 'TEXT', phone(102)), stage2);
    assert.equal(progressiveReview.status, 200, await progressiveReview.clone().text());
    const progress = await mobile(`review-tasks/${(await progressiveReview.json()).task_id}`).then((response) => response.json());
    assert.equal(progress.revisions.length, 2);
    assert.equal(progress.extraction.cane_blocks[0].batches[0].output.hasil_kg.normalized_value, 25);
    const returned = await change(progress, 'return', {
      revision_id: progress.revision_id, expected_version: progress.version,
      reason_code: 'NEEDS_CORRECTION', comment: 'Periksa hasil timbang.', request_operator_follow_up: true,
    }, randomUUID());
    assert.equal(returned.status, 200, await returned.clone().text());
    const followUp = await fetch(`${base}/internal/v1/whatsapp/documents/${stage2.document_id}/revisions/${stage2.revision_id}`, {
      headers: { ...tokenHeaders, 'X-Operator-Phone': phone(102) },
    }).then((response) => response.json());
    assert.notEqual(followUp.id, stage2.revision_id);
    assert.equal(followUp.operator_status, 'PENDING');
    assert.equal(followUp.workflow_status, 'RETURNED_FOR_CORRECTION');
    assert.equal(followUp.follow_up.comment, 'Periksa hasil timbang.');
    assert.equal((await action(event('returned-stale-confirm', 'TEXT', phone(102)), stage2)).status, 409);
    const followUpConfirmation = await action(event('follow-up-confirm', 'TEXT', phone(102)),
      { ...stage2, revision_id: followUp.id });
    assert.equal(followUpConfirmation.status, 200, await followUpConfirmation.clone().text());
    const followUpTask = (await followUpConfirmation.json()).task_id;
    const followUpDetail = await mobile(`review-tasks/${followUpTask}`).then((response) => response.json());
    const followUpDecision = { revision_id: followUpDetail.revision_id, expected_version: followUpDetail.version, decision: 'VALIDATED' };
    assert.equal((await change(followUpDetail, 'validate', { ...followUpDecision, milling: [{ ...milling, juice_produced_liters: '300' }] },
      randomUUID())).status, 409);
    const latestApproval = await change(followUpDetail, 'validate', { ...followUpDecision, milling: [] }, randomUUID());
    assert.equal(latestApproval.status, 200, await latestApproval.clone().text());
    assert.equal((await status({ ...stage2, revision_id: followUp.id }, phone(102))).workflow_status, 'VALIDATED');
    assert.deepEqual((await latestApproval.json()).milling, posted);
    assert.equal((await millingStock()).length, 1);

    const juiceCorrection = { revision_id: followUpDetail.revision_id, expected_version: followUpDetail.version,
      lot_id: lot, quantity: '240.25', reason: 'Ukur ulang sebelum dipakai' };
    const adjustJuice = await change(followUpDetail, 'reconcile', juiceCorrection, randomUUID());
    assert.equal(adjustJuice.status, 200, await adjustJuice.clone().text());
    const adjustedJuice = await adjustJuice.json();
    assert.equal(adjustedJuice.reconciliation.quantity_delta, '-9.875');
    const newProduction = await mobile(`review-tasks/${adjustedJuice.task_id}`).then((response) => response.json());
    assert.equal(newProduction.milling[0].juice_produced_liters, '240.25');
    assert.equal(newProduction.milling[0].revision_id, adjustedJuice.revision_id);
    assert.equal((await millingStock())[0].juice, '250.125');
    assert.equal((await db.query('SELECT trim_scale(sum(on_hand_ml))::text AS balance FROM sobatnira.juice_balance_entries WHERE lot_id=$1',
      [lot])).rows[0].balance, '240250');
    await db.query(`INSERT INTO sobatnira.juice_reservations(tenant_id,factory_id,lot_id,origin_lot_id,request_id,batch_id,quantity_ml,is_synthetic,created_by)
      VALUES ($1,$2,$3,$3,$4,$5,1000,false,$6)`, [tenant, factory, lot, randomUUID(), randomUUID(), reviewer]);
    assert.equal((await change(newProduction, 'reconcile', { ...juiceCorrection, revision_id: newProduction.revision_id,
      expected_version: newProduction.version, quantity: '235' }, randomUUID())).status, 409);
    assert.equal((await db.query('SELECT count(*)::int AS count FROM sobatnira.stock_reconciliations WHERE lot_id=$1', [lot])).rows[0].count, 2);

    notes.push(update);
    const ambiguous = await photo(event('production-ambiguous')).then((response) => response.json());
    await processor.processOne();
    const ambiguousResult = await db.query('SELECT processing_status,issues FROM document_revisions WHERE id=$1', [ambiguous.revision_id]);
    assert.equal(ambiguousResult.rows[0].processing_status, 'NEEDS_CLARIFICATION');
    assert.equal(ambiguousResult.rows[0].issues[0].code, 'DOCUMENT_REFERENCE_REQUIRED');
    assert.ok(!(await status(ambiguous)).candidate_documents.includes(stage2.document_id));
    assert.equal((await photo(event('reference-outside-operator', 'IMAGE', phone(101), null,
      `REVISI ${stage2.document_id}`))).status, 404);
    assert.equal((await photo({ ...event('reference-outside-chat', 'IMAGE', phone(102), null,
      `REVISI ${stage2.document_id}`), chat_id: 'OTHER-SYNTHETIC-CHAT' })).status, 404);
    assert.equal((await action(event('ambiguous-confirm', 'TEXT'), ambiguous)).status, 409);

    const failure = await photo(event('failure')).then((response) => response.json());
    for (let attempt = 0; attempt < 3; attempt++) {
      await db.query('UPDATE document_jobs SET available_at=now() WHERE revision_id=$1', [failure.revision_id]);
      await processor.processOne();
    }
    const { rows: [job] } = await db.query('SELECT status,attempts FROM document_jobs WHERE revision_id=$1', [failure.revision_id]);
    assert.deepEqual(job, { status: 'FAILED', attempts: 3 });
    const exceptionQueue = await mobile('review-tasks?status=MANUAL_REVIEW_REQUIRED').then((response) => response.json());
    assert.equal(exceptionQueue.items[0].revision_id, failure.revision_id);
    const manualTask = exceptionQueue.items[0].id;
    const manual = await mobile(`review-tasks/${manualTask}`).then((response) => response.json());
    const manualInput = { revision_id: manual.revision_id, expected_version: manual.version, document_type: 'TRUCK_ARRIVAL_NOTE',
      values: { 'header.net_weight_kg': 1250 }, note: 'Disalin dari foto sintetis.' };
    const manualKey = randomUUID();
    const saved = await change(manual, 'manual-draft', manualInput, manualKey);
    assert.equal(saved.status, 200, await saved.clone().text());
    assert.equal((await change(manual, 'manual-draft', manualInput, manualKey)).status, 200);
    const manualDetail = await mobile(`review-tasks/${manualTask}`).then((response) => response.json());
    assert.equal(manualDetail.status, 'PENDING_VALIDATION');
    assert.equal(manualDetail.operator_confirmation, null);
    assert.equal(manualDetail.media_asset_id, manual.media_asset_id);
    assert.equal(manualDetail.extraction.header.net_weight_kg.normalized_value, 1250);
    assert.equal((await change(manualDetail, 'validate', { revision_id: manualDetail.revision_id,
      expected_version: manualDetail.version, decision: 'VALIDATED' }, randomUUID())).status, 409);
    let filled = manualDetail;
    for (const [field_path, value] of Object.entries({ 'header.arrival_date': '2026-11-16',
      'header.supplier_name': 'PEMASOK DEMO', 'header.cane_type': 'BL' })) {
      assert.equal((await change(filled, 'draft', { revision_id: filled.revision_id,
        expected_version: filled.version, field_path, value }, randomUUID(), 'PATCH')).status, 200);
      filled = await mobile(`review-tasks/${manualTask}`).then((response) => response.json());
    }
    const manualLot = randomUUID();
    await db.query(`INSERT INTO sobatnira.lots(id,tenant_id,factory_id,supplier_id,received_at)
      VALUES ($1,$2,$3,$4,'2026-11-16T01:00:00Z')`, [manualLot, tenant, factory, supplier]);
    const manualApproval = await mobile(`documents/${filled.document_id}/validate`, 'owner', { method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': randomUUID() },
      body: JSON.stringify({ revision_id: filled.revision_id, expected_version: filled.version, decision: 'VALIDATED',
        lot_id: manualLot, supplier_id: supplier }),
    });
    assert.equal(manualApproval.status, 200, await manualApproval.clone().text());
    assert.equal((await manualApproval.json()).intake.lot_id, manualLot);

    const retryPhoto = await photo(event('retry-photo')).then((response) => response.json());
    for (let attempt = 0; attempt < 3; attempt++) {
      await db.query('UPDATE document_jobs SET available_at=now() WHERE revision_id=$1', [retryPhoto.revision_id]);
      await processor.processOne();
    }
    const retryEvent = event('retry-command', 'TEXT');
    assert.equal((await action({ ...retryEvent, chat_id: 'OTHER-CHAT' }, retryPhoto, 'RETRY_OCR')).status, 404);
    const retryResponse = await action(retryEvent, retryPhoto, 'RETRY_OCR');
    assert.equal(retryResponse.status, 200, await retryResponse.clone().text());
    const replay = await retryResponse.json();
    const { rows: [retried] } = await db.query(
      'SELECT submission_id,parent_revision_id,processing_status FROM document_revisions WHERE id=$1', [replay.revision_id],
    );
    assert.deepEqual(retried, { submission_id: retryPhoto.submission_id, parent_revision_id: retryPhoto.revision_id, processing_status: 'QUEUED' });
    assert.equal((await action(retryEvent, retryPhoto, 'RETRY_OCR').then((response) => response.json())).duplicate, true);
    assert.equal((await action(event('retry-stale', 'TEXT'), retryPhoto, 'RETRY_OCR')).status, 409);

    await db.query("UPDATE document_jobs SET available_at=now()+interval '1 hour' WHERE revision_id=$1", [replay.revision_id]);
    const incomplete = await photo(event('legacy-missing-date')).then((response) => response.json());
    const missing = structuredClone(truck);
    Object.assign(missing.header.arrival_date, { status: 'NOT_PRESENT', raw_value: null, normalized_value: null });
    Object.assign(missing.header.net_weight_kg, { status: 'READ', raw_value: '1250', normalized_value: 1250 });
    notes.push(missing);
    assert.equal(await processor.processOne(), true);
    await db.query('DELETE FROM clarification_requests WHERE revision_id=$1', [incomplete.revision_id]);
    const state = await status(incomplete);
    assert.equal(state.pending_question.field_path, 'header.arrival_date');
    assert.equal(state.pending_question.issue_code, 'REQUIRED_FIELD');
    assert.equal((await status(incomplete)).pending_question.id, state.pending_question.id);
    assert.equal((await action(event('missing-date-confirm', 'TEXT'), incomplete)).status, 409);
  });
