const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createServer } = require('node:http');
const net = require('node:net');
const test = require('node:test');
const { loadConfiguration } = require('../dist/config/backend.config.js');
const { checkConnections, createConnectionProbes } = require('../dist/connections/connection-checks.js');

async function listen(server) {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return server.address().port;
}

test('checks Auth keys, signed R2 bucket access and FastAPI using read-only HTTP requests', async () => {
  const seenKeys = [];
  const server = createServer((req, res) => {
    if (req.url === '/auth/v1/settings') {
      assert.equal(req.method, 'GET');
      seenKeys.push(req.headers.apikey);
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ external: { email: true } }));
    } else if (req.url === '/health') {
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ status: 'ok', service: 'sobatnira-ai' }));
    } else {
      assert.equal(req.method, 'HEAD');
      assert.ok(req.url.startsWith('/synthetic-bucket'));
      assert.match(req.headers.authorization, /^AWS4-HMAC-SHA256 /);
      res.end();
    }
  });
  const port = await listen(server);
  try {
    const endpoint = `http://127.0.0.1:${port}`;
    const config = loadConfiguration({ envFile: false, env: {
      AI_BASE_URL: endpoint, SUPABASE_URL: endpoint,
      SUPABASE_PUBLISHABLE_KEY: 'synthetic-publishable', SUPABASE_SECRET_KEY: 'synthetic-secret',
      R2_ENDPOINT: endpoint, R2_BUCKET_NAME: 'synthetic-bucket',
      R2_ACCESS_KEY_ID: 'synthetic-access', R2_SECRET_ACCESS_KEY: 'synthetic-secret',
    } });
    const results = await checkConnections(config);
    for (const name of ['supabase', 'r2', 'fastapi']) {
      assert.equal(results.find((item) => item.service === name).status, 'ok');
    }
    assert.equal(results.find((item) => item.service === 'postgresql').status, 'not_configured');
    assert.equal(results.find((item) => item.service === 'redis').status, 'not_configured');
    assert.deepEqual(seenKeys, ['synthetic-publishable', 'synthetic-secret']);
    assert.ok(!JSON.stringify(results).includes('synthetic-secret'));
  } finally { server.closeAllConnections(); await new Promise((done) => server.close(done)); }
});

test('HTTP failures, wrong service payloads and timeouts are failures without leaking bodies', async () => {
  let mode = 'unauthorized';
  const server = createServer((_req, res) => {
    if (mode === 'timeout') return;
    res.setHeader('content-type', 'application/json');
    if (mode === 'unauthorized') res.writeHead(401);
    res.end(JSON.stringify({ secret: 'synthetic-secret-never-log', status: 'ok', service: 'another-app' }));
  });
  const port = await listen(server);
  const config = loadConfiguration({ envFile: false, env: {
    AI_BASE_URL: `http://127.0.0.1:${port}`, CONNECTION_TIMEOUT_MS: '100',
  } });
  try {
    for (mode of ['unauthorized', 'wrong-service', 'timeout']) {
      const result = (await checkConnections(config)).find((item) => item.service === 'fastapi');
      assert.equal(result.status, 'failed', mode);
      assert.ok(!JSON.stringify(result).includes('synthetic-secret-never-log'));
    }
  } finally { server.closeAllConnections(); await new Promise((done) => server.close(done)); }
});

test('one failed service does not hide the rest, and arbitrary provider errors are redacted', async () => {
  const config = loadConfiguration({ envFile: false, env: {} });
  const results = await checkConnections(config, {
    postgresql: async () => { throw Object.assign(new Error('postgres://user:secret@private-host/db'), { code: '28P01' }); },
    redis: async () => { throw new Error('WRONGPASS secret at private-host'); },
    fastapi: async () => {},
  });
  assert.equal(results.find((item) => item.service === 'fastapi').status, 'ok');
  assert.match(results.find((item) => item.service === 'postgresql').message, /Autentikasi PostgreSQL ditolak/);
  assert.ok(!JSON.stringify(results).includes('private-host'));
  assert.ok(!JSON.stringify(results).includes('secret'));
});

test('Redis probe authenticates, pings, and closes its connection without writing keys', async () => {
  const commands = [];
  const sockets = new Set();
  const server = net.createServer((socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    let buffer = '';
    socket.on('data', (data) => {
      buffer += data.toString();
      while (buffer.length) {
        const match = /^\*(\d+)\r\n/.exec(buffer);
        if (!match) return;
        let offset = match[0].length;
        const args = [];
        for (let index = 0; index < Number(match[1]); index++) {
          const length = /^\$(\d+)\r\n/.exec(buffer.slice(offset));
          if (!length) return;
          offset += length[0].length;
          const end = offset + Number(length[1]);
          if (buffer.length < end + 2) return;
          args.push(buffer.slice(offset, end));
          offset = end + 2;
        }
        buffer = buffer.slice(offset);
        commands.push(args);
        socket.write(args[0].toUpperCase() === 'PING' ? '+PONG\r\n' : '+OK\r\n');
      }
    });
  });
  const port = await listen(server);
  try {
    const config = loadConfiguration({ envFile: false, env: {
      REDIS_URL: `redis://default:synthetic@127.0.0.1:${port}`, CONNECTION_TIMEOUT_MS: '1000',
    } });
    await createConnectionProbes(config).redis();
    assert.ok(commands.some((args) => args[0].toUpperCase() === 'AUTH' ||
      (args[0].toUpperCase() === 'HELLO' && args.includes('AUTH') && args.includes('synthetic'))));
    assert.ok(commands.some((args) => args[0].toUpperCase() === 'PING'));
    assert.ok(commands.every((args) => ['AUTH', 'HELLO', 'CLIENT', 'PING'].includes(args[0].toUpperCase())));
  } finally {
    for (const socket of sockets) socket.destroy();
    await new Promise((done) => server.close(done));
  }
});

test('Redis connection failure is bounded and does not leave retrying clients', async () => {
  const server = net.createServer();
  const port = await listen(server);
  await new Promise((done) => server.close(done));
  const config = loadConfiguration({ envFile: false, env: {
    REDIS_URL: `redis://127.0.0.1:${port}`, CONNECTION_TIMEOUT_MS: '100',
  } });
  const result = (await checkConnections(config, { redis: createConnectionProbes(config).redis }))[3];
  assert.equal(result.status, 'failed');
  assert.ok(result.durationMs < 2000);
});
