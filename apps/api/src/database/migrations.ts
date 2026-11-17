import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { Client } from 'pg';
import type { DatabaseSession } from './database.service';

export const MIGRATIONS_DIRECTORY = resolve(__dirname, '../../migrations');

function migrationSources() {
  return readdirSync(MIGRATIONS_DIRECTORY).filter((name) => /^\d+_[a-z_]+\.sql$/.test(name)).sort().map((name) => {
    const sql = readFileSync(resolve(MIGRATIONS_DIRECTORY, name), 'utf8').replace(/\r\n/g, '\n');
    return { name, sql, checksum: createHash('sha256').update(sql).digest('hex') };
  });
}

export async function assertBusinessMigrationsApplied(db: DatabaseSession) {
  const { rows } = await db.query<{ name: string; checksum: string }>('SELECT name, checksum FROM sobatnira._migrations', []);
  const applied = new Map(rows.map(({ name, checksum }) => [name, checksum]));
  if (migrationSources().some(({ name, checksum }) => applied.get(name) !== checksum)) {
    throw new Error('Business migrations are missing or differ from the applied versions');
  }
}

export async function applyMigrations(client: Client): Promise<string[]> {
  const applied: string[] = [];
  await client.query('BEGIN');
  try {
    await client.query('SELECT pg_advisory_xact_lock(1397637710, 1)');
    await client.query('CREATE SCHEMA IF NOT EXISTS sobatnira');
    await client.query('REVOKE ALL ON SCHEMA sobatnira FROM PUBLIC, anon, authenticated');
    await client.query(`CREATE TABLE IF NOT EXISTS sobatnira._migrations (
      name text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now()
    )`);
    await client.query('REVOKE ALL ON sobatnira._migrations FROM PUBLIC, anon, authenticated');
    for (const { name, sql, checksum } of migrationSources()) {
      const previous = await client.query<{ checksum: string }>(
        'SELECT checksum FROM sobatnira._migrations WHERE name = $1', [name],
      );
      if (previous.rows.length) {
        if (previous.rows[0].checksum !== checksum) throw new Error('Applied migration was modified.');
        continue;
      }
      await client.query(sql);
      await client.query('INSERT INTO sobatnira._migrations(name, checksum) VALUES ($1, $2)', [name, checksum]);
      applied.push(name);
    }
    await client.query('COMMIT');
    return applied;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}
