const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createServer } = require('node:http');
const test = require('node:test');
const { NestFactory } = require('@nestjs/core');
const { AppModule } = require('../dist/app.module.js');

test('returns health and forwards a draft, then reports an upstream failure', async () => {
  const draft = { synthetic: true, lotCode: 'DEMO-261114-01' };
  const upstream = createServer((request, response) => {
    assert.equal(request.url, '/demo/draft');
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify(draft));
  });
  upstream.listen(0, '127.0.0.1');
  await once(upstream, 'listening');
  process.env.AI_BASE_URL = `http://127.0.0.1:${upstream.address().port}`;
  const api = await NestFactory.create(AppModule, { logger: false });
  try {
    await api.listen(0, '127.0.0.1');
    const url = await api.getUrl();
    const health = await fetch(`${url}/health`);
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), { status: 'ok', service: 'sobatnira-api' });
    const response = await fetch(`${url}/demo/draft`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), draft);
    upstream.close();
    await once(upstream, 'close');
    assert.equal((await fetch(`${url}/demo/draft`)).status, 503);
  } finally {
    upstream.close();
    await api.close();
    delete process.env.AI_BASE_URL;
  }
});
