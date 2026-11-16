import { validateRuntime, supabaseKey } from './config';
import { Database } from './database';
import { assertR2Privacy, MediaStorage } from './media';
import { UUID } from './contracts';
import { ConfigurationError } from '../config/backend.config';

async function check(name: string, action: () => Promise<unknown>) {
  try { await action(); console.log(`${name}: OK`); }
  catch { console.error(`${name}: GAGAL`); process.exitCode = 1; }
}

async function ok(url: URL | string, headers: Record<string, string>, timeout = 6_000) {
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(timeout), redirect: 'error' });
  if (!response.ok) throw new Error('Bad response');
  return response;
}

async function readiness(db: Database, infrastructureOnly: boolean) {
  const connected = process.env.SOBATNIRA_MODE === 'connected';
  await Promise.all([
    check('PostgreSQL [DATABASE_URL, DATABASE_SSL_CA_FILE]', () => db.transaction(async (client) => {
      await client.query('SET TRANSACTION READ ONLY');
      await client.query('SELECT 1');
    })),
    check('Auth [SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY]', () => ok(new URL('/auth/v1/settings', process.env.SUPABASE_URL), { apikey: supabaseKey()! })),
    check(connected ? 'R2 [R2_ENDPOINT, R2_BUCKET_NAME, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY]' : 'Media lokal [DOCUMENT_MEDIA_DIR]',
      () => new MediaStorage().check()),
  ]);
  if (infrastructureOnly) return;
  await Promise.all([
    check('Migration [jalankan db:migrate]', async () => {
      await db.query('SELECT 1 FROM whatsapp_notices LIMIT 0');
      await db.query('SELECT status FROM clarification_requests LIMIT 0');
      const { rowCount } = await db.query("SELECT 1 FROM sobatnira_migrations WHERE name='005_duplicate_photo_lookup.sql'");
      if (!rowCount) throw new Error('Migration missing');
    }),
    check('PaddleOCR [AI_BASE_URL, AI_SERVICE_INTERNAL_TOKEN, extra paddle]', () => ok(
      new URL('/internal/v1/ocr/ready', process.env.AI_SERVICE_BASE_URL || process.env.AI_BASE_URL),
      { 'X-Internal-Service-Token': process.env.AI_SERVICE_INTERNAL_TOKEN! }, 120_000)),
    ...(connected ? [
      ...(process.env.R2_PUBLIC_BASE_URL ? [check('Privasi R2 [R2_PUBLIC_BASE_URL, akses publik bucket]', assertR2Privacy)] : []),
      check('Gemini [GEMINI_API_KEY, GEMINI_VISION_MODEL]', async () => {
        const model = process.env.GEMINI_VISION_MODEL;
        const token = process.env.GEMINI_API_KEY;
        if (!token || !model || !/^[a-z0-9._-]+$/i.test(model)) throw new Error('Missing configuration');
        await ok(`https://generativelanguage.googleapis.com/v1beta/models/${model}`, { 'x-goog-api-key': token });
      }),
      check('OpenRouter [OPENROUTER_API_KEY, OPENROUTER_AGENT_MODEL, OPENROUTER_AGENT_FALLBACK_MODEL, OPENROUTER_ALLOWED_PROVIDERS]', async () => {
        const key = process.env.OPENROUTER_API_KEY;
        const models = [process.env.OPENROUTER_AGENT_MODEL, process.env.OPENROUTER_AGENT_FALLBACK_MODEL].filter(Boolean);
        if (!key || !process.env.OPENROUTER_AGENT_MODEL || !process.env.OPENROUTER_ALLOWED_PROVIDERS ||
            models.some((model) => !/^[a-z0-9._-]+\/[a-z0-9._-]+$/i.test(model!))) throw new Error('Missing configuration');
        const headers = { Authorization: `Bearer ${key}` };
        await ok('https://openrouter.ai/api/v1/key', headers);
        await Promise.all([...new Set(models)].map((model) => ok(`https://openrouter.ai/api/v1/models/${model}/endpoints`, headers)));
      }),
    ] : []),
  ]);
}

async function provision(db: Database) {
  const factory = process.env.SETUP_FACTORY_ID;
  const operator = process.env.SETUP_OPERATOR_PHONE;
  const name = process.env.SETUP_OPERATOR_NAME;
  const admin = process.env.SETUP_ADMIN_USER_ID;
  const owner = process.env.SETUP_OWNER_USER_ID;
  if (!factory || !UUID.test(factory) || !operator || !/^\+[1-9][0-9]{7,14}$/.test(operator) || !name?.trim() ||
      !admin || !UUID.test(admin) || (owner && (!UUID.test(owner) || owner === admin))) {
    throw new Error('Provisioning: periksa SETUP_FACTORY_ID, SETUP_OPERATOR_PHONE, SETUP_OPERATOR_NAME, SETUP_ADMIN_USER_ID, SETUP_OWNER_USER_ID');
  }
  await db.transaction(async (client) => {
    const row = await client.query(`INSERT INTO operator_contacts (factory_id,phone_e164,display_name) VALUES ($1,$2,$3)
      ON CONFLICT (phone_e164) DO NOTHING`, [factory, operator, name]);
    if (!row.rowCount) {
      const { rows: [existing] } = await client.query('SELECT factory_id,active FROM operator_contacts WHERE phone_e164=$1', [operator]);
      if (!existing?.active || existing.factory_id !== factory.toLowerCase()) throw new Error('Provisioning: operator nonaktif atau sudah berada di pabrik lain');
    }
    for (const [id, role] of [[admin, 'ADMIN'], ...(owner ? [[owner, 'OWNER']] : [])]) {
      await client.query(`INSERT INTO review_memberships (user_id,factory_id,role) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`, [id, factory, role]);
      const { rows: [existing] } = await client.query('SELECT role,active FROM review_memberships WHERE user_id=$1 AND factory_id=$2', [id, factory]);
      if (!existing?.active || existing.role !== role) throw new Error('Provisioning: keanggotaan sudah mempunyai role atau status berbeda');
    }
  });
  console.log('Provisioning: operator dan keanggotaan tersedia');
}

const db = new Database();
void (async () => {
  try {
    if (!process.env.SOBATNIRA_MODE) throw new Error('NestJS: SOBATNIRA_MODE wajib');
    validateRuntime();
    const action = process.argv[2];
    if (action === 'provision') await provision(db);
    else if (action === 'check') await readiness(db, process.argv.includes('--infra-only'));
    else if (action === 'check-media-privacy') await check('Privasi R2 [R2_PUBLIC_BASE_URL, akses publik bucket]', assertR2Privacy);
    else throw new Error('NestJS: gunakan check [--infra-only], check-media-privacy, atau provision');
  } catch (error) {
    console.error(error instanceof ConfigurationError ||
      (error instanceof Error && /^(NestJS|PostgreSQL|FastAPI|Supabase|R2|Mode local|Provisioning):/.test(error.message))
      ? error.message : 'Setup gagal. Periksa DATABASE_URL, migration dan pengaturan provider.');
    process.exitCode = 1;
  } finally { await db.onModuleDestroy(); }
})();
