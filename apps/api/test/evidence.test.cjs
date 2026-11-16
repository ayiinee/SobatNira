const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const test = require('node:test');
const sharp = require('sharp');
const { BadRequestException, PayloadTooLargeException, ServiceUnavailableException } = require('@nestjs/common');
const { validateEvidence, parseEvidenceUpload } = require('../dist/evidence/evidence.validation');
const { MAX_EVIDENCE_BYTES } = require('../dist/evidence/evidence.types');
const { R2EvidenceStorage } = require('../dist/evidence/r2-evidence.storage');
const { loadConfiguration } = require('../dist/config/backend.config');
const { r2Fixture } = require('./helpers/r2-fixture.cjs');

test('photos are fully decoded, hashed and preserved as original JPEG/PNG/WebP bytes', async () => {
  for (const [format, mime] of [['jpeg', 'image/jpeg'], ['png', 'image/png'], ['webp', 'image/webp']]) {
    const bytes = await sharp({ create: { width: 24, height: 16, channels: 3, background: '#ffffff' } })[format]().toBuffer();
    const result = await validateEvidence({ buffer: bytes, size: bytes.length, mimetype: mime });
    assert.deepEqual(result.bytes, bytes);
    assert.equal(result.sha256, createHash('sha256').update(bytes).digest('hex'));
    assert.equal(result.width, 24);
    assert.equal(result.height, 16);
    assert.equal(result.contentType, mime);
  }
});

test('missing, oversized, corrupt and disguised non-image files are refused', async () => {
  await assert.rejects(validateEvidence(), BadRequestException);
  await assert.rejects(validateEvidence({ buffer: Buffer.alloc(MAX_EVIDENCE_BYTES + 1), mimetype: 'image/png' }), PayloadTooLargeException);
  for (const bytes of [Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>'), Buffer.from('<script>synthetic</script>'), Buffer.from([255, 216, 255, 0])]) {
    await assert.rejects(validateEvidence({ buffer: bytes, size: bytes.length, mimetype: 'image/png' }), BadRequestException);
  }
  const bytes = await sharp({ create: { width: 16, height: 16, channels: 3, background: 'white' } }).png().toBuffer();
  await assert.rejects(validateEvidence({ buffer: bytes, size: bytes.length, mimetype: 'image/jpeg' }), BadRequestException);
  await assert.rejects(validateEvidence({ buffer: bytes.subarray(0, 32), size: 32, mimetype: 'image/png' }), BadRequestException);
});

test('images above the pixel limit are refused before they can enter storage', async () => {
  const bytes = await sharp({ create: { width: 5000, height: 5000, channels: 3, background: 'white' } }).png().toBuffer();
  await assert.rejects(validateEvidence({ buffer: bytes, size: bytes.length, mimetype: 'image/png' }), BadRequestException);
});

test('multipart metadata requires revision, reason and request UUID, without accepting object keys', () => {
  const fields = { requestId: '50000000-0000-4000-8000-000000000001', expectedRevision: '1', reason: ' Synthetic photo ' };
  assert.deepEqual(parseEvidenceUpload(fields), { ...fields, expectedRevision: 1, reason: 'Synthetic photo' });
  for (const invalid of [{ ...fields, objectKey: 'other-tenant/photo.png' }, { ...fields, expectedRevision: '1e2' }, { ...fields, reason: '' }]) {
    assert.throws(() => parseEvidenceUpload(invalid), BadRequestException);
  }
});

test('R2 privacy checks reject an anonymous public bucket and always remove their marker', async () => {
  const fake = await r2Fixture();
  const storage = new R2EvidenceStorage(loadConfiguration({ envFile: false, env: fake.env }));
  try {
    fake.state.public = true;
    await assert.rejects(storage.assertPrivate(), ServiceUnavailableException);
    assert.equal(fake.objects.size, 0);
    fake.state.public = false;
    await storage.assertPrivate();
    assert.equal(fake.objects.size, 0);
    assert.ok(fake.calls.every((call) => call.key.startsWith('privacy-checks/')));
  } finally { storage.onModuleDestroy(); await fake.close(); }
});

test('R2 photo reads validate length, MIME and SHA-256 before returning any bytes', async () => {
  const fake = await r2Fixture();
  const storage = new R2EvidenceStorage(loadConfiguration({ envFile: false, env: fake.env }));
  try {
    const bytes = await sharp({ create: { width: 16, height: 16, channels: 3, background: 'white' } }).png().toBuffer();
    const image = await validateEvidence({ buffer: bytes, size: bytes.length, mimetype: 'image/png' });
    const key = 'synthetic/evidence/fixture.png';
    await storage.put(key, image);
    const evidence = { objectKey: key, contentType: image.contentType, byteSize: image.byteSize, sha256: image.sha256 };
    assert.deepEqual(await storage.read(evidence), bytes);
    const altered = Buffer.from(bytes); altered[altered.length - 1] ^= 1;
    fake.objects.get(key).bytes = altered;
    await assert.rejects(storage.read(evidence), ServiceUnavailableException);
    fake.objects.get(key).bytes = bytes.subarray(0, bytes.length - 1);
    await assert.rejects(storage.read(evidence), ServiceUnavailableException);
    await storage.remove(key);
  } finally { storage.onModuleDestroy(); await fake.close(); }
});
