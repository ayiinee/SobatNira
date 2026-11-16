const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');
const { mkdtemp, readFile, rm } = require('node:fs/promises');
const { createServer } = require('node:http');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const test = require('node:test');
const { Pool } = require('pg');
const { createApplication } = require('../dist/application.js');
const { Database } = require('../dist/documents/database.js');
const { DocumentProcessor } = require('../dist/documents/processing.js');
const { mergeProduction } = require('../dist/documents/revisions.js');

const fixture = (name) => readFile(join(__dirname, '../../../docs/ai/examples', `${name}.example.json`), 'utf8').then(JSON.parse);
const phone = (suffix) => '+' + [1, 202, 555, String(suffix).padStart(4, '0')].join('');
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a4FcAAAAASUVORK5CYII=', 'base64');
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

test('progressive merge preserves evidence and distinct runs with reused wajan', async () => {
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
  assert.deepEqual(issues, []);
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
  plugin.register({ config: {}, pluginConfig: { accountId: 'work', mediaDir: tmpdir() }, logger: { warn() {} },
    registerService(service) { assert.equal(service.id, 'sobatnira-notices'); },
    on(name, callback, opts) {
      assert.equal(name, 'reply_dispatch');
      assert.deepEqual(opts.eligibleDispatchKinds, ['agent']);
      dispatch = callback;
    },
    runtime: { channel: { outbound: { loadAdapter() {} } } },
  });
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
});

