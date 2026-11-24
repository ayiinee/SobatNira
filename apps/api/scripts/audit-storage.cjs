// No Put/Delete/Update commands: this CLI only inventories and writes a local report.
const { createWriteStream } = require('node:fs');
const { mkdir, rename, opendir, lstat } = require('node:fs/promises');
const { resolve, join } = require('node:path');
const { randomUUID } = require('node:crypto');
const { Client } = require('pg');
const { S3Client, ListObjectsV2Command } = require('@aws-sdk/client-s3');
const { loadConfiguration } = require('../dist/config/backend.config');
const { postgresClientOptions } = require('../dist/database/postgres.config');
const { objectReferences, reviewObject, AUDIT_VERSION } = require('../dist/storage/storage-audit');

async function* localInventory(root) {
  // MediaStorage uses root/<hash> for originals and root/reports/<hash>.
  // Never follow symlinks or traverse unrelated directories.
  for await (const item of await opendir(root)) {
    const path = join(root, item.name), info = await lstat(path);
    if (item.isDirectory() && !info.isSymbolicLink() && item.name === 'reports') {
      for await (const entry of await opendir(path)) {
        const child = await lstat(join(path, entry.name));
        yield { key: `reports/${entry.name}`, bytes: child.isFile() ? child.size : 0,
          modifiedAt: child.isFile() && !child.isSymbolicLink() ? child.mtime.toISOString() : null };
      }
    } else {
      yield { key: /^[a-f0-9]{64}$/.test(item.name) && info.isFile() && !info.isSymbolicLink()
        ? `originals/${item.name}` : `unrecognized-local/${item.name}`,
        bytes: info.isFile() ? info.size : 0, modifiedAt: info.isFile() && !info.isSymbolicLink() ? info.mtime.toISOString() : null };
    }
  }
}

async function* r2Inventory(client, bucket) {
  let token;
  do {
    const page = await client.send(new ListObjectsV2Command({ Bucket: bucket, MaxKeys: 200, ContinuationToken: token }),
      { abortSignal: AbortSignal.timeout(15_000) });
    for (const object of page.Contents ?? []) {
      if (!object.Key || object.Size === undefined) throw new Error('Incomplete object metadata');
      yield { key: object.Key, bytes: object.Size, modifiedAt: object.LastModified?.toISOString() ?? null };
    }
    if (page.IsTruncated && !page.NextContinuationToken) throw new Error('Incomplete bucket pagination');
    token = page.IsTruncated ? page.NextContinuationToken : undefined;
  } while (token);
}

async function audit({ inventory, db, write, now, ageHours, maxObjects }) {
  const totals = { objects: 0, bytes: 0, candidateObjects: 0, candidateBytes: 0, categories: {} };
  let batch = [], complete = true;
  async function flush() {
    if (!batch.length) return;
    // Do not keep a transaction open while listing R2 or writing output.
    await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    let refs;
    try { refs = await objectReferences(db, batch.map(object => object.key)); await db.query('COMMIT'); }
    catch (error) { await db.query('ROLLBACK').catch(() => {}); throw error; }
    for (const object of batch) {
      const result = reviewObject(object, refs.filter(ref => ref.key === object.key), now, ageHours);
      totals.objects++; totals.bytes += object.bytes;
      totals.categories[result.category] = (totals.categories[result.category] ?? 0) + 1;
      if (result.state === 'review_candidate') { totals.candidateObjects++; totals.candidateBytes += object.bytes; }
      await write({ type: 'object', ...result });
    }
    batch = [];
  }
  for await (const object of inventory) {
    if (totals.objects + batch.length >= maxObjects) { complete = false; break; }
    batch.push(object);
    if (batch.length === 200) await flush();
  }
  await flush();
  const summary = { type: 'summary', dryRun: true, deletionAllowed: false, complete,
    policyVersion: AUDIT_VERSION, sampledAt: now.toISOString(), candidateAgeHours: ageHours, ...totals };
  await write(summary);
  return summary;
}

async function main() {
  const ageHours = Number(process.env.STORAGE_AUDIT_AGE_HOURS ?? 168);
  const maxObjects = Number(process.env.STORAGE_AUDIT_MAX_OBJECTS ?? 10000);
  if (!Number.isSafeInteger(ageHours) || ageHours < 1 || !Number.isSafeInteger(maxObjects) || maxObjects < 1 || maxObjects > 1000000) {
    throw new Error('Invalid audit limits');
  }
  const config = loadConfiguration({ envFile: false });
  if (!config.postgres) throw new Error('Database configuration required');
  const mode = process.env.STORAGE_AUDIT_SOURCE;
  if (!['local', 'r2'].includes(mode)) throw new Error('Set STORAGE_AUDIT_SOURCE=local or r2 explicitly');
  if (mode === 'local' && (!process.env.DOCUMENT_MEDIA_DIR || config.r2)) throw new Error('Local audit requires only DOCUMENT_MEDIA_DIR');
  if (mode === 'r2' && !config.r2) throw new Error('R2 configuration required');
  const db = new Client({ ...postgresClientOptions(config), application_name: 'sobatnira-storage-audit',
    options: '-c default_transaction_read_only=on' });
  const r2 = mode === 'r2' ? new S3Client({ endpoint: config.r2.endpoint, region: config.r2.region,
    forcePathStyle: true, maxAttempts: 2,
    credentials: { accessKeyId: config.r2.accessKeyId, secretAccessKey: config.r2.secretAccessKey } }) : undefined;
  const directory = resolve(__dirname, '../../../.tmp/storage-audit');
  await mkdir(directory, { recursive: true });
  const output = join(directory, `${new Date().toISOString().replace(/[:.]/g, '-')}-${randomUUID()}.jsonl`);
  const stream = createWriteStream(output + '.partial', { flags: 'wx', mode: 0o600 });
  // Register before first write; a filesystem failure must abort the audit.
  const finished = new Promise((resolve, reject) => { stream.once('finish', resolve); stream.once('error', reject); });
  finished.catch(() => {});
  try {
    await db.connect();
    const summary = await audit({ inventory: r2 ? r2Inventory(r2, config.r2.bucket) : localInventory(resolve(process.env.DOCUMENT_MEDIA_DIR)),
      db, now: new Date(), ageHours, maxObjects,
      write: row => new Promise((resolve, reject) => stream.write(JSON.stringify(row) + '\n', error => error ? reject(error) : resolve())) });
    stream.end(); await finished;
    await rename(output + '.partial', output);
    console.log(JSON.stringify({ output, ...summary }));
    if (!summary.complete) process.exitCode = 2;
  } finally { stream.destroy(); r2?.destroy(); await db.end(); }
}

module.exports = { audit, localInventory, r2Inventory };
if (require.main === module) main().catch(() => { console.error('Storage audit failed; partial output is not a complete inventory. Check configuration, schema, access and connectivity.'); process.exitCode = 1; });
