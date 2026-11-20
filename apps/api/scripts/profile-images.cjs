const { readFile, mkdir, writeFile } = require('node:fs/promises');
const { resolve } = require('node:path');
const { performance } = require('node:perf_hooks');
const { createHash } = require('node:crypto');
const sharp = require('sharp');
const { renderImageVariant, IMAGE_TRANSFORM_VERSION } = require('../dist/evidence/image-variant');

async function main() {
  const output = resolve(__dirname, '../../../.tmp/performance/images');
  await mkdir(output, { recursive: true });
  const results = [];
  for (const name of ['truck', 'production', 'manual', 'update']) {
    const bytes = await readFile(resolve(__dirname, '../../ai/fixtures/acceptance', name + '.png'));
    const source = { sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length, mime: 'image/png' };
    const pixels = await sharp(bytes).raw().toBuffer();
    for (const variant of ['preview', 'thumbnail']) {
      const start = performance.now();
      const result = await renderImageVariant(async () => bytes, source, variant);
      const elapsedMs = performance.now() - start;
      const metadata = await sharp(result.bytes).metadata();
      const samePixels = variant === 'preview' && (await sharp(result.bytes).raw().toBuffer()).equals(pixels);
      await writeFile(resolve(output, `${name}-${variant}.webp`), result.bytes);
      results.push({ name, variant, originalBytes: bytes.length, bytes: result.bytes.length,
        width: metadata.width, height: metadata.height, elapsedMs, samePixels,
        rssAfterBytes: process.memoryUsage().rss });
    }
  }
  await writeFile(resolve(output, 'profile.json'), JSON.stringify({ version: IMAGE_TRANSFORM_VERSION,
    note: 'Synthetic fixtures, one local run; RSS after each transform is not peak RAM; no network latency or handwritten accuracy claim.', results }, null, 2));
  console.log(JSON.stringify({ output, results }));
}
main().catch(() => { console.error('Image profiling failed'); process.exitCode = 1; });
