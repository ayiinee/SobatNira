const assert = require('node:assert/strict');
const { mkdtempSync, mkdirSync, writeFileSync, rmSync } = require('node:fs');
const { resolve } = require('node:path');
const test = require('node:test');
const { ConfigurationError, loadConfiguration } = require('../dist/config/backend.config.js');
const { postgresClientOptions } = require('../dist/connections/connection-checks.js');

test('loads a chosen env file without mutating process env, with deployment overrides', () => {
  const base = resolve(__dirname, '../../../.tmp');
  mkdirSync(base, { recursive: true });
  const directory = mkdtempSync(resolve(base, 'api-config-'));
  const file = resolve(directory, '.env');
  try {
    writeFileSync(file, 'API_PORT=3100\nAPP_NAME="Fixture App"\nAI_BASE_URL=http://127.0.0.1:8100\n');
    const before = process.env.APP_NAME;
    const config = loadConfiguration({ envFile: file, env: { API_PORT: '3200' } });
    assert.equal(config.port, 3200);
    assert.equal(config.appName, 'Fixture App');
    assert.equal(config.aiBaseUrl, 'http://127.0.0.1:8100');
    assert.equal(process.env.APP_NAME, before);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test('starter runs without cloud credentials and retains local defaults', () => {
  const config = loadConfiguration({ envFile: false, env: {} });
  assert.equal(config.host, '127.0.0.1');
  assert.equal(config.port, 3000);
  assert.equal(config.aiTimeoutMs, 3000);
  assert.equal(config.supabase, undefined);
  assert.equal(config.postgres, undefined);
  assert.equal(config.r2, undefined);
  assert.equal(config.redis, undefined);
});

test('rejects malformed/partial configuration while redacting supplied values', () => {
  const secret = 'synthetic-secret-never-log';
  assert.throws(() => loadConfiguration({ envFile: false, env: {
    API_PORT: '8000oops', NODE_ENV: 'invalid', LOG_LEVEL: 'invalid', API_HOST: 'not a host',
    DATABASE_URL: `https://user:${secret}@example.invalid/db`,
    REDIS_URL: `https://default:${secret}@example.invalid`,
    SUPABASE_URL: 'https://example.invalid',
    R2_ACCESS_KEY_ID: secret,
  } }), (error) => {
    assert.ok(error instanceof ConfigurationError);
    for (const key of ['API_PORT', 'NODE_ENV', 'LOG_LEVEL', 'API_HOST', 'DATABASE_URL',
      'REDIS_URL', 'SUPABASE_PUBLISHABLE_KEY', 'R2_ENDPOINT', 'R2_SECRET_ACCESS_KEY']) {
      assert.ok(error.fields.includes(key), key);
    }
    assert.ok(!error.message.includes(secret));
    assert.ok(!error.message.includes('example.invalid'));
    return true;
  });
});

test('validates CORS origins and requires TLS for Upstash Redis', () => {
  assert.throws(() => loadConfiguration({ envFile: false, env: { CORS_ORIGINS: '*' } }), ConfigurationError);
  assert.throws(() => loadConfiguration({ envFile: false, env: {
    REDIS_URL: 'redis://default:synthetic@fixture.upstash.io:6379',
  } }), ConfigurationError);
  const config = loadConfiguration({ envFile: false, env: {
    REDIS_URL: 'rediss://default:synthetic@fixture.upstash.io:6379',
    FRONTEND_ORIGIN: 'http://localhost:8080/',
  } });
  assert.deepEqual(config.corsOrigins, ['http://localhost:8080']);
});

test('does not send Supabase or R2 credentials over external plaintext HTTP', () => {
  assert.throws(() => loadConfiguration({ envFile: false, env: {
    SUPABASE_URL: 'http://example.invalid', SUPABASE_PUBLISHABLE_KEY: 'synthetic',
  } }), ConfigurationError);
  assert.throws(() => loadConfiguration({ envFile: false, env: {
    R2_ENDPOINT: 'http://example.invalid', R2_BUCKET_NAME: 'synthetic',
    R2_ACCESS_KEY_ID: 'synthetic', R2_SECRET_ACCESS_KEY: 'synthetic',
  } }), ConfigurationError);
});

test('PostgreSQL TLS verification cannot be disabled by remote URL parameters', () => {
  const config = loadConfiguration({ envFile: false, env: {
    DATABASE_URL: 'postgresql://user:synthetic@example.invalid/db?sslmode=no-verify&uselibpqcompat=true',
  } });
  const options = postgresClientOptions(config);
  assert.equal(options.ssl.rejectUnauthorized, true);
  assert.equal(new URL(options.connectionString).searchParams.has('sslmode'), false);
  assert.equal(new URL(options.connectionString).searchParams.has('uselibpqcompat'), false);
  const local = loadConfiguration({ envFile: false, env: {
    DATABASE_URL: 'postgresql://user:synthetic@127.0.0.1/db',
  } });
  assert.equal(postgresClientOptions(local).ssl, false);
});

test('R2 endpoint can be derived from an account ID, without requiring public access', () => {
  const config = loadConfiguration({ envFile: false, env: {
    R2_ACCOUNT_ID: 'a'.repeat(32), R2_BUCKET_NAME: 'synthetic',
    R2_ACCESS_KEY_ID: 'synthetic', R2_SECRET_ACCESS_KEY: 'synthetic',
  } });
  assert.equal(config.r2.endpoint, `https://${'a'.repeat(32)}.r2.cloudflarestorage.com`);
  assert.equal(config.r2.region, 'auto');
  assert.equal(config.r2.signedUrlTtlSeconds, 300);
});

test('normalizes a dashboard R2 endpoint containing the configured bucket suffix', () => {
  const env = {
    R2_ENDPOINT: 'https://synthetic.r2.cloudflarestorage.com/synthetic-bucket',
    R2_BUCKET_NAME: 'synthetic-bucket', R2_ACCESS_KEY_ID: 'synthetic', R2_SECRET_ACCESS_KEY: 'synthetic',
  };
  assert.equal(loadConfiguration({ envFile: false, env }).r2.endpoint,
    'https://synthetic.r2.cloudflarestorage.com');
  assert.throws(() => loadConfiguration({ envFile: false, env: {
    ...env, R2_ENDPOINT: 'https://synthetic.r2.cloudflarestorage.com/another-bucket',
  } }), ConfigurationError);
});
