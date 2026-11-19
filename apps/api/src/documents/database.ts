import { Injectable, Logger, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';
import { loadConfiguration } from '../config/backend.config';
import { postgresClientOptions } from '../database/postgres.config';

const directory = resolve(__dirname, '../../migrations/ocr');
const migrationFiles = async () => (await readdir(directory)).filter((name) => /^\d+_.*\.sql$/.test(name)).sort();

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

  async migrate() {
    const files = await migrationFiles();
    await this.transaction(async (db) => {
      await db.query("SELECT pg_advisory_xact_lock(hashtext('sobatnira_schema_migrations'))");
      await db.query('CREATE TABLE IF NOT EXISTS sobatnira_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
      const { rows } = await db.query<{ name: string }>('SELECT name FROM sobatnira_migrations');
      const applied = new Set(rows.map(({ name }) => name));
      for (const file of files) {
        if (applied.has(file)) continue;
        await db.query(await readFile(resolve(directory, file), 'utf8'));
        await db.query('INSERT INTO sobatnira_migrations (name) VALUES ($1)', [file]);
      }
    });
  }

  async assertMigrationsApplied() {
    const files = await migrationFiles();
    const { rows } = await this.query<{ name: string }>('SELECT name FROM sobatnira_migrations');
    const applied = new Set(rows.map(({ name }) => name));
    if (files.some((name) => !applied.has(name))) throw new Error('OCR migrations are pending');
  }

  async onModuleDestroy() {
    await this.pool?.end();
  }
}
