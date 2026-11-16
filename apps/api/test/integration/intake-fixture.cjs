const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');
const { createServer } = require('node:http');
const { Client } = require('pg');
const { createApplication } = require('../../dist/application');
const { loadConfiguration } = require('../../dist/config/backend.config');
const { postgresClientOptions } = require('../../dist/database/postgres.config');
const { DatabaseService } = require('../../dist/database/database.service');
const { useTransactionFixture } = require('./database-fixture.cjs');

async function intakeFixture(committed = false, extraEnv = {}) {
  const config = loadConfiguration();
  assert.notEqual(config.environment, 'production', 'Run synthetic integration fixtures on a development database');
  const client = new Client(postgresClientOptions(config));
  client.on('error', () => {});
  const ids = Object.fromEntries(['tenant', 'otherTenant', 'factory', 'siblingFactory', 'otherFactory', 'admin', 'owner',
    'supplier', 'replacementSupplier', 'otherSupplier', 'lot', 'secondLot', 'thirdLot', 'siblingLot', 'otherLot'].map((key) => [key, randomUUID()]));
  let app, authServer, seeded = false;
  const close = async () => {
    await app?.close();
    if (authServer) { authServer.closeAllConnections(); await new Promise((done) => authServer.close(done)); }
    try {
      if (!committed || !seeded) await client.query('ROLLBACK');
      else {
        // Only this fixture's freshly inserted, randomly identified tenants are removed.
        await client.query('BEGIN');
        await client.query('SET CONSTRAINTS ALL DEFERRED');
        for (const table of ['sugarcane_stock_movements', 'intake_records', 'intake_document_events', 'intake_document_revisions',
          'intake_evidence', 'intake_documents', 'production_audit_events', 'lots', 'suppliers', 'factory_memberships', 'tenant_memberships', 'factories']) {
          await client.query(`DELETE FROM sobatnira.${table} WHERE tenant_id IN ($1, $2)`, [ids.tenant, ids.otherTenant]);
        }
        await client.query('DELETE FROM sobatnira.tenants WHERE id IN ($1, $2)', [ids.tenant, ids.otherTenant]);
        await client.query('DELETE FROM auth.users WHERE id IN ($1, $2)', [ids.admin, ids.owner]);
        await client.query('COMMIT');
      }
    } finally { await client.end(); }
  };
  try {
    await client.connect();
    const hooks = await client.query("SELECT count(*)::int AS count FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal");
    assert.equal(hooks.rows[0].count, 0, 'Inspect auth.users hooks before synthetic integration fixtures');
    const installed = await client.query("SELECT to_regclass('sobatnira.intake_evidence') IS NOT NULL AS installed");
    assert.ok(installed.rows[0].installed, 'Run npm run db:migrate before test:intake-db');
    await client.query('BEGIN');
    for (const user of [ids.admin, ids.owner]) {
      await client.query("INSERT INTO auth.users(id, aud, role, email) VALUES ($1, 'authenticated', 'authenticated', $2)",
        [user, `synthetic-${user}@example.invalid`]);
    }
    await client.query("INSERT INTO sobatnira.tenants(id, name) VALUES ($1, 'Synthetic intake tenant'), ($2, 'Synthetic other tenant')", [ids.tenant, ids.otherTenant]);
    await client.query(`INSERT INTO sobatnira.factories(id, tenant_id, name) VALUES
      ($1, $2, 'Synthetic factory'), ($3, $2, 'Synthetic sibling'), ($4, $5, 'Synthetic other')`,
    [ids.factory, ids.tenant, ids.siblingFactory, ids.otherFactory, ids.otherTenant]);
    await client.query('INSERT INTO sobatnira.tenant_memberships(tenant_id, user_id) VALUES ($1, $3), ($2, $3), ($1, $4)',
      [ids.tenant, ids.otherTenant, ids.admin, ids.owner]);
    await client.query(`INSERT INTO sobatnira.factory_memberships(tenant_id, factory_id, user_id, role) VALUES
      ($1, $2, $6, 'admin'), ($1, $3, $6, 'admin'), ($4, $5, $6, 'admin'), ($1, $2, $7, 'owner')`,
    [ids.tenant, ids.factory, ids.siblingFactory, ids.otherTenant, ids.otherFactory, ids.admin, ids.owner]);
    await client.query(`INSERT INTO sobatnira.suppliers(id, tenant_id, name) VALUES
      ($1, $2, 'Synthetic supplier'), ($3, $2, 'Synthetic replacement'), ($4, $5, 'Synthetic other')`,
    [ids.supplier, ids.tenant, ids.replacementSupplier, ids.otherSupplier, ids.otherTenant]);
    for (const lot of [ids.lot, ids.secondLot, ids.thirdLot]) {
      await client.query("INSERT INTO sobatnira.lots(id, tenant_id, factory_id, supplier_id, received_at) VALUES ($1, $2, $3, $4, '2026-11-16T01:00:00Z')",
        [lot, ids.tenant, ids.factory, ids.supplier]);
    }
    await client.query(`INSERT INTO sobatnira.lots(id, tenant_id, factory_id, supplier_id, received_at) VALUES
      ($1, $2, $3, $4, '2026-11-16T01:00:00Z'), ($5, $6, $7, $8, '2026-11-16T01:00:00Z')`,
    [ids.siblingLot, ids.tenant, ids.siblingFactory, ids.supplier, ids.otherLot, ids.otherTenant, ids.otherFactory, ids.otherSupplier]);
    if (committed) { await client.query('COMMIT'); seeded = true; }

    authServer = createServer((req, res) => {
      const token = req.headers.authorization;
      res.setHeader('Content-Type', 'application/json');
      if (!['Bearer fixture-admin', 'Bearer fixture-owner'].includes(token)) { res.writeHead(401); res.end('{}'); return; }
      res.end(JSON.stringify({ id: token === 'Bearer fixture-owner' ? ids.owner : ids.admin, aud: 'authenticated' }));
    });
    authServer.listen(0, '127.0.0.1');
    await once(authServer, 'listening');
    const env = { SUPABASE_URL: `http://127.0.0.1:${authServer.address().port}`, SUPABASE_PUBLISHABLE_KEY: 'synthetic-key', LOG_LEVEL: 'silent', ...extraEnv };
    app = await createApplication(committed ? { env } : { envFile: false, env });
    if (!committed) useTransactionFixture(app.get(DatabaseService), client);
    await app.listen(0, '127.0.0.1');
    const base = await app.getUrl();
    const root = `/tenants/${ids.tenant}/factories/${ids.factory}`;
    const siblingRoot = `/tenants/${ids.tenant}/factories/${ids.siblingFactory}`;
    const otherRoot = `/tenants/${ids.otherTenant}/factories/${ids.otherFactory}`;
    const request = async (path, method = 'GET', body, token = 'fixture-admin') => {
      const response = await fetch(base + path, { method,
        headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      return { status: response.status, body: await response.json() };
    };
    const create = (lotId = ids.lot, requestId = randomUUID()) => request(root + '/intake-documents/synthetic', 'POST', { lotId, requestId });
    return { ids, client, app, base, root, siblingRoot, otherRoot, request, create, close };
  } catch (error) { await close(); throw error; }
}

module.exports = { intakeFixture };
