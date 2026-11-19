// Export only public client settings; never pass the backend .env to Flutter.
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseEnv } from 'node:util';

const root = resolve(import.meta.dirname, '..');
class ConfigurationError extends Error {}

function origin(value, field) {
  try {
    const url = new URL(value);
    if (url.username || url.password || url.search || url.hash || url.pathname !== '/' ||
        !(url.protocol === 'https:' || (url.protocol === 'http:' &&
          ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)))) throw new Error();
    return url.origin;
  } catch {
    throw new ConfigurationError(`Periksa ${field} di .env.`);
  }
}

try {
  const env = { ...parseEnv(readFileSync(resolve(root, '.env'), 'utf8')), ...process.env };
  const key = (env.SUPABASE_PUBLISHABLE_KEY || env.SUPABASE_ANON_KEY || '').trim();
  let publicKey = key.startsWith('sb_publishable_');
  if (key.startsWith('eyJ')) {
    try {
      publicKey = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role === 'anon';
    } catch { /* Invalid JWT is rejected below. */ }
  }
  if (!publicKey) throw new ConfigurationError('SUPABASE_PUBLISHABLE_KEY harus publishable key atau anon key Supabase.');
  const host = (env.API_HOST || '127.0.0.1').trim();
  const port = (env.API_PORT || '3000').trim();
  if (!/^\d+$/.test(port) || +port < 1 || +port > 65535) throw new ConfigurationError('Periksa API_PORT di .env.');
  const browserHost = ['0.0.0.0', '::'].includes(host) ? '127.0.0.1' : host.includes(':') ? `[${host}]` : host;
  const config = {
    SOBATNIRA_MODE: 'connected',
    API_BASE_URL: origin(env.API_BASE_URL?.trim() || `http://${browserHost}:${port}`, 'API_BASE_URL/API_HOST'),
    SUPABASE_URL: origin(env.SUPABASE_URL?.trim(), 'SUPABASE_URL'),
    SUPABASE_PUBLISHABLE_KEY: key,
  };
  const directory = resolve(root, '.tmp/mobile');
  mkdirSync(directory, { recursive: true });
  writeFileSync(resolve(directory, 'public-defines.json'), JSON.stringify(config, null, 2) + '\n');
  console.log('Konfigurasi publik Flutter siap dari .env.');
} catch (error) {
  console.error(error instanceof ConfigurationError ? error.message : error.code === 'ENOENT' ?
    'File .env di akar repo belum tersedia.' : 'Konfigurasi Flutter gagal; periksa .env dan izin .tmp/mobile.');
  process.exitCode = 1;
}
