const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createServer } = require('node:http');
const test = require('node:test');
const { Controller, Get, Module } = require('@nestjs/common');
const { NestFactory } = require('@nestjs/core');
const { createApplication } = require('../dist/application');
const { AppModule } = require('../dist/app.module');
const { AccessRepository } = require('../dist/auth/access.repository');

const TENANT_A = '10000000-0000-4000-8000-000000000001';
const TENANT_B = '10000000-0000-4000-8000-000000000002';
const FACTORY_A = '20000000-0000-4000-8000-000000000001';
const FACTORY_B = '20000000-0000-4000-8000-000000000002';
const FACTORY_C = '20000000-0000-4000-8000-000000000003';
const OWNER = '30000000-0000-4000-8000-000000000001';
const ADMIN = '30000000-0000-4000-8000-000000000002';
const NO_ACCESS = '30000000-0000-4000-8000-000000000003';
const path = (tenant = TENANT_A, factory = FACTORY_A) => `/tenants/${tenant}/factories/${factory}`;

async function fixture(t) {
  const users = { 'owner-token': OWNER, 'admin-token': ADMIN, 'no-access-token': NO_ACCESS };
  const memberships = [
    { userId: OWNER, tenantId: TENANT_A, tenantName: 'Tenant A', factoryId: FACTORY_A, factoryName: 'Factory A', role: 'owner' },
    { userId: ADMIN, tenantId: TENANT_A, tenantName: 'Tenant A', factoryId: FACTORY_A, factoryName: 'Factory A', role: 'admin' },
    // A role in one factory must never elevate permissions in another.
    { userId: ADMIN, tenantId: TENANT_B, tenantName: 'Tenant B', factoryId: FACTORY_C, factoryName: 'Factory C', role: 'owner' },
  ];
  let authMode = 'normal';
  let authRequests = 0;
  const authServer = createServer((req, res) => {
    authRequests++;
    assert.equal(req.url, '/auth/v1/user');
    assert.equal(req.headers.apikey, 'synthetic-publishable-key');
    if (authMode === 'timeout') return;
    res.setHeader('content-type', 'application/json');
    const token = req.headers.authorization?.replace(/^Bearer /, '');
    if (authMode === 'unavailable') {
      res.writeHead(503);
      res.end(JSON.stringify({ secret: 'private-upstream-detail' }));
    } else if (!users[token]) {
      res.writeHead(401);
      res.end(JSON.stringify({ message: 'expired or tampered private-upstream-detail' }));
    } else {
      res.end(JSON.stringify({ id: authMode === 'invalid-response' ? 'invalid' : users[token],
        aud: 'authenticated', email: 'synthetic@example.invalid',
        user_metadata: { role: 'owner', tenantId: TENANT_B, factoryId: FACTORY_C },
        app_metadata: { role: 'owner' },
      }));
    }
  });
  authServer.listen(0, '127.0.0.1');
  await once(authServer, 'listening');
  const env = { SUPABASE_URL: `http://127.0.0.1:${authServer.address().port}`,
    SUPABASE_PUBLISHABLE_KEY: 'synthetic-publishable-key', LOG_LEVEL: 'silent', CONNECTION_TIMEOUT_MS: '100' };
  const app = await createApplication({ envFile: false, env });
  const repository = app.get(AccessRepository);
  let databaseReads = 0;
  repository.listAccess = async (userId) => { databaseReads++; return memberships.filter((m) => m.userId === userId); };
  repository.findFactoryAccess = async (userId, tenantId, factoryId) => {
    databaseReads++;
    return memberships.find((m) => m.userId === userId && m.tenantId === tenantId && m.factoryId === factoryId);
  };
  repository.factoryProfile = async (access) => ({ ...access, profileVersion: 1 });
  repository.listFactoryMembers = async (access) => memberships
    .filter((m) => m.tenantId === access.tenantId && m.factoryId === access.factoryId)
    .map((m) => ({ userId: m.userId, role: m.role, isActive: true }));
  await app.listen(0, '127.0.0.1');
  const base = await app.getUrl();
  t.after(async () => {
    await app.close();
    authServer.closeAllConnections();
    await new Promise((done) => authServer.close(done));
  });
  return {
    app, env, memberships,
    setAuthMode: (mode) => { authMode = mode; },
    reads: () => ({ authRequests, databaseReads }),
    request: (route, token, extraHeaders = {}) => fetch(base + route, {
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...extraHeaders },
    }),
  };
}

test('requires a Bearer token before querying Supabase or memberships', async (t) => {
  const f = await fixture(t);
  for (const header of [undefined, 'Basic secret', 'Bearer', 'Bearer first, Bearer second']) {
    const response = await f.request('/auth/me', undefined, header ? { Authorization: header } : {});
    assert.equal(response.status, 401);
  }
  assert.deepEqual(f.reads(), { authRequests: 0, databaseReads: 0 });
});

test('rejects invalid/expired tokens without leaking upstream response bodies', async (t) => {
  const f = await fixture(t);
  for (const token of ['expired-token', 'tampered-token', 'api-key-is-not-a-user-token']) {
    const response = await f.request('/auth/me', token);
    assert.equal(response.status, 401);
    assert.ok(!(await response.text()).includes('private-upstream-detail'));
  }
  assert.equal(f.reads().databaseReads, 0);
});

