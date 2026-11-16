import { loadConfiguration } from '../config/backend.config';

export function r2Settings() {
  const r2 = loadConfiguration({ envFile: false }).r2;
  if (!r2 || (process.env.SOBATNIRA_MODE === 'connected' && !r2.endpoint.startsWith('https://'))) {
    throw new Error('R2: periksa R2_ENDPOINT dan R2_BUCKET_NAME');
  }
  return r2;
}

export function supabaseKey() {
  return process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
}

function validUrl(value: string | undefined, protocols: string[]) {
  try { return protocols.includes(new URL(value ?? '').protocol); }
  catch { return false; }
}

export function validateRuntime() {
  const mode = process.env.SOBATNIRA_MODE;
  if (!mode) return;
  if (!['local','connected'].includes(mode)) throw new Error('NestJS: periksa SOBATNIRA_MODE');
  const missing: string[] = [];
  if (!validUrl(process.env.DATABASE_URL, ['postgresql:','postgres:'])) missing.push('PostgreSQL: DATABASE_URL');
  for (const name of ['AI_SERVICE_INTERNAL_TOKEN','WHATSAPP_ADAPTER_INTERNAL_TOKEN']) {
    if ((process.env[name]?.length ?? 0) < 32) missing.push(`NestJS: ${name}`);
  }
  if (process.env.DOCUMENT_WORKER_ENABLED !== 'true') missing.push('NestJS: DOCUMENT_WORKER_ENABLED');
  if (!validUrl(process.env.AI_SERVICE_BASE_URL || process.env.AI_BASE_URL, ['https:','http:'])) missing.push('FastAPI: AI_BASE_URL');
  if (!supabaseKey() || !validUrl(process.env.SUPABASE_URL, mode === 'local' ? ['http:'] : ['https:'])) {
    missing.push('Supabase: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY');
  }
  if (mode === 'connected') {
    for (const name of ['R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY']) if (!process.env[name]) missing.push(`R2: ${name}`);
    if (!process.env.R2_ENDPOINT && !process.env.R2_ACCOUNT_ID) missing.push('R2: R2_ENDPOINT');
    if (!process.env.R2_BUCKET_NAME && !process.env.R2_BUCKET) missing.push('R2: R2_BUCKET_NAME');
    if (!missing.length) r2Settings();
    if (process.env.DOCUMENT_MEDIA_DIR) missing.push('R2: hapus DOCUMENT_MEDIA_DIR pada mode connected');
  } else {
    if (!process.env.DOCUMENT_MEDIA_DIR) missing.push('NestJS: DOCUMENT_MEDIA_DIR');
    if (process.env.R2_ENDPOINT || process.env.R2_ACCOUNT_ID || process.env.R2_ACCESS_KEY_ID || process.env.R2_SECRET_ACCESS_KEY) {
      missing.push('R2: hapus konfigurasi R2 pada mode local');
    }
    for (const name of ['DATABASE_URL', 'SUPABASE_URL']) {
      const value = process.env[name];
      if (validUrl(value, ['postgresql:', 'postgres:', 'http:']) && !['127.0.0.1','localhost','[::1]'].includes(new URL(value!).hostname)) {
        missing.push(`Mode local: ${name} harus menunjuk loopback`);
      }
    }
  }
  if (missing.length) throw new Error(missing.join('\n'));
}
