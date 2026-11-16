const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createServer } = require('node:http');
const test = require('node:test');
const { createApplication } = require('../dist/application.js');

test('returns health and forwards a draft, then reports an upstream failure', async () => {
  const draft = { synthetic: true, lotCode: 'DEMO-261114-01' };
  const upstream = createServer((request, response) => {
    assert.equal(request.url, '/demo/draft');
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify(draft));
  });
  upstream.listen(0, '127.0.0.1');
  await once(upstream, 'listening');
  const api = await createApplication({ envFile: false, env: {
    AI_BASE_URL: `http://127.0.0.1:${upstream.address().port}`, LOG_LEVEL: 'silent',
    CORS_ORIGINS: 'http://localhost:8080',
  } });
  try {
    await api.listen(0, '127.0.0.1');
    const url = await api.getUrl();
    const health = await fetch(`${url}/health`);
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), { status: 'ok', service: 'sobatnira-api' });
    const allowed = await fetch(`${url}/health`, { headers: { Origin: 'http://localhost:8080' } });
    assert.equal(allowed.headers.get('access-control-allow-origin'), 'http://localhost:8080');
    const denied = await fetch(`${url}/health`, { headers: { Origin: 'http://untrusted.invalid' } });
    assert.equal(denied.headers.get('access-control-allow-origin'), null);
    const response = await fetch(`${url}/demo/draft`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), draft);
    upstream.close();
    await once(upstream, 'close');
    assert.equal((await fetch(`${url}/demo/draft`)).status, 503);
  } finally {
    upstream.close();
    await api.close();
  }
});

test('returns 503 within the configured AI timeout when upstream does not respond', async () => {
  const upstream = createServer(() => {});
  upstream.listen(0, '127.0.0.1');
  await once(upstream, 'listening');
  const api = await createApplication({ envFile: false, env: {
    AI_BASE_URL: `http://127.0.0.1:${upstream.address().port}`,
    AI_TIMEOUT_MS: '100', LOG_LEVEL: 'silent',
  } });
  try {
    await api.listen(0, '127.0.0.1');
    const start = performance.now();
    const response = await fetch(`${await api.getUrl()}/demo/draft`);
    assert.equal(response.status, 503);
    assert.ok(performance.now() - start < 2000);
  } finally {
    upstream.closeAllConnections();
    await new Promise((done) => upstream.close(done));
    await api.close();
  }
});
