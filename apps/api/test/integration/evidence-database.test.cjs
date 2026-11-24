const assert = require('node:assert/strict');
const { randomUUID, createHash } = require('node:crypto');
const test = require('node:test');
const sharp = require('sharp');
const { intakeFixture } = require('./intake-fixture.cjs');
const { r2Fixture } = require('../helpers/r2-fixture.cjs');
const { evidenceRequests } = require('./evidence-requests.cjs');
const { MAX_EVIDENCE_BYTES } = require('../../dist/evidence/evidence.types');
const { DatabaseService } = require('../../dist/database/database.service');
const { EvidenceRepository } = require('../../dist/evidence/evidence.repository');
const { ServiceUnavailableException } = require('@nestjs/common');

const png = (color = 'white') => sharp({ create: { width: 32, height: 24, channels: 3, background: color } }).png().toBuffer();

test('photo upload is scoped, versioned, private, idempotent and retained through synthetic approval', async () => {
  const r2 = await r2Fixture();
  const f = await intakeFixture(false, r2.env);
  const { upload, content } = evidenceRequests(f);
  try {
    const bytes = await png();
    const draft = await f.create();
    assert.equal(draft.status, 201, JSON.stringify(draft.body));
    const id = draft.body.id;
    const path = f.root + '/intake-documents/' + id;
    const requestId = randomUUID();
    r2.state.public = true;
    assert.equal((await upload(id, bytes, { requestId })).status, 503);
    assert.equal(r2.objects.size, 0);
    assert.ok(r2.calls.every((call) => call.key.startsWith('privacy-checks/')));
    r2.state.public = false;
    const photo = await upload(id, bytes, { requestId });
    assert.equal(photo.status, 201, JSON.stringify(photo.body));
    assert.equal(photo.body.document.currentRevision, 2);
    assert.equal(photo.body.document.evidence.id, photo.body.evidence.id);
    assert.equal(photo.body.evidence.sha256, createHash('sha256').update(bytes).digest('hex'));
    assert.equal(photo.body.evidence.width, 32);
    assert.equal(r2.objects.size, 1);
    assert.ok(!JSON.stringify(photo.body).includes('objectKey'));
    assert.ok(!JSON.stringify(photo.body).includes('synthetic-bucket'));
    const key = [...r2.objects.keys()][0];
    assert.ok(key.startsWith(`tenants/${f.ids.tenant}/factories/${f.ids.factory}/intake-documents/${id}/evidence/`));
    assert.ok(key.endsWith('.png'));
    assert.ok(!key.includes('untrusted-name'));
    const read = await content(photo.body.evidence.contentPath);
    assert.equal(read.status, 200);
    assert.equal(read.headers.get('content-type'), 'image/png');
    assert.equal(read.headers.get('cache-control'), 'private, no-store');
    assert.equal(read.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(read.headers.get('access-control-allow-origin'), 'http://localhost:8080');
    assert.deepEqual(Buffer.from(await read.arrayBuffer()), bytes);
    for (const variant of ['preview', 'thumbnail']) {
      const response = await content(photo.body.evidence.contentPath + '?variant=' + variant);
      assert.equal(response.status, 200); assert.equal(response.headers.get('content-type'), 'image/webp');
      assert.equal((await sharp(Buffer.from(await response.arrayBuffer())).metadata()).width, 32);
    }
    assert.equal((await content(photo.body.evidence.contentPath + '?variant=unknown')).status, 400);
    assert.equal((await content(photo.body.evidence.contentPath, null)).status, 401);
    const beforeCalls = r2.calls.length;
    for (const root of [f.siblingRoot, f.otherRoot]) {
      const response = await content(photo.body.evidence.contentPath.replace(f.root, root));
      assert.equal(response.status, 404);
      assert.equal((await f.request(root + '/intake-documents/' + id + '/evidence')).status, 404);
      assert.equal((await content(photo.body.evidence.contentPath.replace(f.root, root) + '?variant=preview')).status, 404);
    }
    assert.equal(r2.calls.length, beforeCalls);
    const otherDoc = await f.create(f.ids.secondLot);
    assert.equal((await content(photo.body.evidence.contentPath.replace(id, otherDoc.body.id))).status, 404);
    const replay = await upload(id, bytes, { requestId });
    assert.equal(replay.body.evidence.id, photo.body.evidence.id);
    assert.equal(replay.body.document.currentRevision, 2);
    assert.equal(r2.calls.length, beforeCalls);
    assert.equal((await upload(id, await png('black'), { requestId })).status, 409);
    assert.equal((await upload(id, bytes, { requestId: randomUUID(), expectedRevision: 1 })).status, 409);
    assert.equal((await upload(id, bytes, { requestId: randomUUID(), expectedRevision: 2, extra: { objectKey: 'other-tenant' } })).status, 400);
    assert.equal((await upload(id, undefined, { requestId: randomUUID(), expectedRevision: 2 })).status, 400);
    assert.equal((await upload(id, Buffer.alloc(MAX_EVIDENCE_BYTES + 1), { requestId: randomUUID(), expectedRevision: 2 })).status, 413);

    // A replaced image remains available for the older revision.
    const replacement = await upload(id, await png('black'), { requestId: randomUUID(), expectedRevision: 2 });
    assert.equal(replacement.status, 201, JSON.stringify(replacement.body));
    assert.equal(replacement.body.document.currentRevision, 3);
    assert.notEqual(replacement.body.evidence.id, photo.body.evidence.id);
    assert.equal(r2.objects.size, 2);
    const oldRead = await content(photo.body.evidence.contentPath);
    assert.deepEqual(Buffer.from(await oldRead.arrayBuffer()), bytes);
    assert.equal((await f.request(path + '/evidence')).body.total, 2);
    const revisions = (await f.request(path + '/revisions')).body.items;
    assert.equal(revisions.find((revision) => revision.revision === 2).evidenceId, photo.body.evidence.id);
    assert.equal(revisions.find((revision) => revision.revision === 3).evidenceId, replacement.body.evidence.id);
    await f.request(path + '/draft', 'PATCH', { expectedRevision: 3, reason: 'Tinjauan sintetis', changes: { netWeightKg: '1300.25' } });
    assert.equal((await f.request(path)).body.evidence.id, replacement.body.evidence.id);
    assert.equal((await f.request(path + '/revisions')).body.items.find((revision) => revision.revision === 4).evidenceId, replacement.body.evidence.id);
    assert.equal((await f.request(path + '/confirm-synthetic', 'POST', { expectedRevision: 4 })).status, 200);
    assert.equal((await upload(id, bytes, { requestId: randomUUID(), expectedRevision: 4 })).status, 409);
    assert.equal((await f.request(path + '/approve', 'POST', { expectedRevision: 4 })).status, 200);
    assert.equal((await upload(id, bytes, { requestId })).body.evidence.id, photo.body.evidence.id);
    assert.equal((await f.request(f.root + '/stock/sugarcane?synthetic=true')).body.quantityKg, '1300.25');

    // Corruption in storage never reaches the client as an apparently valid photo.
    r2.objects.get(key).bytes = Buffer.from(bytes);
    r2.objects.get(key).bytes[bytes.length - 1] ^= 1;
    assert.equal((await content(photo.body.evidence.contentPath)).status, 503);
    r2.objects.get(key).bytes = bytes;
    r2.state.failGet = true;
    assert.equal((await content(photo.body.evidence.contentPath)).status, 503);
    r2.state.failGet = false;

    // A DB failure removes only the fresh unlinked upload, preserving previous evidence.
    const failureDoc = await f.create(f.ids.thirdLot);
    const failurePath = f.root + '/intake-documents/' + failureDoc.body.id;
    await f.client.query('SAVEPOINT reject_photo_audit');
    await f.client.query("ALTER TABLE sobatnira.intake_document_events ADD CONSTRAINT synthetic_reject_photo CHECK (action <> 'evidence_attached') NOT VALID");
    assert.ok((await upload(failureDoc.body.id, bytes, { requestId: randomUUID() })).status >= 500);
    assert.equal((await f.request(failurePath)).body.currentRevision, 1);
    assert.equal((await f.request(failurePath)).body.evidence, null);
    assert.equal(r2.objects.size, 2);
    await f.client.query('ROLLBACK TO SAVEPOINT reject_photo_audit');
    r2.state.failPut = true;
    assert.equal((await upload(failureDoc.body.id, bytes, { requestId: randomUUID() })).status, 503);
    assert.equal((await f.request(failurePath)).body.currentRevision, 1);
    r2.state.failPut = false;

    // Re-check authorization after the network upload, not only at request start.
    r2.state.onImagePut = async () => {
      await f.client.query('UPDATE sobatnira.factory_memberships SET is_active = false WHERE user_id = $1', [f.ids.admin]);
      r2.state.onImagePut = null;
    };
    assert.equal((await upload(failureDoc.body.id, bytes, { requestId: randomUUID() })).status, 403);
    assert.equal(r2.objects.size, 2);
    assert.equal((await content(photo.body.evidence.contentPath)).status, 403);
  } finally { await f.close(); await r2.close(); }
});

test('concurrent photo retries produce one attachment and remove losing uploads', async () => {
  const r2 = await r2Fixture();
  const f = await intakeFixture(true, r2.env);
  const { upload } = evidenceRequests(f);
  try {
    const bytes = await png();
    const draft = await f.create();
    const id = draft.body.id;
    const requestId = randomUUID();
    const uploads = await Promise.all(Array.from({ length: 3 }, () => upload(id, bytes, { requestId })));
    for (const response of uploads) assert.equal(response.status, 201, JSON.stringify(response.body));
    assert.equal(new Set(uploads.map((response) => response.body.evidence.id)).size, 1);
    assert.equal(r2.objects.size, 1);
    assert.equal((await f.request(f.root + '/intake-documents/' + id)).body.currentRevision, 2);
    const replacements = await Promise.all(Array.from({ length: 2 }, () => upload(id, bytes, { requestId: randomUUID(), expectedRevision: 2 })));
    assert.deepEqual(replacements.map((response) => response.status).sort(), [201, 409]);
    assert.equal(r2.objects.size, 2);
    assert.equal((await f.request(f.root + '/intake-documents/' + id + '/evidence')).body.total, 2);

    // An ambiguous response after a successful COMMIT must not delete the attached image.
    const another = await f.create(f.ids.secondLot);
    const database = f.app.get(DatabaseService);
    const originalTransaction = database.transaction.bind(database);
    let interruptCommitResponse = true;
    database.transaction = async (work) => {
      const result = await originalTransaction(work);
      if (interruptCommitResponse && result?.storedKey) {
        interruptCommitResponse = false;
        throw new ServiceUnavailableException('Synthetic interruption after commit');
      }
      return result;
    };
    const interruptedRequest = randomUUID();
    assert.equal((await upload(another.body.id, bytes, { requestId: interruptedRequest })).status, 503);
    assert.equal(r2.objects.size, 3);
    const recovered = await upload(another.body.id, bytes, { requestId: interruptedRequest });
    assert.equal(recovered.status, 201);
    assert.equal(recovered.body.document.currentRevision, 2);
    assert.equal(r2.objects.size, 3);
    database.transaction = originalTransaction;

    // A cleanup read cannot race ahead of a still-committing writer's metadata.
    const key = `synthetic-advisory-check/${randomUUID()}.png`;
    await f.client.query('BEGIN');
    const repository = f.app.get(EvidenceRepository);
    await repository.holdUpload(f.client, key);
    await f.client.query(`INSERT INTO sobatnira.intake_evidence
      (id, tenant_id, factory_id, document_id, request_id, request_hash, object_key, content_type, byte_size, sha256, width, height, uploaded_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'image/png', $8, $6, 32, 24, $9)`,
    [randomUUID(), f.ids.tenant, f.ids.factory, id, randomUUID(), createHash('sha256').update(bytes).digest('hex'), key, bytes.length, f.ids.admin]);
    let finished = false;
    const checking = repository.referenced(key).then((result) => { finished = true; return result; });
    await new Promise((done) => setTimeout(done, 50));
    assert.equal(finished, false);
    await f.client.query('COMMIT');
    assert.equal(await checking, true);
  } finally { await f.close(); await r2.close(); }
});
