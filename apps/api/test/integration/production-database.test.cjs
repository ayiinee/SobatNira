const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { createServer } = require('node:http');
const test = require('node:test');
const { Client } = require('pg');
const { createApplication } = require('../../dist/application');
const { loadConfiguration } = require('../../dist/config/backend.config');
const { postgresClientOptions } = require('../../dist/database/postgres.config');
const { DatabaseService } = require('../../dist/database/database.service');
const { CaneTypesRepository } = require('../../dist/cane-types/cane-types.repository');
const { SuppliersRepository } = require('../../dist/suppliers/suppliers.repository');
const { useTransactionFixture } = require('./database-fixture.cjs');

test('production master data and lot HTTP flows enforce scope, filters and atomic audit', async () => {
  const client = new Client(postgresClientOptions(loadConfiguration()));
  client.on('error', () => {});
  const [tenantA, tenantB, factoryA, factoryB, factoryC, user] = Array.from({ length: 6 }, () => randomUUID());
  let app, authServer;
  try {
    await client.connect();
    const hooks = await client.query("SELECT count(*)::int AS count FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal");
    assert.equal(hooks.rows[0].count, 0, 'Inspect auth.users hooks before transactional synthetic data');
    await client.query('BEGIN');
    const installed = await client.query("SELECT to_regclass('sobatnira.lots') IS NOT NULL AS installed");
    if (!installed.rows[0].installed) {
      await client.query(readFileSync(resolve(__dirname, '../../migrations/002_suppliers_lots.sql'), 'utf8'));
    }
    const intakeInstalled = await client.query("SELECT to_regclass('sobatnira.intake_records') IS NOT NULL AS installed");
    if (!intakeInstalled.rows[0].installed) {
      await client.query(readFileSync(resolve(__dirname, '../../migrations/003_intake_documents.sql'), 'utf8'));
    }
    const catalogueInstalled = await client.query("SELECT to_regclass('sobatnira.cane_types') IS NOT NULL AS installed");
    if (!catalogueInstalled.rows[0].installed) {
      await client.query(readFileSync(resolve(__dirname, '../../migrations/016_cane_type_catalog.sql'), 'utf8'));
    }
    await client.query(`INSERT INTO auth.users(id, aud, role, email) VALUES ($1, 'authenticated', 'authenticated', $2)`,
      [user, `synthetic-${user}@example.invalid`]);
    await client.query("INSERT INTO sobatnira.tenants(id, name) VALUES ($1, 'Synthetic A'), ($2, 'Synthetic B')", [tenantA, tenantB]);
    await client.query(`INSERT INTO sobatnira.factories(id, tenant_id, name) VALUES
      ($1, $2, 'Synthetic A'), ($3, $2, 'Synthetic B'), ($4, $5, 'Synthetic C')`, [factoryA, tenantA, factoryB, factoryC, tenantB]);
    await client.query('INSERT INTO sobatnira.tenant_memberships(tenant_id, user_id) VALUES ($1, $3), ($2, $3)', [tenantA, tenantB, user]);
    await client.query(`INSERT INTO sobatnira.factory_memberships(tenant_id, factory_id, user_id, role) VALUES
      ($1, $2, $5, 'admin'), ($1, $3, $5, 'admin'), ($4, $6, $5, 'admin')`, [tenantA, factoryA, factoryB, tenantB, user, factoryC]);

    authServer = createServer((_req, res) => {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ id: user, aud: 'authenticated' }));
    });
    authServer.listen(0, '127.0.0.1');
    await once(authServer, 'listening');
    app = await createApplication({ envFile: false, env: {
      SUPABASE_URL: `http://127.0.0.1:${authServer.address().port}`, SUPABASE_PUBLISHABLE_KEY: 'synthetic-key', LOG_LEVEL: 'silent',
    } });
    useTransactionFixture(app.get(DatabaseService), client);
    await app.listen(0, '127.0.0.1');
    const base = await app.getUrl();
    const scope = (tenant = tenantA, factory = factoryA) => `/tenants/${tenant}/factories/${factory}`;
    const root = scope();
    async function request(path, method = 'GET', body) {
      const response = await fetch(base + path, { method,
        headers: { Authorization: 'Bearer synthetic-token', ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      return { status: response.status, body: await response.json() };
    }

    const created = await request(root + '/suppliers', 'POST', { name: '  Pemasok %_ Sintetis  ' });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const supplier = created.body;
    assert.equal(supplier.name, 'Pemasok %_ Sintetis');
    assert.equal(supplier.tenantId, tenantA);
    assert.equal((await request(scope(tenantA, factoryB) + '/suppliers/' + supplier.id)).status, 200);
    assert.equal((await request(scope(tenantB, factoryC) + '/suppliers/' + supplier.id)).status, 404);
    const filtered = await request(root + '/suppliers?q=%25_&isActive=true&limit=1');
    assert.equal(filtered.status, 200, JSON.stringify(filtered.body));
    assert.equal(filtered.body.total, 1);
    assert.equal(filtered.body.items[0].id, supplier.id);
    const beyond = await request(root + '/suppliers?offset=99');
    assert.deepEqual(beyond.body, { items: [], total: 1, limit: 20, offset: 99 });
    assert.equal((await request(root + '/suppliers/' + randomUUID())).status, 404);
    assert.equal((await request(root + '/suppliers/not-a-uuid')).status, 400);
    assert.equal((await request(root + '/suppliers', 'POST', { name: 'X', tenantId: tenantB })).status, 400);

    const caneTypes = root + '/cane-types';
    const sameTenant = scope(tenantA, factoryB) + '/cane-types';
    const otherTenant = scope(tenantB, factoryC) + '/cane-types';
    const registered = await request(caneTypes, 'POST', { code: ' demo-01 ', name: 'Jenis Uji A' });
    assert.equal(registered.status, 201, JSON.stringify(registered.body));
    const type = registered.body;
    assert.equal(type.code, 'DEMO-01');
    assert.equal(type.tenantId, tenantA);
    assert.equal(type.isActive, true);
    assert.deepEqual((await request(sameTenant + '/' + type.id)).body, type);
    assert.equal((await request(otherTenant + '/' + type.id)).status, 404);
    assert.equal((await request(otherTenant + '/' + type.id, 'PATCH', { isActive: false })).status, 404);
    assert.equal((await request(sameTenant, 'POST', { code: 'Demo-01', name: 'Duplikat' })).status, 409);
    assert.equal((await request(otherTenant, 'POST', { code: 'DEMO-01', name: 'Jenis Uji B' })).status, 201);
    assert.equal((await request(caneTypes + '?q=demo&isActive=true&limit=1')).body.items[0].id, type.id);
    const renameType = { name: 'Jenis Uji A Baru', isActive: false };
    const changedType = await request(sameTenant + '/' + type.id, 'PATCH', renameType);
    assert.equal(changedType.status, 200, JSON.stringify(changedType.body));
    assert.equal(changedType.body.name, renameType.name);
    assert.equal(changedType.body.code, type.code);
    assert.equal(changedType.body.isActive, false);
    assert.deepEqual((await request(sameTenant + '/' + type.id, 'PATCH', renameType)).body, changedType.body);
    assert.equal((await request(caneTypes + '?isActive=true')).body.total, 0);
    const inactive = await request(caneTypes + '?q=BARU&isActive=false');
    assert.deepEqual(inactive.body.items, [changedType.body]);
    assert.equal((await request(caneTypes, 'POST', { code: type.code, name: 'Pakai Ulang Kode' })).status, 409);
    assert.equal((await request(caneTypes + '/' + type.id, 'PATCH', { code: 'GANTI' })).status, 400);
    const originHistory = await request(caneTypes + '/' + type.id + '/history');
    assert.equal(originHistory.body.total, 1);
    assert.equal(originHistory.body.items[0].action, 'created');
    const typeHistory = await request(sameTenant + '/' + type.id + '/history');
    assert.equal(typeHistory.body.total, 1);
    assert.equal(typeHistory.body.items[0].actorId, user);
    assert.equal(typeHistory.body.items[0].before.isActive, true);
    assert.equal(typeHistory.body.items[0].after.isActive, false);

    const lotInput = { supplierId: supplier.id, receivedAt: '2026-11-16T08:00:00+07:00', displayCode: 'DEMO-MANUAL' };
    const firstLot = await request(root + '/lots', 'POST', lotInput);
    assert.equal(firstLot.status, 201, JSON.stringify(firstLot.body));
    const lot = firstLot.body;
    assert.equal(lot.receivedAt, '2026-11-16T01:00:00.000Z');
    assert.equal(lot.supplierName, supplier.name);
    const secondLot = await request(root + '/lots', 'POST', lotInput);
    assert.equal(secondLot.status, 201);
    assert.notEqual(secondLot.body.id, lot.id);
    assert.equal((await request(scope(tenantA, factoryB) + '/lots/' + lot.id)).status, 404);
    assert.equal((await request(scope(tenantB, factoryC) + '/lots/' + lot.id)).status, 404);
    const lots = await request(root + '/lots?supplierId=' + supplier.id + '&receivedFrom=2026-11-16T00:00:00Z&receivedBefore=2026-11-17T00:00:00Z&q=MANUAL&limit=1');
    assert.equal(lots.body.total, 2, JSON.stringify(lots.body));
    assert.equal(lots.body.items.length, 1);
    assert.equal(Object.hasOwn(lots.body.items[0], 'status'), false);
    const summary = await request(root + '/lots?includeSummary=true&limit=1');
    assert.equal(summary.status, 200);
    assert.equal(summary.body.total, 2);
    assert.equal(summary.body.items[0].status, 'open');
    assert.equal(summary.body.items[0].netWeightGrams, null);
    assert.equal(summary.body.items[0].juiceProducedLiters, null);
    assert.equal(summary.body.items[0].intake, null);
    const cursorFirst = await request(root + '/lots?pagination=cursor&includeSummary=true&limit=1');
    assert.equal(cursorFirst.status, 200, JSON.stringify(cursorFirst.body));
    assert.equal(Object.hasOwn(cursorFirst.body, 'total'), false);
    assert.equal(Object.hasOwn(cursorFirst.body.items[0], 'cursorReceivedAt'), false);
    assert.ok(cursorFirst.body.nextCursor);
    const nextPath = '/lots?pagination=cursor&includeSummary=true&limit=1&after=' + cursorFirst.body.nextCursor;
    const cursorSecond = await request(root + nextPath);
    assert.equal(cursorSecond.status, 200, JSON.stringify(cursorSecond.body));
    assert.equal(cursorSecond.body.nextCursor, null);
    assert.deepEqual(new Set([...cursorFirst.body.items, ...cursorSecond.body.items].map(item => item.id)),
      new Set([lot.id, secondLot.body.id]));
    assert.equal((await request(scope(tenantA, factoryB) + nextPath)).body.items.length, 0);
    assert.equal((await request(root + '/lots?pagination=cursor&q=missing')).body.items.length, 0);
    await client.query("UPDATE sobatnira.lots SET received_at='2026-11-16T01:00:00.000001Z' WHERE id=$1", [secondLot.body.id]);
    const precise = await request(root + '/lots?pagination=cursor&limit=1');
    assert.equal(precise.body.items[0].id, secondLot.body.id);
    assert.equal(JSON.parse(Buffer.from(precise.body.nextCursor, 'base64url'))[0], '2026-11-16T01:00:00.000001Z');
    const preciseNext = await request(root + '/lots?pagination=cursor&limit=1&after=' + precise.body.nextCursor);
    assert.equal(preciseNext.body.items[0].id, lot.id);
    assert.equal((await request(root + '/lots?pagination=cursor&lotId=' + lot.id)).body.items[0].id, lot.id);
    assert.equal((await request(root + '/lots/counts?lotId=' + lot.id)).body.total, 1);
    assert.equal((await request(root + '/lots/suggestions')).status, 400);
    assert.equal((await request(root + '/lots/suggestions?q=---')).body.items.length, 0);
    await client.query('SAVEPOINT lot_suggestions_fixture');
    for (const code of ['MANUAL', 'MANUAL-TAIL', 'X-MANUAL-X']) {
      await client.query(`INSERT INTO sobatnira.lots(tenant_id,factory_id,supplier_id,display_code,received_at)
        VALUES($1,$2,$3,$4,'2025-01-01T00:00:00Z')`, [tenantA, factoryA, supplier.id, code]);
    }
    const ranked = await request(root + '/lots/suggestions?q=man%20ual');
    assert.equal(ranked.status, 200, JSON.stringify(ranked.body));
    assert.deepEqual(ranked.body.items.map(item => item.rank), [0, 1, 2, 2, 2]);
    assert.equal(ranked.body.items[0].displayCode, 'MANUAL');
    assert.equal((await request(scope(tenantA, factoryB) + '/lots/suggestions?q=MANUAL')).body.items.length, 0);
    assert.equal((await request(root + '/lots/suggestions?q=MANUAL&receivedFrom=2026-01-01T00:00:00Z')).body.items.length, 2);
    await client.query('ROLLBACK TO SAVEPOINT lot_suggestions_fixture');
    // Counts use the full matching dataset, independent of the loaded cursor page.
    await client.query('SAVEPOINT lot_counts_fixture');
    await client.query(`INSERT INTO sobatnira.lot_closures(tenant_id,factory_id,lot_id,is_synthetic,closed_by)
      VALUES($1,$2,$3,false,$4)`, [tenantA, factoryA, lot.id, user]);
    assert.deepEqual((await request(root + '/lots/counts')).body, { total: 2, open: 1, closed: 1 });
    await client.query(`INSERT INTO sobatnira.lot_closures(tenant_id,factory_id,lot_id,is_synthetic,closed_by)
      VALUES($1,$2,$3,true,$4)`, [tenantA, factoryA, secondLot.body.id, user]);
    assert.deepEqual((await request(root + '/lots/counts')).body, { total: 2, open: 1, closed: 1 });
    assert.deepEqual((await request(root + '/lots/counts?synthetic=true')).body, { total: 0, open: 0, closed: 0 });
    assert.deepEqual((await request(root + '/lots/counts?q=missing')).body, { total: 0, open: 0, closed: 0 });
    assert.deepEqual((await request(scope(tenantA, factoryB) + '/lots/counts')).body, { total: 0, open: 0, closed: 0 });
    assert.deepEqual((await request(scope(tenantB, factoryC) + '/lots/counts')).body, { total: 0, open: 0, closed: 0 });
    for (const status of ['open', 'closed']) {
      const result = await request(root + '/lots?pagination=cursor&includeSummary=true&limit=1&status=' + status);
      assert.equal(result.status, 200, JSON.stringify(result.body));
      assert.equal(result.body.items.length, 1);
      assert.equal(result.body.items[0].status, status);
      assert.equal(result.body.nextCursor, null);
      assert.equal((await request(root + '/lots?status=' + status)).body.total, 1);
    }
    const search = '&searchMode=normalized&q=demo%20manual';
    assert.equal((await request(root + '/lots?pagination=cursor' + search)).body.items.length, 2);
    assert.equal((await request(root + '/lots/counts?' + search.slice(1))).body.total, 2);
    const byId = await request(root + '/lots?searchMode=normalized&q=' + lot.id.replaceAll('-', '').toUpperCase());
    assert.equal(byId.body.items[0].id, lot.id);
    assert.equal((await request(root + '/lots?searchMode=normalized&q=---')).body.total, 0);
    assert.equal((await request(root + '/lots/counts?receivedBefore=2026-11-16T00:00:00Z')).body.total, 0);
    assert.equal((await request(root + '/lots/counts?supplierId=' + randomUUID())).body.total, 0);
    assert.equal((await fetch(base + root + '/lots/counts')).status, 401);
    assert.equal((await request(root + '/lots/counts?limit=1')).status, 400);
    assert.equal((await request(root + '/lots?status=done')).status, 400);
    await client.query("UPDATE sobatnira.lot_closures SET reopened_at=clock_timestamp(),reopened_by=$2,reopen_reason='Synthetic correction' WHERE lot_id=$1", [lot.id, user]);
    assert.deepEqual((await request(root + '/lots/counts')).body, { total: 2, open: 2, closed: 0 });
    assert.equal((await request(root + '/lots?status=closed')).body.total, 0);
    await client.query('ROLLBACK TO SAVEPOINT lot_counts_fixture');
    assert.equal((await request(root + '/lots?includeSummary=invalid')).status, 400);
    assert.equal((await request(scope(tenantA, factoryB) + '/lots?includeSummary=true')).body.total, 0);
    const emptyPage = await request(root + '/lots?offset=99');
    assert.deepEqual(emptyPage.body, { items: [], total: 2, limit: 20, offset: 99 });
    assert.equal((await request(root + '/lots?receivedBefore=2026-11-16T00:00:00Z')).body.total, 0);
    assert.equal((await request(scope(tenantA, factoryB) + '/lots')).body.total, 0);
    assert.equal((await request(root + '/lots', 'POST', { ...lotInput, supplierId: randomUUID() })).status, 400);
    assert.equal((await request(root + '/lots', 'POST', { ...lotInput, netWeightKg: 1250 })).status, 400);

    const renamed = await request(root + '/suppliers/' + supplier.id, 'PATCH', { name: 'Pemasok Sintetis Baru', isActive: false });
    assert.equal(renamed.status, 200, JSON.stringify(renamed.body));
    assert.equal(renamed.body.isActive, false);
    assert.equal((await request(root + '/lots', 'POST', lotInput)).status, 400);
    assert.equal((await request(root + '/lots/' + lot.id)).status, 200);
    const changed = await request(root + '/lots/' + lot.id, 'PATCH', { displayCode: null, receivedAt: '2026-11-16T09:00:00+07:00' });
    assert.equal(changed.status, 200, JSON.stringify(changed.body));
    assert.equal(changed.body.displayCode, null);
    assert.equal(changed.body.receivedAt, '2026-11-16T02:00:00.000Z');
    assert.equal((await request(root + '/lots/' + lot.id, 'PATCH', { supplierId: randomUUID() })).status, 404);

    const history = await request(root + '/suppliers/' + supplier.id + '/history');
    assert.equal(history.status, 200, JSON.stringify(history.body));
    assert.equal(history.body.total, 2);
    const update = history.body.items.find((event) => event.action === 'updated');
    assert.equal(update.actorId, user);
    assert.equal(update.before.name, supplier.name);
    assert.equal(update.after.name, 'Pemasok Sintetis Baru');
    assert.equal((await request(scope(tenantA, factoryB) + '/suppliers/' + supplier.id + '/history')).body.total, 0);
    assert.equal((await request(root + '/lots/' + lot.id + '/history')).body.total, 2);
    assert.equal((await request(scope(tenantA, factoryB) + '/lots/' + lot.id + '/history')).status, 404);

    // Failure to persist audit must roll back the entity change in the same statement.
    await client.query('SAVEPOINT audit_failure');
    await client.query(`ALTER TABLE sobatnira.production_audit_events ADD CONSTRAINT synthetic_reject_audit
      CHECK (after_data->>'name' IS DISTINCT FROM 'Synthetic audit failure')`);
    const access = { userId: user, tenantId: tenantA, factoryId: factoryA, role: 'admin' };
    await assert.rejects(app.get(SuppliersRepository).create(access, { name: 'Synthetic audit failure' }), (error) => error.code === '23514');
    await client.query('ROLLBACK TO SAVEPOINT audit_failure');
    assert.equal((await client.query("SELECT count(*)::int AS count FROM sobatnira.suppliers WHERE tenant_id = $1 AND name = 'Synthetic audit failure'", [tenantA])).rows[0].count, 0);

    await client.query('SAVEPOINT cane_audit_failure');
    await client.query(`ALTER TABLE sobatnira.production_audit_events ADD CONSTRAINT synthetic_reject_cane_audit
      CHECK (after_data->>'name' IS DISTINCT FROM 'Synthetic audit failure')`);
    await assert.rejects(app.get(CaneTypesRepository).update(access, type.id, { name: 'Synthetic audit failure' }), { code: '23514' });
    await client.query('ROLLBACK TO SAVEPOINT cane_audit_failure');
    assert.equal((await request(caneTypes + '/' + type.id)).body.name, renameType.name);

    await client.query('SAVEPOINT invalid_relation');
    await assert.rejects(client.query(`INSERT INTO sobatnira.lots(tenant_id, factory_id, supplier_id, received_at)
      VALUES ($1, $2, $3, now())`, [tenantB, factoryC, supplier.id]), (error) => error.code === '23503');
    await client.query('ROLLBACK TO SAVEPOINT invalid_relation');
    const rls = await client.query(`SELECT rowsecurity FROM pg_tables WHERE schemaname = 'sobatnira'
      AND tablename IN ('suppliers', 'lots', 'cane_types', 'production_audit_events')`);
    assert.equal(rls.rows.length, 4);
    assert.ok(rls.rows.every((row) => row.rowsecurity));
    await client.query('SAVEPOINT anonymous_access');
    await client.query('SET LOCAL ROLE authenticated');
    await assert.rejects(client.query('SELECT * FROM sobatnira.lots'), (error) => error.code === '42501');
    await client.query('ROLLBACK TO SAVEPOINT anonymous_access');

    await client.query('SAVEPOINT catalogue_access');
    await client.query('SET LOCAL ROLE authenticated');
    await assert.rejects(client.query('SELECT * FROM sobatnira.cane_types'), { code: '42501' });
    await client.query('ROLLBACK TO SAVEPOINT catalogue_access');

    await client.query('UPDATE sobatnira.factory_memberships SET is_active = false WHERE user_id = $1', [user]);
    assert.equal((await request(root + '/lots/counts')).status, 403);
    assert.equal((await request(root + '/lots?status=open&pagination=cursor')).status, 403);
    assert.equal((await request(root + '/lots/suggestions?q=MANUAL')).status, 403);
    assert.equal((await request(root + '/suppliers', 'POST', { name: 'Denied' })).status, 403);
    assert.equal((await request(caneTypes)).status, 403);
  } finally {
    await app?.close();
    if (authServer) { authServer.closeAllConnections(); await new Promise((done) => authServer.close(done)); }
    await client.query('ROLLBACK').catch(() => {});
    await client.end();
  }
});
