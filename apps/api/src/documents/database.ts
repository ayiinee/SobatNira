import { Injectable, Logger, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';
import { loadConfiguration } from '../config/backend.config';
import { postgresClientOptions } from '../database/postgres.config';

const directory = resolve(__dirname, '../../migrations/ocr');
const migrationFiles = async () => (await readdir(directory)).filter((name) => /^\d+_.*\.sql$/.test(name)).sort();
export const migrationChecksum = (sql: string) => createHash('sha256').update(sql.replace(/\r\n/g, '\n')).digest('hex');

@Injectable()
export class Database implements OnModuleDestroy {
  private readonly logger = new Logger(Database.name);
  private pool?: Pool;

  private connection() {
    if (this.pool) return this.pool;
    const config = loadConfiguration({ envFile: false });
    if (!config.postgres) {
      throw new ServiceUnavailableException('Database dokumen belum dikonfigurasi');
    }
    const pool = new Pool(postgresClientOptions(config));
    // pg discards failed idle connections and opens replacements on demand.
    pool.on('error', () => this.logger.warn('Koneksi idle database dokumen terputus.'));
    this.pool = pool;
    return pool;
  }

  query<T extends QueryResultRow = QueryResultRow>(sql: string, args?: unknown[]): Promise<QueryResult<T>> {
    return this.connection().query<T>(sql, args);
  }

  async transaction<T>(operation: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.connection().connect();
    try {
      await client.query('BEGIN');
      const result = await operation(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async migrate(baseline = false) {
    const files = await migrationFiles();
    await this.transaction(async (db) => {
      await db.query("SELECT pg_advisory_xact_lock(hashtext('sobatnira_schema_migrations'))");
      await db.query('CREATE TABLE IF NOT EXISTS sobatnira_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
      await db.query('ALTER TABLE sobatnira_migrations ADD COLUMN IF NOT EXISTS checksum text');
      const { rows } = await db.query<{ name: string; checksum: string | null }>('SELECT name,checksum FROM sobatnira_migrations');
      const applied = new Map(rows.map(row => [row.name, row.checksum]));
      for (const file of files) {
        const sql = await readFile(resolve(directory, file), 'utf8'), checksum = migrationChecksum(sql);
        if (applied.has(file)) {
          if (applied.get(file) === null && baseline) {
            await db.query('UPDATE sobatnira_migrations SET checksum=$2 WHERE name=$1 AND checksum IS NULL', [file, checksum]);
          } else if (applied.get(file) !== checksum) throw new Error('OCR migration changed or requires reviewed checksum baseline');
          continue;
        }
        await db.query(sql);
        await db.query('INSERT INTO sobatnira_migrations (name,checksum) VALUES ($1,$2)', [file, checksum]);
      }
    });
  }

  async assertMigrationsApplied() {
    const files = await migrationFiles();
    const { rows } = await this.query<{ name: string; checksum: string }>('SELECT name,checksum FROM sobatnira_migrations');
    const applied = new Map(rows.map(row => [row.name, row.checksum]));
    for (const name of files) {
      if (applied.get(name) !== migrationChecksum(await readFile(resolve(directory, name), 'utf8')))
        throw new Error('OCR migrations are pending, changed, or require reviewed checksum baseline');
    }
  }

  async onModuleDestroy() {
    await this.pool?.end();
  }
}