test('me returns only the verified identity and current memberships, ignoring client metadata', async (t) => {
  const f = await fixture(t);
  const response = await f.request(`/auth/me?userId=${OWNER}&role=owner`, 'admin-token', { 'x-user-id': OWNER, 'x-role': 'owner' });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.user.id, ADMIN);
  assert.equal(result.access.find((m) => m.factoryId === FACTORY_A).role, 'admin');
  assert.ok(result.access.every((m) => m.userId === ADMIN));
  assert.equal(result.user.user_metadata, undefined);
  assert.equal(result.user.app_metadata, undefined);
  assert.ok(!JSON.stringify(result).includes('admin-token'));
});

test('allows admin and owner in their factory, but restricts membership listing to owner there', async (t) => {
  const f = await fixture(t);
  for (const token of ['owner-token', 'admin-token']) {
    assert.equal((await f.request(path(), token)).status, 200);
  }
  assert.equal((await f.request(path() + '/memberships', 'admin-token')).status, 403);
  const owner = await f.request(path() + '/memberships', 'owner-token');
  assert.equal(owner.status, 200);
  assert.equal((await owner.json()).memberships.length, 2);
  // This user is owner at factory C and admin at A: roles remain scoped.
  assert.equal((await f.request(path(TENANT_B, FACTORY_C) + '/memberships', 'admin-token')).status, 200);
});

test('browser preflight permits the Authorization header without requiring a token', async (t) => {
  const f = await fixture(t);
  const base = await f.app.getUrl();
  const response = await fetch(base + '/auth/me', { method: 'OPTIONS', headers: {
    Origin: 'http://localhost:8080', 'Access-Control-Request-Method': 'GET',
    'Access-Control-Request-Headers': 'authorization',
  } });
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('access-control-allow-origin'), 'http://localhost:8080');
  assert.match(response.headers.get('access-control-allow-headers'), /authorization/i);
  assert.deepEqual(f.reads(), { authRequests: 0, databaseReads: 0 });
});

test('denies cross-tenant/factory access, malformed IDs and spoofed scope headers', async (t) => {
  const f = await fixture(t);
  const routes = [path(TENANT_B, FACTORY_A), path(TENANT_A, FACTORY_B), path(TENANT_B, FACTORY_C), path('invalid', FACTORY_A)];
  for (const route of routes) {
    const response = await f.request(route + '?role=owner', 'owner-token', {
      'x-tenant-id': TENANT_A, 'x-factory-id': FACTORY_A, 'x-role': 'owner',
    });
    assert.equal(response.status, 403);
    assert.ok(!(await response.text()).includes('Factory C'));
  }
  assert.equal((await f.request(path(), 'no-access-token')).status, 403);
  const empty = await f.request('/auth/me', 'no-access-token');
  assert.equal(empty.status, 200);
  assert.deepEqual((await empty.json()).access, []);
});

test('revoked access or a role change takes effect on the next request with the same token', async (t) => {
  const f = await fixture(t);
  assert.equal((await f.request(path() + '/memberships', 'owner-token')).status, 200);
  f.memberships[0].role = 'admin';
  assert.equal((await f.request(path() + '/memberships', 'owner-token')).status, 403);
  f.memberships.splice(0, 1);
  assert.equal((await f.request(path(), 'owner-token')).status, 403);
});

test('auth outages, timeouts and malformed provider responses fail closed as 503', async (t) => {
  const f = await fixture(t);
  for (const mode of ['unavailable', 'timeout', 'invalid-response']) {
    f.setAuthMode(mode);
    const response = await f.request(path(), 'owner-token');
    assert.equal(response.status, 503, mode);
    assert.ok(!(await response.text()).includes('private-upstream-detail'));
  }
  assert.equal(f.reads().databaseReads, 0);
});

test('protected endpoints fail closed when Supabase is not configured', async (t) => {
  const app = await createApplication({ envFile: false, env: { LOG_LEVEL: 'silent' } });
  t.after(() => app.close());
  await app.listen(0, '127.0.0.1');
  assert.equal((await fetch(`${await app.getUrl()}/auth/me`)).status, 401);
  assert.equal((await fetch(`${await app.getUrl()}/auth/me`, { headers: { Authorization: 'Bearer synthetic' } })).status, 503);
});

test('new endpoints without an explicit access policy are denied by the global guard', async (t) => {
  const f = await fixture(t);
  class UndeclaredController { read() { return { shouldNotBeReturned: true }; } }
  Controller('undeclared')(UndeclaredController);
  Get()(UndeclaredController.prototype, 'read', Object.getOwnPropertyDescriptor(UndeclaredController.prototype, 'read'));
  class FixtureModule {}
  Module({ imports: [AppModule.register({ envFile: false, env: f.env })], controllers: [UndeclaredController] })(FixtureModule);
  const app = await NestFactory.create(FixtureModule, { logger: false });
  t.after(() => app.close());
  await app.listen(0, '127.0.0.1');
  assert.equal((await fetch(`${await app.getUrl()}/undeclared`, {
    headers: { Authorization: 'Bearer owner-token' },
  })).status, 403);
});

test('synthetic demo remains available for development and is disabled in production', async (t) => {
  const app = await createApplication({ envFile: false, env: { NODE_ENV: 'production', LOG_LEVEL: 'silent' } });
  t.after(() => app.close());
  await app.listen(0, '127.0.0.1');
  assert.equal((await fetch(`${await app.getUrl()}/health`)).status, 200);
  assert.equal((await fetch(`${await app.getUrl()}/demo/draft`)).status, 404);
});
