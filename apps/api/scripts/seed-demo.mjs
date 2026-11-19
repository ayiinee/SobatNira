import { randomBytes } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import pg from 'pg';
import configuration from '../dist/config/backend.config.js';
import postgres from '../dist/database/postgres.config.js';
import migrations from '../dist/database/migrations.js';

const root = resolve(import.meta.dirname, '../../..');
const loginFile = resolve(root, '.tmp/mobile/demo-login.json');
const email = 'admin.demo@example.invalid';
const marker = 'sobatnira-development-demo-v1';
const tenantId = 'de000000-0000-4000-8000-000000000001';
const factoryId = 'de000000-0000-4000-8000-000000000002';
const suppliers = ['de000000-0000-4000-8000-000000000011', 'de000000-0000-4000-8000-000000000012'];
const lots = [1, 2, 3].map((number) => `de000000-0000-4000-8000-00000000002${number}`);
class SeedError extends Error {}

async function seed() {
  const config = configuration.loadConfiguration();
  if (config.environment !== 'development') throw new SeedError('Seeder demo hanya boleh berjalan dengan NODE_ENV=development.');
  if (!config.postgres || !config.supabase?.secretKey) {
    throw new SeedError('Seeder memerlukan DATABASE_URL, SUPABASE_URL dan SUPABASE_SECRET_KEY.');
  }
  const client = new pg.Client(postgres.postgresClientOptions(config));
  client.on('error', () => {});
  let transaction = false;
  try {
    await client.connect();
    await migrations.assertBusinessMigrationsApplied(client);
    const reviewSchema = await client.query("SELECT to_regclass('review_memberships') AS membership");
    if (!reviewSchema.rows[0]?.membership) throw new SeedError('Jalankan npm run db:migrate:ocr sebelum seeder demo.');
    const existing = await client.query(
      'SELECT id, raw_app_meta_data FROM auth.users WHERE lower(email) = $1', [email],
    );
    const user = existing.rows[0];
    if (user && user.raw_app_meta_data?.sobatnira_seed !== marker) {
      throw new SeedError('Email demo sudah dipakai akun lain; seeder tidak mengubah akun tersebut.');
    }
    let saved;
    try { saved = JSON.parse(readFileSync(loginFile, 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw new SeedError('Periksa file privat .tmp/mobile/demo-login.json.'); }
    const reusable = user && saved?.supabaseUrl === config.supabase.url && saved?.userId === user.id &&
      saved?.email === email && typeof saved?.password === 'string' && saved.password.length >= 24;
    const password = reusable ? saved.password : randomBytes(24).toString('base64url') + 'aA1!';
    let userId = user?.id;
    if (!reusable) {
      // Admin createUser confirms only this synthetic user, without sending mail.
      // https://supabase.com/docs/reference/javascript/auth-admin-createuser
      const response = await fetch(new URL(`/auth/v1/admin/users${user ? `/${user.id}` : ''}`, config.supabase.url), {
        method: user ? 'PUT' : 'POST',
        headers: { apikey: config.supabase.secretKey, Authorization: `Bearer ${config.supabase.secretKey}`,
          'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, email_confirm: true,
          app_metadata: { sobatnira_seed: marker }, user_metadata: { display_name: 'Admin Demo Sintetis' } }),
        signal: AbortSignal.timeout(config.timeoutMs),
      });
      if (!response.ok) throw new SeedError(`Pembuatan akun demo Supabase gagal (HTTP ${response.status}); periksa secret key dan Auth.`);
      const created = await response.json();
      userId = created.id;
      if (typeof userId !== 'string' || !/^[0-9a-f-]{36}$/i.test(userId)) {
        throw new SeedError('Supabase tidak mengembalikan ID akun demo yang valid.');
      }
    }
    mkdirSync(resolve(root, '.tmp/mobile'), { recursive: true });
    writeFileSync(loginFile, JSON.stringify({ supabaseUrl: config.supabase.url, email, password, userId }, null, 2) + '\n', { mode: 0o600 });

    await client.query('BEGIN');
    transaction = true;
    await client.query('SELECT pg_advisory_xact_lock(1397637710, 2)');
    await client.query('INSERT INTO sobatnira.tenants(id, name) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [tenantId, 'Usaha Demo Sintetis']);
    await client.query('INSERT INTO sobatnira.factories(id, tenant_id, name) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING',
      [factoryId, tenantId, 'Pabrik Demo Sintetis']);
    await client.query('INSERT INTO sobatnira.tenant_memberships(tenant_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [tenantId, userId]);
    await client.query(`INSERT INTO sobatnira.factory_memberships(tenant_id, factory_id, user_id, role)
      VALUES ($1, $2, $3, 'admin') ON CONFLICT DO NOTHING`, [tenantId, factoryId, userId]);
    await client.query(`INSERT INTO review_memberships(user_id, factory_id, role)
      VALUES ($1, $2, 'ADMIN') ON CONFLICT DO NOTHING`, [userId, factoryId]);
    for (const [index, id] of suppliers.entries()) {
      await client.query('INSERT INTO sobatnira.suppliers(id, tenant_id, name) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING',
        [id, tenantId, `Pemasok Demo ${index + 1} (Sintetis)`]);
    }
    for (const [code, name] of [['DEMO_BL', 'Bululawang Demo'], ['DEMO_PS', 'PS Demo']]) {
      await client.query('INSERT INTO sobatnira.cane_types(tenant_id, code, name) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING',
        [tenantId, code, name]);
    }
    for (const [index, id] of lots.entries()) {
      await client.query(`INSERT INTO sobatnira.lots(id, tenant_id, factory_id, supplier_id, display_code, received_at)
        VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT DO NOTHING`,
      [id, tenantId, factoryId, suppliers[index % suppliers.length], `DEMO-KLOTER-00${index + 1}`, `2026-11-${15 + index}T08:00:00+07:00`]);
    }
    await client.query('COMMIT');
    transaction = false;
    console.log('Seed sintetis siap: 1 admin, 1 usaha, 1 pabrik, 2 pemasok, 2 jenis tebu, 3 kloter.');
    console.log('Akun login tersimpan privat di .tmp/mobile/demo-login.json (akar repo).');
    console.log('Stok tetap berasal dari pengesahan nota; seeder hanya mengisi data dasar.');
  } catch (error) {
    if (transaction) await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { await client.end(); }
}

seed().catch((error) => {
  console.error(error instanceof SeedError || error instanceof configuration.ConfigurationError ? error.message :
    'Seed demo gagal; periksa migrasi, koneksi, dan izin database. Aman untuk menjalankan ulang setelah diperbaiki.');
  process.exitCode = 1;
});
