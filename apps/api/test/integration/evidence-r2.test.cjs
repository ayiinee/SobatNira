const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const test = require('node:test');
const sharp = require('sharp');
const { intakeFixture } = require('./intake-fixture.cjs');
const { evidenceRequests } = require('./evidence-requests.cjs');
const { R2EvidenceStorage } = require('../../dist/evidence/r2-evidence.storage');
const { loadConfiguration } = require('../../dist/config/backend.config');

test('real R2 accepts a synthetic photo and serves its original bytes only through authorized backend access', async () => {
  const f = await intakeFixture(true);
  const { upload, content } = evidenceRequests(f);
  try {
    const bytes = await sharp({ create: { width: 48, height: 32, channels: 3, background: 'white' } }).png().toBuffer();
    const draft = await f.create();
    assert.equal(draft.status, 201);
    const photo = await upload(draft.body.id, bytes, { requestId: randomUUID() });
    assert.equal(photo.status, 201, JSON.stringify(photo.body));
    const image = await content(photo.body.evidence.contentPath);
    assert.equal(image.status, 200);
    assert.deepEqual(Buffer.from(await image.arrayBuffer()), bytes);
    assert.equal((await content(photo.body.evidence.contentPath, null)).status, 401);
    assert.equal((await content(photo.body.evidence.contentPath.replace(f.root, f.otherRoot))).status, 404);
    const publicBase = loadConfiguration().r2.publicProbeBaseUrl;
    if (publicBase) {
      const stored = await f.client.query('SELECT object_key FROM sobatnira.intake_evidence WHERE tenant_id = $1', [f.ids.tenant]);
      const anonymous = await fetch(new URL(stored.rows[0].object_key, new URL(publicBase).origin + '/'), { signal: AbortSignal.timeout(8000), redirect: 'error' });
      await anonymous.body?.cancel();
      assert.ok([401, 403, 404].includes(anonymous.status), 'Anonymous R2 access must be denied');
    }
    assert.equal((await f.request(f.root + '/intake-documents/' + draft.body.id + '/confirm-synthetic', 'POST', { expectedRevision: 2 })).status, 200);
    const approved = await f.request(f.root + '/intake-documents/' + draft.body.id + '/approve', 'POST', { expectedRevision: 2 });
    assert.equal(approved.status, 200);
    assert.equal(approved.body.evidence.id, photo.body.evidence.id);
  } finally {
    try {
      const objects = await f.client.query('SELECT object_key FROM sobatnira.intake_evidence WHERE tenant_id = $1', [f.ids.tenant]);
      for (const object of objects.rows) await f.app.get(R2EvidenceStorage).remove(object.object_key);
    } finally { await f.close(); }
  }
});
