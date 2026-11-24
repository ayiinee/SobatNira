const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID, createHash } = require('node:crypto');
const { readFile, readdir } = require('node:fs/promises');
const { resolve } = require('node:path');
const { intakeFixture } = require('./intake-fixture.cjs');
const { objectReferences, reviewObject } = require('../../dist/storage/storage-audit');

test('storage audit resolves historical evidence, unattached upload attempts and deterministic export keys in PostgreSQL', async () => {
  const f = await intakeFixture();
  try {
    // The isolated fixture rolls back schema and data; never migrate a shared database here.
    const installed = await f.client.query("SELECT to_regclass('public.media_assets') AS name");
    if (!installed.rows[0].name) {
      const directory = resolve(__dirname, '../../migrations/ocr');
      for (const file of (await readdir(directory)).filter(name => /^\d+.*\.sql$/.test(name)).sort()) {
        await f.client.query(await readFile(resolve(directory, file), 'utf8'));
      }
    }
    const media = 'c'.repeat(64), upload = 'd'.repeat(64);
    await f.client.query(`INSERT INTO public.media_assets(factory_id,object_key,mime_type,size_bytes,sha256)
      VALUES ($1,$2,'image/png',123,$2)`, [f.ids.factory, media]);
    await f.client.query(`INSERT INTO public.media_uploads(object_key,factory_id,mime_type,size_bytes,sha256)
      VALUES ($1,$2,'image/png',123,$1)`, [upload, f.ids.factory]);
    const document = (await f.create()).body;
    const id = randomUUID();
    const evidence = `tenants/${f.ids.tenant}/factories/${f.ids.factory}/intake-documents/${document.id}/evidence/${id}.png`;
    // An evidence row unattached to the current revision is still protected.
    await f.client.query(`INSERT INTO sobatnira.intake_evidence
      (id,tenant_id,factory_id,document_id,request_id,request_hash,object_key,content_type,byte_size,sha256,width,height,uploaded_by)
      VALUES ($1,$2,$3,$4,$5,$6,$7,'image/png',123,$6,10,10,$8)`,
    [id, f.ids.tenant, f.ids.factory, document.id, randomUUID(), 'e'.repeat(64), evidence, f.ids.admin]);
    const reportId = randomUUID(), key = createHash('sha256').update(reportId + ':pdf').digest('hex');
    await f.client.query(`INSERT INTO sobatnira.report_exports
      (id,tenant_id,factory_id,requested_by,idempotency_key,input_hash,snapshot,status)
      VALUES ($1,$2,$3,$4,$5,'fixture','{}','FAILED')`,
    [reportId, f.ids.tenant, f.ids.factory, f.ids.owner, randomUUID()]);
    const artifactId = randomUUID(), artifactKey = 'f'.repeat(64);
    await f.client.query(`INSERT INTO sobatnira.report_exports
      (id,tenant_id,factory_id,requested_by,idempotency_key,input_hash,snapshot,status,artifacts)
      VALUES ($1,$2,$3,$4,$5,'fixture','{}','READY',$6)`,
    [artifactId, f.ids.tenant, f.ids.factory, f.ids.owner, randomUUID(), JSON.stringify({ pdf: { key: artifactKey, sha256: media } })]);
    const keys = ['originals/' + media, 'originals/' + upload, evidence, 'reports/' + key, 'reports/' + artifactKey];
    const refs = await objectReferences(f.client, keys);
    for (const objectKey of keys) {
      const result = reviewObject({ key: objectKey, bytes: 123, modifiedAt: '2020-01-01T00:00:00Z' },
        refs.filter(ref => ref.key === objectKey), new Date(), 168);
      assert.notEqual(result.state, 'review_candidate', JSON.stringify(result));
      assert.equal(result.deletionAllowed, false);
    }
    assert.ok(refs.some(ref => ref.source === 'report_artifact'));
    assert.ok(refs.some(ref => ref.source === 'report_job_FAILED'));
    assert.ok(refs.some(ref => ref.source === 'upload_unattached' && ref.lastAttemptAt));
  } finally { await f.close(); }
});
