// Minimal RESP protocol fixture, not a Redis server or production performance model.
const { createServer } = require('node:net');
const { once } = require('node:events');

function frame(buffer) {
  const line = buffer.indexOf('\r\n'); if (line < 0) return;
  if (buffer[0] !== 42) throw new Error('Expected RESP array');
  const count = Number(buffer.subarray(1, line)); let offset = line + 2; const args = [];
  for (let n = 0; n < count; n++) {
    const end = buffer.indexOf('\r\n', offset); if (end < 0) return;
    if (buffer[offset] !== 36) throw new Error('Expected bulk string');
    const length = Number(buffer.subarray(offset + 1, end));
    if (buffer.length < end + 2 + length + 2) return;
    args.push(buffer.toString('utf8', end + 2, end + 2 + length)); offset = end + 2 + length + 2;
  }
  return { args, used: offset };
}
const bulk = value => value === null ? '$-1\r\n' : `$${Buffer.byteLength(value)}\r\n${value}\r\n`;

async function redisFixture() {
  const entries = new Map(), sockets = new Set(), calls = [];
  const state = { delayMs: 0, unavailable: false };
  const current = key => { const item = entries.get(key); return item && item.expires > Date.now() ? item.value : null; };
  const server = createServer(socket => {
    sockets.add(socket); socket.on('close', () => sockets.delete(socket)); socket.on('error', () => {});
    let buffer = Buffer.alloc(0);
    socket.on('data', data => {
      buffer = Buffer.concat([buffer, data]);
      try {
        for (;;) {
          const parsed = frame(buffer); if (!parsed) break;
          buffer = buffer.subarray(parsed.used);
          const [raw, ...args] = parsed.args, command = raw.toUpperCase(); calls.push({ command, key: args[0] });
          const reply = () => {
            if (socket.destroyed) return;
            if (['GET', 'SET'].includes(command) && state.unavailable) { socket.destroy(); return; }
            if (command === 'HELLO') socket.write('%3\r\n+server\r\n+redis\r\n+version\r\n+7.2.0\r\n+proto\r\n:3\r\n');
            else if (command === 'GET') socket.write(bulk(current(args[0])));
            else if (command === 'SET') {
              if (args.includes('NX') && current(args[0]) !== null) socket.write('$-1\r\n');
              else { entries.set(args[0], { value: args[1], expires: Date.now() + Number(args[3]) * (args[2] === 'EX' ? 1000 : 1) }); socket.write('+OK\r\n'); }
            } else if (['CLIENT', 'SELECT', 'AUTH'].includes(command)) socket.write('+OK\r\n');
            else if (command === 'PING') socket.write('+PONG\r\n');
            else socket.write('-ERR unsupported fixture command\r\n');
          };
          if (state.delayMs && ['GET', 'SET'].includes(command)) { const timer = setTimeout(reply, state.delayMs); timer.unref(); }
          else reply();
        }
      } catch { socket.destroy(); }
    });
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  return { url: `redis://127.0.0.1:${server.address().port}`, entries, calls, state,
    async close() { for (const socket of sockets) socket.destroy(); await new Promise(resolve => server.close(resolve)); } };
}
module.exports = { redisFixture };
