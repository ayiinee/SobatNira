const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtemp, writeFile, mkdir, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { reviewObject } = require('../dist/storage/storage-audit');
const { audit, localInventory, r2Inventory } = require('../scripts/audit-storage.cjs');
const key = 'originals/' + 'a'.repeat(64);
const now = new Date('2026-11-21T00:00:00Z');
const object = { key, bytes: 123, modifiedAt: '2026-10-01T00:00:00Z' };

test('storage review preserves historical references, active attempts, unknown paths and uncertain age', () => {
  assert.equal(reviewObject(object, [], now, 168).state, 'review_candidate');
  for (const source of ['media_asset', 'intake_evidence', 'upload_attached', 'report_artifact', 'report_job_FAILED']) {
    const result = reviewObject(object, [{ key, source }], now, 168);
    assert.equal(result.state, 'protected_reference'); assert.equal(result.deletionAllowed, false);
  }
  assert.equal(reviewObject(object, [{ key, source: 'upload_unattached', lastAttemptAt: now.toISOString() }], now, 168).state, 'protected_recent_or_unknown_age');
  for (const modifiedAt of [null, 'invalid', '2026-11-22T00:00:00Z']) {
    assert.equal(reviewObject({ ...object, modifiedAt }, [], now, 168).state, 'protected_recent_or_unknown_age');
  }
  assert.equal(reviewObject({ ...object, key: 'misc/unknown' }, [], now, 168).state, 'protected_unknown');
});

test('inventory pagination uses ListObjects only and never downloads/deletes objects', async () => {
  const commands = [];
  const client = { send: async command => {
    commands.push(command);
    return command.input.ContinuationToken ? { Contents: [{ Key: key, Size: 123 }] } :
      { Contents: [{ Key: 'unknown', Size: 1 }], IsTruncated: true, NextContinuationToken: 'next' };
  } };
  const objects = [];
  for await (const item of r2Inventory(client, 'fixture')) objects.push(item);
  assert.equal(objects.length, 2);
  assert.deepEqual(commands.map(command => command.constructor.name), ['ListObjectsV2Command', 'ListObjectsV2Command']);
  assert.equal(commands[1].input.ContinuationToken, 'next');
  await assert.rejects(async () => { for await (const item of r2Inventory({ send: async () => ({ IsTruncated: true }) }, 'fixture')) {} });
});

test('audit bounds work, reports incomplete inventory and aborts on missing reference sources', async () => {
  const statements = [], output = [];
  const db = { query: async sql => { statements.push(sql); return { rows: [] }; } };
  async function* objects() { yield object; yield { ...object, key: 'reports/' + 'b'.repeat(64) }; }
  const summary = await audit({ inventory: objects(), db, write: async row => output.push(row), now, ageHours: 168, maxObjects: 1 });
  assert.equal(summary.complete, false); assert.equal(summary.candidateBytes, 123); assert.equal(summary.deletionAllowed, false);
  assert.equal(output.length, 2);
  assert.ok(statements[0].includes('READ ONLY'));
  assert.ok(statements.at(-1) === 'COMMIT');
  assert.ok(statements.every(sql => !/\b(DELETE|UPDATE|INSERT)\b/.test(sql)));
  const broken = { query: async sql => { if (sql.includes('SELECT')) throw new Error('missing schema'); return { rows: [] }; } };
  await assert.rejects(audit({ inventory: objects(), db: broken, write: async () => {}, now, ageHours: 168, maxObjects: 10 }), /missing schema/);
});

test('local inventory recognizes actual MediaStorage layout and preserves unrelated directories', async () => {
  const root = await mkdtemp(join(tmpdir(), 'sobatnira-audit-'));
  try {
    await mkdir(join(root, 'reports')); await mkdir(join(root, 'unrelated'));
    await writeFile(join(root, 'a'.repeat(64)), 'original');
    await writeFile(join(root, 'reports', 'b'.repeat(64)), 'report');
    await writeFile(join(root, 'unrelated', 'private'), 'do not traverse');
    const objects = [];
    for await (const item of localInventory(root)) objects.push(item);
    assert.deepEqual(objects.map(item => item.key).sort(), [key, 'reports/' + 'b'.repeat(64), 'unrecognized-local/unrelated'].sort());
    assert.equal(objects.find(item => item.key === key).bytes, 8);
  } finally { await rm(root, { recursive: true, force: true }); }
});
