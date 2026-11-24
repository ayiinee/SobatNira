import { ForbiddenException, Inject, Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { Redis } from 'ioredis';
import { BACKEND_CONFIG, BackendConfig } from '../config/backend.config';
import { FactoryAccess } from '../auth/auth.types';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { DatabaseService } from '../database/database.service';
import { CatalogQuery, scopeValues } from '../production/production.dto';

type Catalog = 'suppliers' | 'cane_types';
const digest = (value: string) => createHash('sha256').update(value).digest('hex');
const MAX_BYTES = 256 * 1024;
const wait = (milliseconds: number) => new Promise(resolve => setTimeout(resolve, milliseconds));

function pageMatches(data: unknown, access: FactoryAccess, query: CatalogQuery, catalog: Catalog): boolean {
  if (!data || typeof data !== 'object') return false;
  const page = data as { items?: unknown[]; total?: number; limit?: number; offset?: number };
  return Array.isArray(page.items) && page.items.length <= query.limit &&
    Number.isSafeInteger(page.total) && Number(page.total) >= page.items.length &&
    page.limit === query.limit && page.offset === query.offset && page.items.every(value => {
      if (!value || typeof value !== 'object') return false;
      const item = value as Record<string, unknown>;
      return item.tenantId === access.tenantId && typeof item.id === 'string' && typeof item.name === 'string' &&
        typeof item.isActive === 'boolean' && (catalog !== 'cane_types' || typeof item.code === 'string');
    });
}

@Injectable()
export class CatalogCache implements OnModuleDestroy {
  private readonly logger = new Logger(CatalogCache.name);
  private client?: Redis;
  private connecting?: Promise<unknown>;
  private sampler?: NodeJS.Timeout;
  private readonly flights = new Map<string, Promise<unknown>>();
  private readonly counts = { hit: 0, miss: 0, error: 0, invalid: 0, coalesced: 0, skipped: 0, lockWait: 0 };
  constructor(@Inject(BACKEND_CONFIG) private readonly config: BackendConfig, private readonly db: DatabaseService) {}
  statistics() { return { ...this.counts, filling: this.flights.size, connection: this.client?.status ?? 'unused' }; }

  private async redis() {
    if (!this.client) {
      const timeout = this.config.catalogCache!.timeoutMs;
      this.client = new Redis(this.config.redis!.url, { lazyConnect: true, enableOfflineQueue: false,
        enableReadyCheck: false, connectTimeout: timeout, commandTimeout: timeout,
        maxRetriesPerRequest: 0, retryStrategy: count => Math.min(count * 1000, 30000) });
      this.client.on('error', () => {});
      this.sampler = setInterval(() => this.logger.debug({ event: 'catalog_cache', ...this.statistics() }), 30000);
      this.sampler.unref();
    }
    if (this.client.status === 'wait') {
      this.connecting ??= this.client.connect().finally(() => { this.connecting = undefined; });
    }
    if (this.connecting) await this.connecting;
    return this.client.status === 'ready' ? this.client : undefined;
  }

  async read<T>(access: FactoryAccess, catalog: Catalog, query: CatalogQuery, load: () => Promise<T>): Promise<T> {
    if (!this.config.catalogCache?.enabled || !this.config.redis) { this.counts.skipped++; return load(); }
    // Authorization and generation are one current SQL snapshot, even on a cache hit.
    const { rows: [version] } = await this.db.query<{ generation: string; role: string }>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT COALESCE(v.generation::text,'empty') AS generation,a.role FROM authorized_scope a
      LEFT JOIN sobatnira.catalog_cache_versions v ON v.tenant_id=a."tenantId" AND v.catalog=$4
      WHERE a.role IN ('admin','owner')`, [...scopeValues(access), catalog]);
    if (!version) throw new ForbiddenException('Akses pabrik tidak lagi tersedia.');
    const filters = Object.fromEntries(Object.entries(query).filter(([, value]) => value !== undefined).sort(([a], [b]) => a.localeCompare(b)));
    const database = this.config.postgres ? new URL(this.config.postgres.url) : undefined;
    const namespace = digest(`${this.config.environment}:${database?.host}:${database?.pathname}`);
    const key = `sobatnira:catalog:v1:${namespace}:${access.tenantId}:${access.factoryId}:${access.userId}:${version.role}:${catalog}:${version.generation}:${digest(JSON.stringify(filters))}`;
    const pending = this.flights.get(key);
    if (pending) { this.counts.coalesced++; return pending as Promise<T>; }
    if (this.flights.size >= 100) { this.counts.skipped++; return load(); }
    const work = this.fill(access, catalog, query, key, load);
    this.flights.set(key, work);
    try { return await work; }
    finally { this.flights.delete(key); }
  }

  private async fill<T>(access: FactoryAccess, catalog: Catalog, query: CatalogQuery, key: string, load: () => Promise<T>) {
    let client: Redis | undefined;
    const decode = (raw: string | null): T | undefined => {
      if (!raw) return undefined;
      try {
        if (Buffer.byteLength(raw) > MAX_BYTES) throw new Error();
        const envelope = JSON.parse(raw);
        if (envelope.schema !== 1 || envelope.keyHash !== digest(key) || !pageMatches(envelope.data, access, query, catalog)) throw new Error();
        return envelope.data as T;
      } catch { this.counts.invalid++; return undefined; }
    };
    try {
      client = await this.redis();
      if (client) {
        const hit = decode(await client.get(key));
        if (hit !== undefined) { this.counts.hit++; return hit; }
        // Lock expires itself; no delete can accidentally release another filler's lock.
        const lock = await client.set(key + ':fill', randomUUID(), 'PX', 2000, 'NX');
        if (!lock) {
          this.counts.lockWait++;
          for (let n = 0; n < 5; n++) {
            await wait(25);
            const shared = decode(await client.get(key));
            if (shared !== undefined) { this.counts.hit++; return shared; }
          }
        }
      }
    } catch { this.counts.error++; client = undefined; }
    this.counts.miss++;
    // DB errors propagate. Never store errors or borrow an entry from another version.
    const result = await load();
    if (client) {
      try {
        const data = JSON.parse(JSON.stringify(result));
        const value = JSON.stringify({ schema: 1, keyHash: digest(key), data });
        if (Buffer.byteLength(value) <= MAX_BYTES && pageMatches(data, access, query, catalog)) {
          await client.set(key, value, 'EX', this.config.catalogCache!.ttlSeconds);
        } else this.counts.skipped++;
      } catch { this.counts.error++; }
    }
    return result;
  }

  async onModuleDestroy() { clearInterval(this.sampler); this.client?.disconnect(); }
}
