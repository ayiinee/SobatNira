const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { mkdtemp, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { pathToFileURL } = require('node:url');
const test = require('node:test');
const { Workbook } = require('exceljs');
const { PDFDocument } = require('pdf-lib');
const { ReportExports } = require('../../dist/production/report-exports');
const { MediaStorage } = require('../../dist/documents/media');
const { mobileClosureFixture } = require('./mobile-closure-fixture.cjs');

test('OpenClaw owner session, official answers and recoverable report exports', async t => {
  const fixture = await mobileClosureFixture();
  t.after(() => fixture.close());
  const folder = await mkdtemp(join(tmpdir(), 'sobatnira-agent-test-'));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const token = randomUUID();
  const env = { OWNER_AGENT_ENABLED: 'true', REPORT_EXPORT_ENABLED: 'true', DOCUMENT_MEDIA_DIR: folder,
    WHATSAPP_ADAPTER_INTERNAL_TOKEN: token };
  const previous = Object.fromEntries(Object.keys(env).map(key => [key, process.env[key]]));
  Object.assign(process.env, env);
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });
  const { createBridge } = await import(pathToFileURL(join(__dirname, '../../integrations/openclaw/index.mjs')));
  const { createOwnerNarrator } = await import(pathToFileURL(join(__dirname, '../../integrations/openclaw/owner-agent.mjs')));
  const phone = '+12025550101';
  const anotherPhone = '+12025550102';
  const sent = [];
  const narration = [];
  const narrator = createOwnerNarrator({ key: 'fixture-key', model: 'example/model-v1', providers: 'example-provider',
    request: async (_, options) => {
      const request = JSON.parse(options.body);
      const metadata = request.messages.find(message => message.role === 'user').content;
      narration.push(metadata);
      if (metadata === 'PARTIAL') return new Response(null, { status: 503 });
      return Response.json({ choices: [{ message: { tool_calls: [{ type: 'function',
        function: { name: 'select_owner_explanation', arguments: JSON.stringify({ intent: 'SUMBER' }) },
      }] } }] });
    } });
  const bridge = createBridge({ apiUrl: fixture.base, token, mediaDir: folder, ownerAgent: true,
    selectOwnerView: async value => { sent.push(value); return 'GRADES'; },
    narrateOwnerResult: narrator });
  const chat = async (body, messageId = randomUUID(), senderId = phone, conversationId = senderId) =>
    (await bridge.handle({ senderId, conversationId, messageId, body,
      timestamp: Date.parse('2026-11-17T16:55:00Z') }, {})).text;
  const memberships = fixture.root + '/owner-agent/sessions';
  const path = fixture.root + '/report-exports';
  const owner = 'fixture-owner';
  const batch = await fixture.request(fixture.root + '/production/batches?lotId=' + fixture.ids.lot);
  const batchId = batch.body.items[0].id;
  assert.match(await chat('ASISTEN total produksi kemarin'), /Akses belum tersedia/);
  assert.match(await chat('ASISTEN petakan distribusi kemarin +12025550123'), /Akses belum tersedia/);
  assert.match(await chat('ASISTEN jelaskan total produksi, grade dan kontribusi terbesar kemarin'), /Akses belum tersedia/);
  assert.deepEqual(sent, []);
  assert.deepEqual(narration, []);
  assert.equal((await fixture.request(memberships, 'POST', { phone })).status, 403);
  assert.equal((await fixture.request(fixture.siblingRoot + '/owner-agent/sessions', 'POST', { phone }, owner)).status, 403);
  const grant = await fixture.request(memberships, 'POST', { phone }, owner);
  assert.equal(grant.status, 201, JSON.stringify(grant.body));
  const connect = 'SAMBUNG ' + grant.body.code;
  assert.match(await chat(connect, randomUUID(), anotherPhone), /Akses belum tersedia/);
  assert.match(await chat(connect, randomUUID(), phone, 'other-chat'), /Akses belum tersedia/);
  assert.match(await chat(connect), /tersambung/);
  assert.match(await chat(connect), /Akses belum tersedia/);
  const summary = await chat('ASISTEN total produksi kemarin perusahaan-rahasia +12025550123');
  assert.match(summary, /gula final: 30 kg/);
  assert.match(summary, /Periode 2026-11-16 sampai sebelum 2026-11-17 WIB/);
  assert.deepEqual(sent, []);
  assert.match(await chat('ASISTEN petakan distribusi kemarin perusahaan-rahasia +12025550123'), /Grade A: 30 kg/);
  assert.deepEqual(sent, ['petakan distribusi']);
  const ambiguousRank = await chat('ASISTEN berapa total produksi, distribusi grade, dan kontribusi terbesar kemarin?');
  assert.match(ambiguousRank, /gula final: 30 kg/);
  assert.match(ambiguousRank, /Grade A: 30 kg/);
  assert.match(ambiguousRank, /Untuk peringkat, apakah yang dimaksud/);
  assert.doesNotMatch(ambiguousRank, /250000 mL/);
  const explicitRank = 'ASISTEN jelaskan total produksi, grade, dan kontribusi nira terbesar berdasarkan tanggal penerimaan kloter batch kemarin';
  const ranked = await chat(explicitRank);
  assert.match(ranked, /250000 mL/);
  assert.match(ranked, /Referensi sumber dapat diperiksa/);
  assert.deepEqual(narration, ['COMPLETE']);
  await fixture.client.query("UPDATE sobatnira.juice_reservations SET quantity_ml=1 WHERE batch_id=$1", [batchId]);
  const incomplete = await chat(explicitRank);
  assert.match(incomplete, /debit nira tidak cocok/);
  assert.doesNotMatch(incomplete, /250000 mL/);
  assert.deepEqual(narration, ['COMPLETE', 'PARTIAL']);
  await fixture.client.query("UPDATE sobatnira.juice_reservations SET quantity_ml=250000 WHERE batch_id=$1", [batchId]);
  const trace = await chat('ASISTEN telusuri batch ' + batchId);
  assert.match(trace, /250000 mL/);
  assert.match(trace, /Relasi masak ulang resmi belum tersedia/);
  assert.match(await chat('ASISTEN telusuri batch ' + randomUUID()), /Referensi tidak ditemukan/);

  const requestId = randomUUID();
  const requested = await chat('ASISTEN buat laporan kemarin', requestId);
  assert.match(requested, /sedang diproses/);
  const id = requested.match(/[a-f0-9-]{36}/)[0];
  assert.match(await chat('ASISTEN buat laporan kemarin', requestId), new RegExp(id));
  const snapshot = await fixture.request(path + '/' + id + '/snapshot', 'GET', undefined, owner);
  assert.equal(snapshot.status, 200);
  assert.equal(snapshot.body.snapshot.totals.finalSugarKg, '30');
  assert.equal((await fixture.request(path + '/' + id, 'GET')).status, 404);
  const getFile = (format, actor = owner) => fetch(fixture.base + path + '/' + id + '/files/' + format,
    { headers: { Authorization: 'Bearer ' + actor } });
  assert.equal((await getFile('pdf')).status, 409);
  assert.equal((await getFile('pdf', 'fixture-admin')).status, 404);
  const notifications = [];
  const send = async value => { notifications.push(value); return 'synthetic-provider-receipt'; };
  assert.equal(await bridge.deliverReportNotice(send), false);

  const reports = fixture.app.get(ReportExports);
  const storage = fixture.app.get(MediaStorage);
  const realRead = storage.read.bind(storage);
  const failure = t.mock.method(storage, 'read', async () => { throw new Error('synthetic storage timeout'); });
  assert.equal(await reports.processOne(), true);
  assert.equal((await getFile('pdf')).status, 409);
  failure.mock.restore();
  // Simulate a worker dying after it claimed the next attempt.
  await fixture.client.query(`UPDATE sobatnira.report_exports SET status='PROCESSING',
    lease_until=clock_timestamp()-interval '1 second',claim_token=$2 WHERE id=$1`, [id, randomUUID()]);
  assert.equal(await reports.processOne(), true);
  assert.equal(await reports.processOne(), false);
  const { rows: [stored] } = await fixture.client.query(
    'SELECT attempts,artifacts FROM sobatnira.report_exports WHERE id=$1', [id]);
  assert.equal(stored.attempts, 2);
  assert.deepEqual(Object.keys(stored.artifacts).sort(), ['pdf', 'xlsx']);
  assert.match(await chat('ASISTEN status laporan ' + id), /siap dalam PDF dan XLSX/);
  assert.equal(await bridge.deliverReportNotice(send), true);
  assert.equal(await bridge.deliverReportNotice(send), false);
  assert.deepEqual(notifications, [{ to: phone, replyToId: requestId,
    text: `Laporan ${id} siap dalam PDF dan XLSX. Unduh dengan sesi owner di SobatNira.` }]);

  const pdf = await getFile('pdf');
  const xlsx = await getFile('xlsx');
  assert.equal(pdf.status, 200);
  assert.equal(xlsx.status, 200);
  assert.equal(pdf.headers.get('content-type'), 'application/pdf');
  assert.ok((await PDFDocument.load(await pdf.arrayBuffer())).getPageCount() > 0);
  const workbook = new Workbook();
  await workbook.xlsx.load(await xlsx.arrayBuffer());
  const sheet = workbook.getWorksheet('Ringkasan');
  assert.equal(sheet.getCell('B8').value, '30');
  assert.equal(sheet.getCell('B11').value, snapshot.body.snapshot.totals.productionMarginRupiah);
  assert.ok((await realRead(stored.artifacts.pdf.key, 'reports')).length > 0);

  const adminJob = await reports.request({ tenantId: fixture.ids.tenant, factoryId: fixture.ids.factory,
    userId: fixture.ids.admin, role: 'admin' }, randomUUID(),
    { from: '2026-11-16T00:00:00Z', before: '2026-11-17T00:00:00Z', synthetic: false });
  assert.equal((await fixture.request(path + '/' + adminJob.id, 'GET')).status, 200);
  assert.equal((await fixture.request(path + '/' + adminJob.id, 'GET', undefined, owner)).status, 404);
  assert.equal(await reports.processOne(), true);
  assert.equal((await fetch(fixture.base + path + '/' + adminJob.id + '/files/pdf',
    { headers: { Authorization: 'Bearer fixture-admin' } })).status, 200);

  await fixture.client.query(`UPDATE sobatnira.factory_memberships SET is_active=false
    WHERE (factory_id,user_id)=($1,$2)`, [fixture.ids.factory, fixture.ids.owner]);
  assert.match(await chat('ASISTEN status laporan ' + id), /Akses belum tersedia/);
  assert.equal((await getFile('pdf')).status, 403);
});