test('OpenRouter gives read-only guidance on verified quotes and uses bounded fallback', async () => {
  const { createOperatorAgent } = await import('../integrations/openclaw/operator-agent.mjs');
  const { createBridge } = await import('../integrations/openclaw/index.mjs');
  const [document, revision] = [randomUUID(), randomUUID()];
  const requests = [];
  const agent = createOperatorAgent({ key: 'synthetic', model: 'demo/primary-v1', fallbackModel: 'demo/fallback-v1', providers: 'test-provider',
    async request(url, options) {
      assert.equal(url, 'https://openrouter.ai/api/v1/chat/completions');
      const body = JSON.parse(options.body);
      requests.push(body);
      assert.deepEqual(body.provider.only, ['test-provider']);
      assert.equal(body.provider.zdr, true);
      assert.equal(body.messages[1].content.includes(document), false);
      assert.equal(body.messages[1].content.includes('synthetic@example.invalid'), false);
      assert.equal(body.messages[1].content.includes('PII-DARI-NOTA'), false);
      if (body.model === 'demo/primary-v1') return new Response('', { status: 503 });
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
      return Response.json({ id: revision, processing_status: 'EXTRACTED', operator_status: 'PENDING',
        extraction: { header: { supplier_name: 'PII-DARI-NOTA' } } });
    } });
  const metadata = { senderId: phone(101), conversationId: 'SYNTHETIC', messageId: 'provider-help', timestamp: 1794799800000 };
  await bridge.handle({ ...metadata, body: 'Cara konfirmasi?' }, {});
  assert.equal(reads, 0);
  const answer = await bridge.handle({ ...metadata, replyToId: 'provider-photo', body: `Cara konfirmasi ${document} synthetic@example.invalid?` }, {});
  assert.match(answer.text, new RegExp(`STATUS ${document} ${revision}`));
  assert.equal(reads, 2);
  assert.deepEqual(requests.map((item) => item.model), ['demo/primary-v1', 'demo/fallback-v1']);
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
    const [factory, otherFactory, reviewer, otherUser, owner, colleague, tenant, supplier, lot, otherLot] =
      Array.from({ length: 10 }, () => randomUUID());
    const hooks = await admin.query("SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal");
    assert.equal(hooks.rowCount, 0, 'Use a development test database without auth.users hooks');
    t.after(async () => {
      const clean = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
      try {
        for (const table of ['sugarcane_stock_movements', 'juice_stock_movements', 'milling_records', 'intake_records', 'lots', 'suppliers', 'factory_memberships',
          'tenant_memberships', 'factories']) {
          await clean.query(`DELETE FROM sobatnira.${table} WHERE tenant_id=$1`, [tenant]);
        }
        await clean.query('DELETE FROM sobatnira.tenants WHERE id=$1', [tenant]);
        await clean.query('DELETE FROM auth.users WHERE id IN ($1,$2)', [reviewer, owner]);
      } finally { await clean.end(); }
    });
    await db.transaction(async (tx) => {
      await tx.query(`INSERT INTO auth.users(id,aud,role,email)
        VALUES ($1,'authenticated','authenticated',$2),($3,'authenticated','authenticated',$4)`,
      [reviewer, `synthetic-${reviewer}@example.invalid`, owner, `synthetic-${owner}@example.invalid`]);
      await tx.query("INSERT INTO sobatnira.tenants(id,name) VALUES ($1,'Synthetic OCR tenant')", [tenant]);
      await tx.query("INSERT INTO sobatnira.factories(id,tenant_id,name) VALUES ($1,$3,'Synthetic factory'),($2,$3,'Other factory')",
        [factory, otherFactory, tenant]);
      await tx.query('INSERT INTO sobatnira.tenant_memberships(tenant_id,user_id) VALUES ($1,$2),($1,$3)', [tenant, reviewer, owner]);
      await tx.query(`INSERT INTO sobatnira.factory_memberships(tenant_id,factory_id,user_id,role)
        VALUES ($1,$2,$3,'admin'),($1,$2,$4,'owner')`, [tenant, factory, reviewer, owner]);
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
    const status = (target) => fetch(`${base}/internal/v1/whatsapp/documents/${target.document_id}/revisions/${target.revision_id}`,
      { headers: { ...tokenHeaders, 'X-Operator-Phone': phone(101) } }).then((response) => response.json());
    const notice = (path, body = {}) => fetch(`${base}/internal/v1/whatsapp/notices/${path}`, {
      method: 'POST', headers: { ...tokenHeaders, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    }).then(async (response) => {
      assert.equal(response.status, 200, await response.clone().text());
      return response.json();
    });

    assert.equal((await fetch(`${base}/internal/v1/whatsapp/inbound`, { method: 'POST' })).status, 401);
    assert.equal((await photo(event('inactive', 'IMAGE', phone(103)))).status, 403);
    assert.equal((await photo(event('bad-media'), Buffer.from('not an image'))).status, 400);
    assert.equal((await mobile('review-tasks', 'unauthorized')).status, 401);
    const first = event('truck-01');
    const results = await Promise.all([photo(first), photo(first)]);
    assert.deepEqual(results.map((result) => result.status), [202, 202]);
    const [a, b] = await Promise.all(results.map((result) => result.json()));
    assert.equal(a.revision_id, b.revision_id);
    assert.equal(Number(a.duplicate) + Number(b.duplicate), 1);
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
    assert.equal(await new DocumentProcessor(db).processOne(), true);
    assert.equal((await db.query('SELECT attempts FROM document_jobs WHERE revision_id=$1', [a.revision_id])).rows[0].attempts, 2);
    const { pending_question: question } = await status(a);
    assert.equal(question.field_path, 'header.net_weight_kg');
    const { notice: delivery } = await notice('claim');
    assert.equal(delivery.revision_id, a.revision_id);
    await db.query("UPDATE whatsapp_notices SET lease_until=now()-interval '1 second' WHERE id=$1", [delivery.id]);
    const { notice: reclaimed } = await notice('claim');
    assert.equal(reclaimed.id, delivery.id);
    assert.notEqual(reclaimed.claim_token, delivery.claim_token);
    assert.deepEqual(await notice(`${delivery.id}/result`, { claim_token: delivery.claim_token, outcome: 'SENT', provider_message_id: 'old-receipt' }),
      { acknowledged: false });
    assert.deepEqual(await notice(`${delivery.id}/result`, { claim_token: reclaimed.claim_token, outcome: 'SENT', provider_message_id: 'gateway-receipt' }),
      { acknowledged: true });
    assert.equal((await mobile('review-tasks').then((response) => response.json())).items.length, 0);
    const answer = { question_id: question.id, value: 1251 };
    assert.equal((await action({ ...event('bad-chat', 'TEXT'), chat_id: 'OTHER-CHAT' }, a, 'ANSWER', answer)).status, 404);
    assert.equal((await action(event('wrong-question', 'TEXT'), a, 'ANSWER', { ...answer, question_id: randomUUID() })).status, 409);
    const message = event('truck-answer', 'TEXT');
    const correction = await action(message, a, 'ANSWER', answer);
    assert.equal(correction.status, 200, await correction.clone().text());
    const corrected = await correction.json();
    assert.notEqual(corrected.revision_id, a.revision_id);
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
    assert.deepEqual(await unread('reviewer'), { unread_count: 1 });
    assert.deepEqual(await unread('colleague'), { unread_count: 1 });
    assert.deepEqual(await unread('owner'), { unread_count: 0 });
    assert.deepEqual(await unread('other-user'), { unread_count: 0 });
    assert.equal((await mobile(`review-tasks/${taskId}`, 'owner')).status, 200);
    for (let attempt = 0; attempt < 2; attempt++) {
      assert.equal((await mobile(`review-notifications/${taskId}/read`, 'reviewer', { method: 'PATCH' })).status, 200);
    }
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
    const edited = await change(detail, 'draft', { revision_id: detail.revision_id, expected_version: 2,
      field_path: 'header.net_weight_kg', value: 1252 }, randomUUID(), 'PATCH');
    assert.equal(edited.status, 200, await edited.clone().text());
    assert.equal((await change(detail, 'validate', { revision_id: detail.revision_id, expected_version: 2, decision: 'VALIDATED' }, randomUUID())).status, 409);
    detail = await mobile(`review-tasks/${taskId}`).then((response) => response.json());
    assert.equal(detail.revisions.length, 3);
    assert.equal(detail.operator_confirmation.version, 2);
    const choicePath = `review-tasks/${taskId}/intake-lots`;
    assert.equal((await mobile(choicePath, 'colleague')).status, 403);
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
    assert.equal((await db.query('SELECT count(*)::int AS count FROM document_approvals')).rows[0].count, 1);

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
    assert.deepEqual(await millingStock(), [{ cane: '-1252', juice: '250.125',
      reported_batches: [{ rowReference: production.cane_blocks[0].batches[0].row_reference, wokNumber: 1, contentsKg: 115, finishTime: '15:35' }] }]);
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
    assert.deepEqual((await latestApproval.json()).milling, posted);
    assert.equal((await millingStock()).length, 1);

    notes.push(update);
    const ambiguous = await photo(event('production-ambiguous')).then((response) => response.json());
    await processor.processOne();
    const ambiguousResult = await db.query('SELECT processing_status,issues FROM document_revisions WHERE id=$1', [ambiguous.revision_id]);
    assert.equal(ambiguousResult.rows[0].processing_status, 'NEEDS_CLARIFICATION');
    assert.equal(ambiguousResult.rows[0].issues[0].code, 'DOCUMENT_REFERENCE_REQUIRED');
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
  });
