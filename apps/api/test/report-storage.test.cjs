const assert = require('node:assert/strict');
const { Readable } = require('node:stream');
const { test } = require('node:test');
const { GetObjectCommand, PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { MediaStorage } = require('../dist/documents/media');
const { MAX_IMAGE_BYTES } = require('../dist/documents/contracts');

test('R2 transport keeps report artifacts private and rejects incomplete or oversized streams', async t => {
  const env = { R2_ENDPOINT: 'https://archive.r2.cloudflarestorage.com', R2_BUCKET_NAME: 'synthetic-private',
    R2_ACCESS_KEY_ID: 'fixture-key', R2_SECRET_ACCESS_KEY: 'fixture-secret' };
  const old = Object.fromEntries(Object.keys(env).map(key => [key, process.env[key]]));
  Object.assign(process.env, env);
  t.after(() => {
    for (const key of Object.keys(env)) {
      if (old[key] === undefined) delete process.env[key];
      else process.env[key] = old[key];
    }
  });
  const key = 'a'.repeat(64);
  const bytes = Buffer.from('synthetic PDF fixture');
  let body = bytes;
  let length = bytes.length;
  let existing = false;
  t.mock.method(S3Client.prototype, 'send', async (command, options) => {
    assert.ok(options.abortSignal);
    assert.equal(command.input.Bucket, 'synthetic-private');
    if (command instanceof PutObjectCommand) {
      assert.equal(command.input.Key, `reports/${key}`);
      assert.equal(command.input.CacheControl, 'private, no-store');
      assert.equal(command.input.IfNoneMatch, '*');
      assert.equal(command.input.ACL, undefined);
      if (existing) throw Object.assign(new Error('already exists'), { $metadata: { httpStatusCode: 412 } });
      return {};
    }
    assert.ok(command instanceof GetObjectCommand);
    assert.match(command.input.Key, new RegExp(`^(reports|originals)/${key}$`));
    return { ContentLength: length, Body: Readable.from([body]) };
  });
  const storage = new MediaStorage();
  await storage.put(key, 'application/pdf', bytes, 'reports');
  existing = true;
  await storage.put(key, 'application/pdf', bytes, 'reports');
  assert.deepEqual(await storage.read(key, 'reports'), bytes);
  assert.deepEqual(await storage.read(key), bytes);
  await assert.rejects(storage.put(key, 'application/pdf', Buffer.alloc(0), 'reports'), error => error.getStatus() === 400);
  length = MAX_IMAGE_BYTES + 1;
  await assert.rejects(storage.read(key, 'reports'), error => error.getStatus() === 503);
  length = bytes.length - 1;
  await assert.rejects(storage.read(key, 'reports'), error => error.getStatus() === 503);
  length = bytes.length;
  body = bytes.subarray(0, 2);
  await assert.rejects(storage.read(key, 'reports'), error => error.getStatus() === 503);
});
