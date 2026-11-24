import { createReadStream } from 'node:fs';
import { realpath, stat } from 'node:fs/promises';
import { createServer, request } from 'node:http';
import { extname, resolve, sep } from 'node:path';
import { pipeline } from 'node:stream';

const contentTypes = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml', '.otf': 'font/otf', '.ttf': 'font/ttf', '.woff2': 'font/woff2',
};

function proxy(incoming, outgoing, target, path) {
  const headers = { ...incoming.headers, host: `127.0.0.1:${target}`, connection: 'close' };
  const upstream = request({ hostname: '127.0.0.1', port: target, method: incoming.method, path, headers }, response => {
    outgoing.writeHead(response.statusCode, response.headers);
    pipeline(response, outgoing, () => {});
  });
  upstream.on('error', () => {
    if (!outgoing.headersSent) outgoing.writeHead(502).end('Layanan lokal belum tersedia');
    else outgoing.destroy();
  });
  outgoing.on('close', () => upstream.destroy());
  incoming.pipe(upstream);
}

export async function startLocalWeb({ directory, webPort, apiPort, authPort }) {
  const root = await realpath(directory);
  const server = createServer(async (incoming, outgoing) => {
    try {
      const { pathname, search } = new URL(incoming.url, 'http://127.0.0.1');
      if (pathname === '/auth/v1/token' || pathname === '/auth/v1/settings') {
        return proxy(incoming, outgoing, authPort, pathname + search);
      }
      if (pathname === '/auth/me' || pathname === '/health' ||
          pathname.startsWith('/tenants/') || pathname.startsWith('/api/v1/mobile/')) {
        return proxy(incoming, outgoing, apiPort, pathname + search);
      }
      if (incoming.method !== 'GET' && incoming.method !== 'HEAD') {
        return outgoing.writeHead(405, { Allow: 'GET, HEAD' }).end();
      }
      const relative = decodeURIComponent(pathname === '/' ? '/index.html' : pathname);
      const file = resolve(root, `.${relative}`);
      if (!file.startsWith(root + sep)) return outgoing.writeHead(404).end();
      const canonical = await realpath(file);
      if (!canonical.startsWith(root + sep)) return outgoing.writeHead(404).end();
      const info = await stat(canonical);
      if (!info.isFile()) return outgoing.writeHead(404).end();
      outgoing.writeHead(200, {
        'Content-Type': contentTypes[extname(canonical)] ?? 'application/octet-stream',
        'Content-Length': info.size,
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
        ...(extname(canonical) === '.html' && {
          'Content-Security-Policy': "connect-src 'self' blob: data:; font-src 'self' blob: data:",
        }),
      });
      if (incoming.method === 'HEAD') return outgoing.end();
      pipeline(createReadStream(canonical), outgoing, () => {});
    } catch (error) {
      outgoing.writeHead(error instanceof URIError ? 400 : 404).end();
    }
  });
  await new Promise((ready, reject) => {
    server.once('error', reject);
    server.listen(webPort, '127.0.0.1', ready);
  });
  return server;
}
