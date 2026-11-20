import { ConflictException, HttpException, Inject, Injectable, Logger, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';
import { BACKEND_CONFIG, BackendConfig } from '../config/backend.config';
import { performance } from 'node:perf_hooks';
import { databasePoolOptions, PoolMeasurements, samplePool } from './pool';

export interface DatabaseSession {
  query<T extends QueryResultRow>(text: string, values: unknown[]): Promise<QueryResult<T>>;
}

function databaseFailure(error: unknown): never {
  if (error instanceof HttpException) throw error;
  const code = (error as { code?: string } | null)?.code;
  if (code && ['23505', '23503', '40001', '40P01', '55P03'].includes(code)) {
    throw new ConflictException('Data atau relasi berubah; muat ulang sebelum mengulangi operasi.');
  }
  throw new ServiceUnavailableException('Database belum tersedia atau operasi gagal.');
}

@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private pool?: Pool;
  private readonly logger = new Logger(DatabaseService.name);
  private sampler?: NodeJS.Timeout;
  private readonly measurements = new PoolMeasurements();
  poolStatistics() { return this.measurements.snapshot(this.pool); }

  constructor(@Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  private getPool(): Pool {
    if (!this.config.postgres) throw new ServiceUnavailableException('Database belum dikonfigurasi.');
    if (!this.pool) {
      this.pool = new Pool(databasePoolOptions(this.config, 'business'));
      this.pool.on('error', () => {});
      this.sampler = samplePool(this.pool, this.measurements, stats => this.logger.debug({ event: 'database_pool', pool: 'business', ...stats }));
    }
    return this.pool;
  }

  async query<T extends QueryResultRow>(text: string, values: unknown[]): Promise<QueryResult<T>> {
    let client: PoolClient | undefined;
    let failed = false;
    try {
      client = await this.measurements.connect(this.getPool());
      return await this.measurements.directQuery(() => client!.query<T>(text, values));
    } catch (error) { failed = true; return databaseFailure(error); }
    finally { client?.release(failed); }
  }

  async transaction<T>(work: (session: DatabaseSession) => Promise<T>): Promise<T> {
    let client: PoolClient | undefined;
    let started: number | undefined;
    let failed = false;
    try {
      client = await this.measurements.connect(this.getPool());
      started = performance.now();
      await client.query('BEGIN');
      const result = await work({ query: (sql, values) => client!.query(sql, values) });
      await client.query('COMMIT');
      return result;
    } catch (error) {
      failed = true;
      if (client) {
        try { await client.query('ROLLBACK'); }
        catch { client.release(true); client = undefined; }
      }
      return databaseFailure(error);
    } finally { if (started !== undefined) this.measurements.transactionFinished(started, failed); client?.release(); }
  }

  async onModuleDestroy() {
    clearInterval(this.sampler);
    await this.pool?.end();
  }
}
