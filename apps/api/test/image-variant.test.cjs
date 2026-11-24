const test = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const sharp = require('sharp');
const { renderImageVariant, imageVariant } = require('../dist/evidence/image-variant');
const { ImageWorkLimiter } = require('../dist/evidence/image-work');
const { validateEvidence } = require('../dist/evidence/evidence.validation');
const { pngHasAnimation } = require('../dist/evidence/png-animation');
const source = bytes => ({ sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length, mime: 'image/png' });

test('preview preserves raw pixel axes and normalized coordinates while removing EXIF and keeping original bytes', async () => {
  const svg = Buffer.from('<svg width="4000" height="2000"><rect width="4000" height="2000" fill="white"/><rect x="400" y="400" width="600" height="200" fill="red"/></svg>');
  const bytes = await sharp(svg).png().withMetadata({ orientation: 6 }).toBuffer();
  const original = await renderImageVariant(async () => bytes, source(bytes), 'original');
  assert.deepEqual(original.bytes, bytes);
  const preview = await renderImageVariant(async () => bytes, source(bytes), 'preview');
  const metadata = await sharp(preview.bytes).metadata();
  assert.equal(metadata.width, 2048); assert.equal(metadata.height, 1024);
  assert.equal(metadata.orientation, undefined); assert.equal(metadata.exif, undefined); assert.equal(metadata.icc, undefined);
  const pixel = await sharp(preview.bytes).extract({ left: Math.round(0.175 * 2048), top: Math.round(0.25 * 1024), width: 1, height: 1 }).raw().toBuffer();
  assert.ok(pixel[0] > 220 && pixel[1] < 30 && pixel[2] < 30);
  const thumbnail = await renderImageVariant(async () => bytes, source(bytes), 'thumbnail');
  assert.equal(thumbnail.width, 320); assert.equal(thumbnail.height, 160);
  await assert.rejects(renderImageVariant(async () => bytes, { ...source(bytes), sha256: '0'.repeat(64) }, 'preview'), /Integritas/);
});

test('variants reject malformed source and parameter values and never upscale small images', async () => {
  const bytes = await sharp({ create: { width: 32, height: 24, channels: 3, background: 'white' } }).png().toBuffer();
  const result = await renderImageVariant(async () => bytes, source(bytes), 'preview');
  assert.equal(result.width, 32); assert.equal(result.height, 24);
  assert.equal(imageVariant({}), 'original'); assert.equal(imageVariant({ variant: 'thumbnail' }), 'thumbnail');
  for (const query of [{ variant: ['preview'] }, { variant: 'bad' }, { other: 'preview' }]) assert.throws(() => imageVariant(query));
  const corrupt = bytes.subarray(0, 40);
  await assert.rejects(renderImageVariant(async () => corrupt, source(corrupt), 'preview'), /belum dapat dibuat/);
});

test('image work bounds concurrent storage reads, rejects overload and recovers after failures', async () => {
  const limiter = new ImageWorkLimiter(1, 1);
  let release, entered;
  const ready = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  const first = limiter.run(async () => { entered(); await gate; throw new Error('fixture failure'); });
  first.catch(() => {}); await ready;
  let secondEntered = false;
  const second = limiter.run(async () => { secondEntered = true; return 2; });
  assert.equal(secondEntered, false);
  assert.deepEqual(limiter.statistics(), { active: 1, waiting: 1 });
  await assert.rejects(limiter.run(async () => 3), error => error.getStatus() === 503);
  release(); await assert.rejects(first); assert.equal(await second, 2);
  assert.deepEqual(limiter.statistics(), { active: 0, waiting: 0 });
});

test('animated WebP is rejected by both shared upload validation and variant processing', async () => {
  const pixels = Buffer.alloc(600);
  for (let i = 0; i < 200; i++) pixels[i * 3 + (i < 100 ? 0 : 2)] = 255;
  const bytes = await sharp(pixels, { raw: { width: 10, height: 20, channels: 3, pageHeight: 10 } })
    .webp({ lossless: true, loop: 0, delay: [100, 100] }).toBuffer();
  assert.equal((await sharp(bytes).metadata()).pages, 2);
  await assert.rejects(validateEvidence({ buffer: bytes, mimetype: 'image/webp', size: bytes.length }), error => error.getStatus() === 400);
  await assert.rejects(renderImageVariant(async () => bytes, { ...source(bytes), mime: 'image/webp' }, 'preview'), error => error.getStatus() === 503);
});

test('PNG animation control chunks are detected even if the decoder only reports a first frame', async () => {
  const bytes = await sharp({ create: { width: 2, height: 2, channels: 3, background: 'white' } }).png().toBuffer();
  const animation = Buffer.alloc(20);
  animation.writeUInt32BE(8); animation.write('acTL', 4); animation.writeUInt32BE(2, 8);
  const apng = Buffer.concat([bytes.subarray(0, 33), animation, bytes.subarray(33)]);
  assert.equal(pngHasAnimation(bytes), false); assert.equal(pngHasAnimation(apng), true);
  await assert.rejects(validateEvidence({ buffer: apng, mimetype: 'image/png', size: apng.length }), error => error.getStatus() === 400 && /statis/.test(error.message));
});
