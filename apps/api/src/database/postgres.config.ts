import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { ClientConfig } from 'pg';
import { BackendConfig, DEFAULT_ENV_FILE, isLoopback } from '../config/backend.config';

export function postgresClientOptions(config: BackendConfig): ClientConfig {
  const settings = config.postgres!;
  const url = new URL(settings.url);
  const useTls = !isLoopback(url.hostname) || settings.caFile !== undefined ||
    ['require', 'verify-ca', 'verify-full'].includes(url.searchParams.get('sslmode') ?? '');
  // URL parameters must not replace the verified TLS configuration.
  for (const key of ['ssl', 'sslmode', 'sslcert', 'sslkey', 'sslrootcert', 'uselibpqcompat']) {
    url.searchParams.delete(key);
  }
  return {
    connectionString: url.toString(),
    ssl: useTls ? {
      rejectUnauthorized: true,
      ...(settings.caFile ? {
        ca: readFileSync(resolve(dirname(DEFAULT_ENV_FILE), settings.caFile), 'utf8'),
      } : {}),
    } : false,
    connectionTimeoutMillis: config.timeoutMs,
    query_timeout: config.timeoutMs,
    statement_timeout: config.timeoutMs,
    application_name: 'sobatnira-api',
  };
}
