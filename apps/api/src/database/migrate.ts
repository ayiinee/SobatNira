import { Client } from 'pg';
import { ConfigurationError, loadConfiguration } from '../config/backend.config';
import { applyMigrations } from './migrations';
import { postgresClientOptions } from './postgres.config';

async function main() {
  const config = loadConfiguration();
  if (!config.postgres) throw new ConfigurationError(['DATABASE_URL']);
  const client = new Client(postgresClientOptions(config));
  client.on('error', () => {});
  try {
    await client.connect();
    const applied = await applyMigrations(client);
    console.log(applied.length ? `Migrasi berhasil: ${applied.join(', ')}` : 'Database sudah menggunakan migrasi terbaru.');
  } finally { await client.end(); }
}

void main().catch((error: unknown) => {
  console.error(error instanceof ConfigurationError ? error.message :
    'Migrasi gagal dan transaksi dibatalkan. Periksa koneksi, izin database, skema dan checksum migrasi.');
  process.exitCode = 1;
});
