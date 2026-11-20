import { performance } from 'node:perf_hooks';
import { Pool, PoolConfig } from 'pg';
import { BackendConfig } from '../config/backend.config';
import { postgresClientOptions } from './postgres.config';

export function databasePoolOptions(config: BackendConfig, kind: 'business' | 'documents'): PoolConfig {
  const settings = config.databasePool;
  return { ...postgresClientOptions(config),
    application_name: `sobatnira-${kind}`,
    max: (kind === 'business' ? settings?.businessMax : settings?.documentsMax) ?? 5,
    idleTimeoutMillis: settings?.idleMs ?? 30000,
    connectionTimeoutMillis: settings?.connectMs ?? config.timeoutMs,
    statement_timeout: settings?.statementMs ?? config.timeoutMs,
    // Server timeout owns cancellation; a client-only timer can return an active
    // connection too early. Keep the driver deadline slightly above the server.
    query_timeout: (settings?.statementMs ?? config.timeoutMs) + 1000,
  };
}

export class PoolMeasurements {
  private acquired = 0;
  private acquisitionErrors = 0;
  private waitTotalMs = 0;
  private waitMaxMs = 0;
  private transactions = 0;
  private transactionTotalMs = 0;
  private transactionMaxMs = 0;

  async connect(pool: Pool) {
    const start = performance.now();
    try { const client = await pool.connect(); this.acquired++; return client; }
    catch (error) { this.acquisitionErrors++; throw error; }
    finally { const elapsed = performance.now() - start; this.waitTotalMs += elapsed; this.waitMaxMs = Math.max(this.waitMaxMs, elapsed); }
  }

  transactionFinished(start: number) {
    const elapsed = performance.now() - start;
    this.transactions++; this.transactionTotalMs += elapsed; this.transactionMaxMs = Math.max(this.transactionMaxMs, elapsed);
  }

  snapshot(pool?: Pool) {
    return { total: pool?.totalCount ?? 0, idle: pool?.idleCount ?? 0, waiting: pool?.waitingCount ?? 0,
      acquired: this.acquired, acquisitionErrors: this.acquisitionErrors, waitTotalMs: this.waitTotalMs,
      waitMaxMs: this.waitMaxMs, transactions: this.transactions,
      transactionTotalMs: this.transactionTotalMs, transactionMaxMs: this.transactionMaxMs };
  }
}

export function samplePool(pool: Pool, measurements: PoolMeasurements, log: (stats: ReturnType<PoolMeasurements['snapshot']>) => void) {
  const timer = setInterval(() => log(measurements.snapshot(pool)), 30000);
  timer.unref();
  return timer;
}
