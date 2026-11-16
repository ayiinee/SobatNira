import { HeadBucketCommand, S3Client } from '@aws-sdk/client-s3';
import { Redis } from 'ioredis';
import { Client } from 'pg';
import { BackendConfig } from '../config/backend.config';
import { postgresClientOptions } from '../database/postgres.config';
export { postgresClientOptions } from '../database/postgres.config';

export type ConnectionName = 'supabase' | 'postgresql' | 'r2' | 'redis' | 'fastapi';
export interface ConnectionResult {
  service: ConnectionName;
  status: 'ok' | 'failed' | 'not_configured';
  durationMs: number;
  message: string;
}
export type ConnectionProbe = () => Promise<void>;
export type ConnectionProbes = Partial<Record<ConnectionName, ConnectionProbe>>;

class ProbeError extends Error {
  constructor(readonly safeMessage: string) { super(safeMessage); }
}

async function fetchJson(url: URL, timeoutMs: number, headers?: Record<string, string>) {
  const response = await fetch(url, {
    headers, signal: AbortSignal.timeout(timeoutMs), redirect: 'error',
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new ProbeError(`HTTP ${response.status}; periksa layanan, kredensial dan izin.`);
  }
  return response.json() as Promise<Record<string, unknown>>;
}

export function createConnectionProbes(config: BackendConfig): ConnectionProbes {
  const probes: ConnectionProbes = {};
  const timeout = config.timeoutMs;
  if (config.supabase) {
    const settings = config.supabase;
    probes.supabase = async () => {
      // A read-only Auth request validates the gateway/API keys, not a user session.
      for (const key of [settings.publishableKey, settings.secretKey].filter(Boolean)) {
        const result = await fetchJson(new URL('/auth/v1/settings', settings.url), timeout, {
          apikey: key!,
        });
        if (!result || typeof result.external !== 'object' || result.external === null) {
          throw new ProbeError('Respons Supabase Auth tidak sesuai kontrak.');
        }
      }
    };
  }
  if (config.postgres) {
    probes.postgresql = async () => {
      const client = new Client(postgresClientOptions(config));
      // pg can emit an asynchronous socket error in addition to rejecting a query.
      client.on('error', () => {});
      try {
        await client.connect();
        const result = await client.query('SELECT 1 AS connected');
        if (result.rows[0]?.connected !== 1) throw new ProbeError('Hasil query tidak sesuai.');
      } finally {
        await client.end();
      }
    };
  }
  if (config.r2) {
    const settings = config.r2;
    probes.r2 = async () => {
      const client = new S3Client({
        endpoint: settings.endpoint, region: settings.region, forcePathStyle: true,
        credentials: { accessKeyId: settings.accessKeyId, secretAccessKey: settings.secretAccessKey },
        maxAttempts: 1,
        requestHandler: { connectionTimeout: timeout, requestTimeout: timeout },
      });
      try {
        await client.send(new HeadBucketCommand({ Bucket: settings.bucket }), {
          abortSignal: AbortSignal.timeout(timeout),
        });
      } finally { client.destroy(); }
    };
  }
  if (config.redis) {
    const settings = config.redis;
    probes.redis = async () => {
      const client = new Redis(settings.url, {
        lazyConnect: true, enableOfflineQueue: false, enableReadyCheck: false,
        connectTimeout: timeout, commandTimeout: timeout,
        maxRetriesPerRequest: 0, retryStrategy: () => null,
      });
      client.on('error', () => {});
      try {
        await client.connect();
        if (await client.ping() !== 'PONG') throw new ProbeError('Respons Redis bukan PONG.');
      } finally { client.disconnect(); }
    };
  }
  probes.fastapi = async () => {
    const result = await fetchJson(new URL('/health', config.aiBaseUrl), timeout);
    if (result?.status !== 'ok' || result?.service !== 'sobatnira-ai') {
      throw new ProbeError('Respons health FastAPI tidak sesuai kontrak SobatNira.');
    }
  };
  return probes;
}

function safeFailure(error: unknown): string {
  if (error instanceof ProbeError) return error.safeMessage;
  // Never return provider messages: they may include passwords, URLs or response bodies.
  const candidate = error as { name?: string; code?: string; cause?: { code?: string }; $metadata?: { httpStatusCode?: number } } | null;
  const code = candidate?.code ?? candidate?.cause?.code;
  const known: Record<string, string> = {
    ENOTFOUND: 'DNS tidak ditemukan; periksa endpoint dan jaringan.',
    EAI_AGAIN: 'Resolusi DNS gagal sementara; coba lagi.',
    ENOENT: 'Berkas CA tidak ditemukan; periksa DATABASE_SSL_CA_FILE.',
    ECONNREFUSED: 'Koneksi ditolak; pastikan layanan berjalan dan port benar.',
    ENETUNREACH: 'Jaringan tidak terjangkau; untuk Supabase periksa kebutuhan IPv4/pooler.',
    ETIMEDOUT: 'Koneksi melewati batas waktu.',
    '28P01': 'Autentikasi PostgreSQL ditolak; periksa password dalam DATABASE_URL.',
    '3D000': 'Database tidak ditemukan; periksa DATABASE_URL.',
    SELF_SIGNED_CERT_IN_CHAIN: 'Sertifikat TLS belum dipercaya; periksa DATABASE_SSL_CA_FILE atau CA jaringan.',
    DEPTH_ZERO_SELF_SIGNED_CERT: 'Sertifikat TLS belum dipercaya; periksa CA layanan.',
    UNABLE_TO_VERIFY_LEAF_SIGNATURE: 'Rantai sertifikat TLS tidak dapat diverifikasi; periksa CA layanan.',
    CERT_HAS_EXPIRED: 'Sertifikat TLS kedaluwarsa.',
    ERR_TLS_CERT_ALTNAME_INVALID: 'Hostname tidak cocok dengan sertifikat TLS; periksa endpoint.',
  };
  if (code && known[code]) return known[code];
  if (candidate?.name === 'TimeoutError' || candidate?.name === 'AbortError') {
    return 'Pemeriksaan melewati batas waktu.';
  }
  const httpStatus = candidate?.$metadata?.httpStatusCode;
  if (httpStatus && Number.isInteger(httpStatus)) return `HTTP ${httpStatus}; periksa endpoint, bucket, kredensial dan izin.`;
  return 'Koneksi gagal; periksa endpoint, kredensial, TLS, jaringan dan ketersediaan layanan.';
}

export async function checkConnections(
  config: BackendConfig,
  probes = createConnectionProbes(config),
): Promise<ConnectionResult[]> {
  const services: ConnectionName[] = ['supabase', 'postgresql', 'r2', 'redis', 'fastapi'];
  return Promise.all(services.map(async (service): Promise<ConnectionResult> => {
    const start = performance.now();
    const probe = probes[service];
    if (!probe) return { service, status: 'not_configured', durationMs: 0, message: 'Konfigurasi layanan belum diisi.' };
    try {
      await probe();
      return { service, status: 'ok', durationMs: Math.round(performance.now() - start), message: 'Koneksi berhasil.' };
    } catch (error) {
      return { service, status: 'failed', durationMs: Math.round(performance.now() - start), message: safeFailure(error) };
    }
  }));
}
