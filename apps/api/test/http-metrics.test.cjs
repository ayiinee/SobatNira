const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { createApplication } = require('../dist/application');
const { DurationHistogram } = require('../dist/metrics/durations');
const { HttpMeasurements } = require('../dist/metrics/http-measurements');

test('bounded histogram reports percentile upper bounds without retaining samples', () => {
  const h = new DurationHistogram();
  for (const value of [1, 2, 7, 50, 99, NaN, Infinity, -1]) h.observe(value);
  const stats = h.snapshot();
  assert.equal(stats.count, 5); assert.equal(stats.p50UpperBoundMs, 10);
  assert.equal(stats.p95UpperBoundMs, 100); assert.equal(stats.p99UpperBoundMs, 100);
  assert.equal(stats.buckets.reduce((sum, bucket) => sum + bucket.count, 0), 5);
  h.observe(600000); assert.equal(h.snapshot().p99UpperBoundMs, null);
});

test('HTTP measurements count responses, bytes and errors without logging URL input or tokens', async () => {
  const app = await createApplication({ envFile: false, env: { LOG_LEVEL: 'silent' } });
  try {
    await app.listen(0, '127.0.0.1'); const base = await app.getUrl();
    const health = await fetch(base + '/health?private-token=secret', { headers: { Authorization: 'Bearer private-token' } });
    const bytes = Buffer.byteLength(await health.text());
    const missing = await fetch(base + '/private-client-value?token=private-token'); await missing.text();
    const stats = app.get(HttpMeasurements).snapshot();
    const success = stats.find(row => row.route === 'GET /health');
    assert.equal(success.responses, 1); assert.equal(success.knownBodyBytes, bytes); assert.equal(success.errors, 0);
    assert.equal(success.durationMs.count, 1);
    assert.equal(stats.find(row => row.route.includes('<unmatched>')).errors, 1);
    assert.ok(!JSON.stringify(stats).includes('private-client-value')); assert.ok(!JSON.stringify(stats).includes('private-token'));
  } finally { await app.close(); }
});

test('HTTP metrics cap label cardinality and count aborted/unknown-length streams once', () => {
  const m = new HttpMeasurements();
  try {
    for (let n = 0; n < 300; n++) {
      const response = new EventEmitter(); response.statusCode = 200; response.getHeader = () => undefined;
      m.middleware({ method: 'GET', route: { path: '/pattern-' + n } }, response, () => {});
      response.emit('close'); response.emit('finish');
    }
    const stats = m.snapshot();
    assert.equal(stats.length, 256); assert.equal(stats.reduce((sum, row) => sum + row.responses, 0), 300);
    assert.equal(stats.reduce((sum, row) => sum + row.aborted, 0), 300);
    assert.equal(stats.reduce((sum, row) => sum + row.unknownBodyResponses, 0), 300);
  } finally { m.onModuleDestroy(); }
});
