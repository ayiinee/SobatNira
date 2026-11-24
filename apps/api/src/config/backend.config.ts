import { readFileSync } from 'node:fs';
import { isIP } from 'node:net';
import { resolve } from 'node:path';
import { parseEnv } from 'node:util';

export const BACKEND_CONFIG = Symbol('BACKEND_CONFIG');
export const DEFAULT_ENV_FILE = resolve(__dirname, '../../.env');

export interface BackendConfig {
  appName: string;
  environment: 'development' | 'test' | 'production';
  logLevel: 'debug' | 'info' | 'warn' | 'error' | 'silent';
  host: string;
  port: number;
  corsOrigins: string[];
  timeoutMs: number;
  aiTimeoutMs: number;
  aiBaseUrl: string;
  batchClosure?: { baseUrl: string; timeoutMs: number };
  supabase?: { url: string; publishableKey: string; secretKey?: string };
  postgres?: { url: string; caFile?: string; caPem?: string };
  databasePool?: { businessMax: number; documentsMax: number; idleMs: number; connectMs: number; statementMs: number };
  redis?: { url: string };
  catalogCache?: { enabled: boolean; ttlSeconds: number; timeoutMs: number };
  r2?: {
    endpoint: string;
    region: string;
    bucket: string;
    accessKeyId: string;
    secretAccessKey: string;
    signedUrlTtlSeconds: number;
    publicProbeBaseUrl?: string;
  };
}

export interface ConfigOptions {
  envFile?: string | false;
  env?: NodeJS.ProcessEnv;
}

export class ConfigurationError extends Error {
  constructor(readonly fields: string[]) {
    // Only field names may enter logs; never include a supplied value.
    super(`Konfigurasi tidak valid atau belum lengkap: ${[...new Set(fields)].join(', ')}`);
    this.name = 'ConfigurationError';
  }
}

export function isLoopback(host: string): boolean {
  return host === 'localhost' || host === '127.0.0.1' || host === '[::1]' || host === '::1';
}

