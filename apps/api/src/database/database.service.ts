import { ConflictException, HttpException, Inject, Injectable, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';
import { BACKEND_CONFIG, BackendConfig } from '../config/backend.config';
import { postgresClientOptions } from './postgres.config';

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

  constructor(@Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  private getPool(): Pool {
    if (!this.config.postgres) throw new ServiceUnavailableException('Database belum dikonfigurasi.');
    if (!this.pool) {
      this.pool = new Pool({ ...postgresClientOptions(this.config), max: 5, idleTimeoutMillis: 30000 });
      this.pool.on('error', () => {});
    }
    return this.pool;
  }

  async query<T extends QueryResultRow>(text: string, values: unknown[]): Promise<QueryResult<T>> {
    try {
      return await this.getPool().query<T>(text, values);
    } catch (error) { return databaseFailure(error); }
  }

  async transaction<T>(work: (session: DatabaseSession) => Promise<T>): Promise<T> {
    let client: PoolClient | undefined;
    try {
      client = await this.getPool().connect();
      await client.query('BEGIN');
      const result = await work({ query: (sql, values) => client!.query(sql, values) });
      await client.query('COMMIT');
      return result;
    } catch (error) {
      if (client) {
        try { await client.query('ROLLBACK'); }
        catch { client.release(true); client = undefined; }
      }
      return databaseFailure(error);
    } finally { client?.release(); }
  }

  async onModuleDestroy() {
    await this.pool?.end();
  }
}
