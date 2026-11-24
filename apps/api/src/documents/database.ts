import { Injectable, Logger, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { performance } from 'node:perf_hooks';
import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';
import { loadConfiguration } from '../config/backend.config';
import { databasePoolOptions, PoolMeasurements, samplePool } from '../database/pool';

const directory = resolve(__dirname, '../../migrations/ocr');
const migrationFiles = async () => (await readdir(directory)).filter((name) => /^\d+_.*\.sql$/.test(name)).sort();

@Injectable()
export class Database implements OnModuleDestroy {
  private readonly logger = new Logger(Database.name);
  private pool?: Pool;
  private sampler?: NodeJS.Timeout;
  private readonly measurements = new PoolMeasurements();
  poolStatistics() { return this.measurements.snapshot(this.pool); }

  private connection() {
    if (this.pool) return this.pool;
    const config = loadConfiguration({ envFile: false });
    if (!config.postgres) {
      throw new ServiceUnavailableException('Database dokumen belum dikonfigurasi');
    }
    const pool = new Pool(databasePoolOptions(config, 'documents'));
    // pg discards failed idle connections and opens replacements on demand.
    pool.on('error', () => this.logger.warn('Koneksi idle database dokumen terputus.'));
    this.sampler = samplePool(pool, this.measurements, stats => this.logger.debug({ event: 'database_pool', pool: 'documents', ...stats }));
    this.pool = pool;
    return pool;
  }

  async query<T extends QueryResultRow = QueryResultRow>(sql: string, args?: unknown[]): Promise<QueryResult<T>> {
    const client = await this.measurements.connect(this.connection());
    let failed = false;
    try { return await this.measurements.directQuery(() => client.query<T>(sql, args)); }
    catch (error) { failed = true; throw error; }
    finally { client.release(failed); }
  }

  async transaction<T>(operation: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.measurements.connect(this.connection());
    const started = performance.now();
    let broken = false;
    let failed = false;
    try {
      await client.query('BEGIN');
      const result = await operation(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      failed = true;
      await client.query('ROLLBACK').catch(() => { broken = true; });
      throw error;
    } finally {
      this.measurements.transactionFinished(started, failed);
      client.release(broken);
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
    clearInterval(this.sampler);
    await this.pool?.end();
  }
}
