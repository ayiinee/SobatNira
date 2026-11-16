const { createServer } = require('node:http');
const { once } = require('node:events');

async function r2Fixture() {
  const objects = new Map();
  const calls = [];
  const state = { public: false, failPut: false, failGet: false };
  const server = createServer(async (req, res) => {
    const path = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const signed = req.headers.authorization?.startsWith('AWS4-HMAC-SHA256 ');
    const key = signed ? path.replace(/^\/synthetic-bucket\//, '') : path.slice(1);
    calls.push({ method: req.method, signed: !!signed, key });
    if (!signed) {
      if (state.public && objects.has(key)) { res.writeHead(200); res.end(objects.get(key).bytes); }
      else { res.writeHead(401); res.end(); }
      return;
    }
    if (req.method === 'PUT') {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      if (state.failPut && key.includes('/evidence/')) { res.writeHead(503); res.end(); return; }
      objects.set(key, { bytes: Buffer.concat(chunks), contentType: req.headers['content-type'], sha256: req.headers['x-amz-meta-sha256'] });
      if (key.includes('/evidence/') && state.onImagePut) await state.onImagePut(key);
      res.writeHead(200); res.end();
    } else if (req.method === 'GET') {
      const object = objects.get(key);
      if (state.failGet || !object) { res.writeHead(503); res.end(); return; }
      res.setHeader('Content-Type', object.contentType);
      res.setHeader('Content-Length', object.bytes.length);
      res.end(object.bytes);
    } else if (req.method === 'DELETE') {
      objects.delete(key); res.writeHead(204); res.end();
    } else { res.writeHead(400); res.end(); }
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const endpoint = `http://127.0.0.1:${server.address().port}`;
  return { objects, calls, state, env: { R2_ENDPOINT: endpoint, R2_BUCKET_NAME: 'synthetic-bucket',
    R2_ACCESS_KEY_ID: 'synthetic-access', R2_SECRET_ACCESS_KEY: 'synthetic-secret', R2_PUBLIC_BASE_URL: endpoint },
  close: async () => { server.closeAllConnections(); await new Promise((done) => server.close(done)); } };
}

module.exports = { r2Fixture };