export function loadConfiguration(options: ConfigOptions = {}): BackendConfig {
  let fileEnv: NodeJS.ProcessEnv = {};
  if (options.envFile !== false) {
    try {
      fileEnv = parseEnv(readFileSync(options.envFile ?? DEFAULT_ENV_FILE, 'utf8'));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT' || options.envFile) {
        throw new ConfigurationError(['ENV_FILE']);
      }
    }
  }
  // Process environment wins; parsing never mutates process.env.
  const env = { ...fileEnv, ...(options.env ?? process.env) };
  const invalid: string[] = [];
  const value = (key: string, fallback = '') => env[key]?.trim() || fallback;
  const required = (key: string) => {
    const result = value(key);
    if (!result) invalid.push(key);
    return result;
  };
  const integer = (key: string, fallback: number, min: number, max: number) => {
    const raw = value(key, String(fallback));
    const result = Number(raw);
    if (!/^\d+$/.test(raw) || !Number.isSafeInteger(result) || result < min || result > max) {
      invalid.push(key);
    }
    return result;
  };
  const url = (key: string, raw: string, protocols: string[], originOnly = false) => {
    try {
      const parsed = new URL(raw);
      if (!protocols.includes(parsed.protocol) || !parsed.hostname) throw new Error();
      if (['http:', 'https:'].includes(parsed.protocol)) {
        if (parsed.username || parsed.password || parsed.search || parsed.hash) throw new Error();
        if (originOnly && parsed.pathname !== '/') throw new Error();
      }
      return parsed;
    } catch {
      invalid.push(key);
      return undefined;
    }
  };
  const credentialEndpoint = (key: string, raw: string, originOnly = false) => {
    const parsed = url(key, raw, ['http:', 'https:'], originOnly);
    if (parsed?.protocol === 'http:' && !isLoopback(parsed.hostname)) invalid.push(key);
    return parsed;
  };

  const environment = value('NODE_ENV', 'development') as BackendConfig['environment'];
  if (!['development', 'test', 'production'].includes(environment)) invalid.push('NODE_ENV');
  const logLevel = value('LOG_LEVEL', 'info') as BackendConfig['logLevel'];
  if (!['debug', 'info', 'warn', 'error', 'silent'].includes(logLevel)) invalid.push('LOG_LEVEL');
  const host = value('API_HOST', '127.0.0.1');
  if (host !== 'localhost' && !isIP(host)) invalid.push('API_HOST');
  const corsOrigins = value('CORS_ORIGINS', value('MOBILE_WEB_ORIGINS', value('FRONTEND_ORIGIN',
    'http://127.0.0.1:8080,http://localhost:8080'))).split(',').map((origin) => origin.trim());
  for (const origin of corsOrigins) url('CORS_ORIGINS', origin, ['http:', 'https:'], true);
  const aiBaseUrl = value('AI_BASE_URL', 'http://127.0.0.1:8000');
  url('AI_BASE_URL', aiBaseUrl, ['http:', 'https:']);

  const config: BackendConfig = {
    appName: value('APP_NAME', 'SobatNira'), environment, logLevel, host,
    port: integer('API_PORT', 3000, 1, 65535),
    corsOrigins: corsOrigins.map((origin) => origin.replace(/\/$/, '')),
    timeoutMs: integer('CONNECTION_TIMEOUT_MS', 8000, 100, 60000),
    aiTimeoutMs: integer('AI_TIMEOUT_MS', 3000, 100, 60000),
    aiBaseUrl,
  };
  config.databasePool = {
    businessMax: integer('DB_POOL_BUSINESS_MAX', 5, 1, 100),
    documentsMax: integer('DB_POOL_DOCUMENTS_MAX', 5, 1, 100),
    idleMs: integer('DB_POOL_IDLE_MS', 30000, 1000, 600000),
    connectMs: integer('DB_POOL_CONNECT_MS', config.timeoutMs, 100, 60000),
    statementMs: integer('DB_STATEMENT_TIMEOUT_MS', config.timeoutMs, 100, 600000),
  };
  const catalogCacheEnabled = value('CATALOG_CACHE_ENABLED', 'false');
  if (!['true', 'false'].includes(catalogCacheEnabled)) invalid.push('CATALOG_CACHE_ENABLED');
  config.catalogCache = {
    enabled: catalogCacheEnabled === 'true',
    ttlSeconds: integer('CATALOG_CACHE_TTL_SECONDS', 300, 1, 3600),
    timeoutMs: integer('CATALOG_CACHE_TIMEOUT_MS', 100, 20, 1000),
  };

  if (value('BATCH_API_BASE_URL')) {
    const baseUrl = value('BATCH_API_BASE_URL');
    credentialEndpoint('BATCH_API_BASE_URL', baseUrl, true);
    config.batchClosure = { baseUrl, timeoutMs: integer('BATCH_CLOSURE_TIMEOUT_MS', 3000, 100, 10000) };
  }

  if (value('SUPABASE_URL') || value('SUPABASE_PUBLISHABLE_KEY') || value('SUPABASE_SECRET_KEY')) {
    const supabaseUrl = required('SUPABASE_URL');
    credentialEndpoint('SUPABASE_URL', supabaseUrl, true);
    config.supabase = {
      url: supabaseUrl,
      publishableKey: value('SUPABASE_PUBLISHABLE_KEY', value('SUPABASE_ANON_KEY')) || required('SUPABASE_PUBLISHABLE_KEY'),
      secretKey: value('SUPABASE_SECRET_KEY') || undefined,
    };
  }

  if (value('DATABASE_URL')) {
    const databaseUrl = value('DATABASE_URL');
    const parsed = url('DATABASE_URL', databaseUrl, ['postgres:', 'postgresql:']);
    if (parsed && (!parsed.username || !parsed.pathname.slice(1))) invalid.push('DATABASE_URL');
    config.postgres = {
      url: databaseUrl,
      caFile: value('DATABASE_SSL_CA_FILE') || undefined,
      caPem: value('DATABASE_SSL_CA_PEM') || undefined,
    };
  } else if (value('DATABASE_SSL_CA_FILE') || value('DATABASE_SSL_CA_PEM')) invalid.push('DATABASE_URL');

  if (value('REDIS_URL')) {
    const redisUrl = value('REDIS_URL');
    const parsed = url('REDIS_URL', redisUrl, ['redis:', 'rediss:']);
    if (parsed?.hostname.endsWith('.upstash.io') && parsed.protocol !== 'rediss:') {
      invalid.push('REDIS_URL');
    }
    config.redis = { url: redisUrl };
  }

  if (['R2_ENDPOINT', 'R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY'].some((key) => value(key))) {
    let endpoint = value('R2_ENDPOINT');
    const bucket = value('R2_BUCKET_NAME', value('R2_BUCKET')) || required('R2_BUCKET_NAME');
    if (!endpoint && value('R2_ACCOUNT_ID')) {
      const accountId = value('R2_ACCOUNT_ID');
      if (!/^[a-f\d]{32}$/i.test(accountId)) invalid.push('R2_ACCOUNT_ID');
      endpoint = `https://${accountId}.r2.cloudflarestorage.com`;
    }
    const parsedEndpoint = credentialEndpoint('R2_ENDPOINT', endpoint);
    if (parsedEndpoint) {
      // The dashboard can provide an S3 URL with the selected bucket appended.
      // S3Client adds Bucket itself, so normalize only that exact suffix.
      const path = parsedEndpoint.pathname.replace(/^\/+|\/+$/g, '');
      if (path && path !== encodeURIComponent(bucket)) invalid.push('R2_ENDPOINT');
      endpoint = parsedEndpoint.origin;
    }
    config.r2 = {
      endpoint, region: value('R2_REGION', 'auto'), bucket,
      accessKeyId: required('R2_ACCESS_KEY_ID'), secretAccessKey: required('R2_SECRET_ACCESS_KEY'),
      signedUrlTtlSeconds: integer('R2_SIGNED_URL_TTL_SECONDS', 300, 1, 604800),
      publicProbeBaseUrl: value('R2_PUBLIC_BASE_URL') || undefined,
    };
    if (config.r2.publicProbeBaseUrl) credentialEndpoint('R2_PUBLIC_BASE_URL', config.r2.publicProbeBaseUrl, true);
  }

  if (value('REPORT_EXPORT_ENABLED') === 'true' && (environment === 'production' || value('SOBATNIRA_MODE') === 'connected')) {
    if (!config.r2) invalid.push('R2_ENDPOINT');
    if (!config.r2?.publicProbeBaseUrl) invalid.push('R2_PUBLIC_BASE_URL');
  }

  if (invalid.length) throw new ConfigurationError(invalid);
  return config;
}
