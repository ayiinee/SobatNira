const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');
const { createServer } = require('node:http');
const test = require('node:test');
const { Client } = require('pg');
const { loadConfiguration } = require('../../dist/config/backend.config');
const { postgresClientOptions } = require('../../dist/database/postgres.config');
const { AccessRepository } = require('../../dist/auth/access.repository');
const { createApplication } = require('../../dist/application');
const { DatabaseService } = require('../../dist/database/database.service');

test('PostgreSQL enforces scoped roles, active memberships, foreign keys and browser isolation', async () => {
  const config = loadConfiguration();
  assert.ok(config.postgres, 'DATABASE_URL is required for this explicit integration test');
  const client = new Client(postgresClientOptions(config));
  client.on('error', () => {});
  const repository = new AccessRepository({ query: (sql, values) => client.query(sql, values) });
  let app;
  let authServer;
  const [tenantA, tenantB, factoryA, factoryB, factoryC, owner, admin, outsider] = Array.from({ length: 8 }, () => randomUUID());
  try {
    await client.connect();
    const hooks = await client.query("SELECT count(*)::int AS count FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal");
    assert.equal(hooks.rows[0].count, 0, 'Inspect auth.users hooks before creating transactional synthetic users');
    await client.query('BEGIN');
    // These synthetic Auth rows remain uncommitted and are always rolled back.
    // No signup API, invitation, email or persistent account is created.
    for (const id of [owner, admin, outsider]) {
      await client.query(`INSERT INTO auth.users(id, aud, role, email, created_at, updated_at)
        VALUES ($1, 'authenticated', 'authenticated', $2, now(), now())`,
      [id, `synthetic-${id}@example.invalid`]);
    }
    await client.query("INSERT INTO sobatnira.tenants(id, name) VALUES ($1, 'Synthetic A'), ($2, 'Synthetic B')", [tenantA, tenantB]);
    await client.query(`INSERT INTO sobatnira.factories(id, tenant_id, name) VALUES
      ($1, $2, 'Synthetic Factory A'), ($3, $2, 'Synthetic Factory B'), ($4, $5, 'Synthetic Factory C')`,
    [factoryA, tenantA, factoryB, factoryC, tenantB]);
    await client.query(`INSERT INTO sobatnira.tenant_memberships(tenant_id, user_id) VALUES
      ($1, $3), ($1, $4), ($2, $3), ($2, $4)`, [tenantA, tenantB, owner, admin]);
    await client.query(`INSERT INTO sobatnira.factory_memberships(tenant_id, factory_id, user_id, role) VALUES
      ($1, $2, $3, 'owner'), ($1, $2, $4, 'admin'), ($5, $6, $4, 'owner')`,
    [tenantA, factoryA, owner, admin, tenantB, factoryC]);

    assert.equal((await repository.listAccess(owner)).length, 1);
    assert.equal((await repository.listAccess(admin)).length, 2);
    assert.deepEqual(await repository.listAccess(outsider), []);
    const ownerAccess = await repository.findFactoryAccess(owner, tenantA, factoryA);
    const adminAccess = await repository.findFactoryAccess(admin, tenantA, factoryA);
    assert.equal(ownerAccess.role, 'owner');
    assert.equal(adminAccess.role, 'admin');
    assert.equal(await repository.findFactoryAccess(owner, tenantB, factoryA), undefined);
    assert.equal(await repository.findFactoryAccess(owner, tenantA, factoryB), undefined);
    assert.equal(await repository.findFactoryAccess(owner, tenantB, factoryC), undefined);
    assert.equal((await repository.listFactoryMembers(ownerAccess)).length, 2);
    assert.deepEqual(await repository.listFactoryMembers(adminAccess), []);

    authServer = createServer((request, response) => {
      const userId = request.headers.authorization === 'Bearer owner-synthetic' ? owner : admin;
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify({ id: userId, aud: 'authenticated' }));
    });
    authServer.listen(0, '127.0.0.1');
    await once(authServer, 'listening');
    app = await createApplication({ envFile: false, env: {
      SUPABASE_URL: `http://127.0.0.1:${authServer.address().port}`,
      SUPABASE_PUBLISHABLE_KEY: 'synthetic-key', LOG_LEVEL: 'silent',
    } });
    // Use this transaction for the real repository so no fixture needs committing.
    app.get(DatabaseService).query = (sql, values) => client.query(sql, values);
    await app.listen(0, '127.0.0.1');
    const base = await app.getUrl();
    const route = `/tenants/${tenantA}/factories/${factoryA}`;
    const request = (suffix, token = 'owner-synthetic') => fetch(base + suffix, {
      headers: { Authorization: `Bearer ${token}` },
    });
    assert.equal((await request(route)).status, 200);
    assert.equal((await request(route + '/memberships')).status, 200);
    assert.equal((await request(route + '/memberships', 'admin-synthetic')).status, 403);
    assert.equal((await request(`/tenants/${tenantB}/factories/${factoryA}`)).status, 403);
    assert.equal((await request(`/tenants/${tenantA}/factories/${factoryB}`)).status, 403);

    for (const [table, predicate, values] of [
      ['tenants', 'id = $1', [tenantA]],
      ['factories', 'id = $1', [factoryA]],
      ['tenant_memberships', 'tenant_id = $1 AND user_id = $2', [tenantA, owner]],
      ['factory_memberships', 'tenant_id = $1 AND user_id = $2 AND factory_id = $3', [tenantA, owner, factoryA]],
    ]) {
      // Table/predicate values are fixed test constants, never user input.
      await client.query(`UPDATE sobatnira.${table} SET is_active = false WHERE ${predicate}`, values);
      assert.equal(await repository.findFactoryAccess(owner, tenantA, factoryA), undefined, table);
      assert.deepEqual(await repository.listAccess(owner), [], table);
      assert.equal((await request(route)).status, 403, table);
      await client.query(`UPDATE sobatnira.${table} SET is_active = true WHERE ${predicate}`, values);
    }
    await client.query("UPDATE sobatnira.factory_memberships SET role = 'admin' WHERE user_id = $1", [owner]);
    assert.equal((await repository.findFactoryAccess(owner, tenantA, factoryA)).role, 'admin');
    // A stale guard context must not permit a role-restricted query after demotion.
    assert.deepEqual(await repository.listFactoryMembers(ownerAccess), []);
    assert.equal((await request(route + '/memberships')).status, 403);

    async function rejected(sql, values, code) {
      await client.query('SAVEPOINT expected_rejection');
      await assert.rejects(client.query(sql, values), (error) => error.code === code);
      await client.query('ROLLBACK TO SAVEPOINT expected_rejection');
    }
    await rejected(`INSERT INTO sobatnira.factory_memberships(tenant_id, factory_id, user_id, role)
      VALUES ($1, $2, $3, 'admin')`, [tenantB, factoryA, owner], '23503');
    await rejected("UPDATE sobatnira.factory_memberships SET role = 'superadmin' WHERE user_id = $1", [owner], '23514');
    await rejected('INSERT INTO sobatnira.tenant_memberships(tenant_id, user_id) VALUES ($1, $2)', [tenantA, randomUUID()], '23503');

    const rls = await client.query(`SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'sobatnira'
      AND tablename IN ('tenants', 'factories', 'tenant_memberships', 'factory_memberships')`);
    assert.equal(rls.rows.length, 4);
    assert.ok(rls.rows.every((table) => table.rowsecurity));
    for (const role of ['anon', 'authenticated']) {
      await client.query('SAVEPOINT browser_access');
      await client.query(`SET LOCAL ROLE ${role}`);
      await assert.rejects(client.query('SELECT * FROM sobatnira.factory_memberships'), (error) => error.code === '42501');
      await client.query('ROLLBACK TO SAVEPOINT browser_access');
    }
  } finally {
    await app?.close();
    if (authServer) {
      authServer.closeAllConnections();
      await new Promise((done) => authServer.close(done));
    }
    await client.query('ROLLBACK').catch(() => {});
    await client.end();
  }
});

test('live Supabase rejects an invalid access token through the configured NestJS backend', { skip: process.env.TEST_LIVE_AUTH !== 'true' }, async () => {
  const app = await createApplication();
  try {
    await app.listen(0, '127.0.0.1');
    const response = await fetch(`${await app.getUrl()}/auth/me`, {
      headers: { Authorization: 'Bearer synthetic-invalid-access-token' },
    });
    assert.equal(response.status, 401);
    assert.ok(!(await response.text()).includes('synthetic-invalid-access-token'));
  } finally { await app.close(); }
});
