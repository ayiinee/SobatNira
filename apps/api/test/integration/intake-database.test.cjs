const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const test = require('node:test');
const { intakeFixture } = require('./intake-fixture.cjs');

test('synthetic intake flows through revisions, confirmation and atomic admin approval without duplicate stock', async () => {
  const f = await intakeFixture();
  const { ids, client, root, request } = f;
  try {
    const sourceId = randomUUID();
    const created = await f.create(ids.lot, sourceId);
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const id = created.body.id;
    const path = root + '/intake-documents/' + id;
    assert.equal(created.body.status, 'draft');
    assert.equal(created.body.fields.netWeightKg, '1250');
    assert.equal(created.body.synthetic, true);
    assert.equal(created.body.intake, null);
    assert.equal((await request(root + '/stock/sugarcane?synthetic=true')).body.quantityKg, '0');
    assert.equal((await f.create(ids.lot, sourceId)).body.id, id);
    assert.equal((await f.create(ids.secondLot, sourceId)).status, 409);
    assert.equal((await request(path + '/approve', 'POST', { expectedRevision: 1 })).status, 409);
    assert.equal((await request(path, 'GET', undefined, null)).status, 401);
    assert.equal((await request(path + '/draft', 'PATCH', { expectedRevision: 1, reason: 'Missing weight', changes: { netWeightKg: null } })).status, 200);
    assert.equal((await request(path + '/confirm-synthetic', 'POST', { expectedRevision: 2 })).status, 400);
    const corrected = await request(path + '/draft', 'PATCH', { expectedRevision: 2, reason: 'Synthetic correction', changes: {
      netWeightKg: '1250.000000000000000001', brix: null, occurredAt: '2026-11-16T09:00:00+07:00',
    } });
    assert.equal(corrected.status, 200, JSON.stringify(corrected.body));
    assert.equal(corrected.body.currentRevision, 3);
    assert.equal((await request(path + '/draft', 'PATCH', { expectedRevision: 1, reason: 'Stale edit', changes: { brix: '18' } })).status, 409);
    const confirmed = await request(path + '/confirm-synthetic', 'POST', { expectedRevision: 3 });
    assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
    assert.equal(confirmed.body.status, 'awaiting_validation');
    assert.equal(confirmed.body.confirmationSource, 'synthetic_admin');
    assert.equal(confirmed.body.confirmedBy, ids.admin);
    assert.equal((await request(root + '/intake-documents?status=awaiting_validation')).body.total, 1);
    const reviewed = await request(path + '/draft', 'PATCH', { expectedRevision: 3, reason: 'Admin review', changes: { netWeightKg: '1300.000000000000000001' } });
    assert.equal(reviewed.body.currentRevision, 4);
    assert.equal(reviewed.body.confirmedRevision, 3);
    assert.equal((await request(path + '/confirm-synthetic', 'POST', { expectedRevision: 3 })).status, 200);
    assert.equal((await request(path + '/approve', 'POST', { expectedRevision: 3 })).status, 409);
    const approved = await request(path + '/approve', 'POST', { expectedRevision: 4 });
    assert.equal(approved.status, 200, JSON.stringify(approved.body));
    assert.equal(approved.body.status, 'approved');
    assert.equal(approved.body.approvedRevision, 4);
    assert.equal(approved.body.intake.netWeightKg, '1300.000000000000000001');
    const retry = await request(path + '/approve', 'POST', { expectedRevision: 4 }, 'fixture-owner');
    assert.equal(retry.status, 200);
    assert.equal(retry.body.intake.id, approved.body.intake.id);
    assert.equal(retry.body.approvedBy, ids.admin);
    const sourceRetry = await f.create(ids.lot, sourceId);
    assert.equal(sourceRetry.body.currentRevision, 4);
    assert.equal(sourceRetry.body.sourcePayload.fields.netWeightKg, '1250');
    assert.equal((await request(path + '/draft', 'PATCH', { expectedRevision: 4, reason: 'Forbidden correction', changes: { netWeightKg: '1' } })).status, 409);
    assert.equal((await request(path + '/revisions')).body.total, 4);
    assert.equal((await request(path + '/history')).body.total, 6);
    assert.equal((await request(root + '/stock/sugarcane?synthetic=true')).body.quantityKg, '1300.000000000000000001');
    assert.equal((await request(root + '/stock/sugarcane')).body.quantityKg, '0');
    assert.equal((await request(f.siblingRoot + '/stock/sugarcane?synthetic=true')).body.quantityKg, '0');
    assert.equal((await request(root + '/intake-documents?status=awaiting_validation')).body.total, 0);
    assert.equal((await request(root + '/intake-documents?offset=99')).body.total, 1);
    const lot = await request(root + '/lots/' + ids.lot);
    assert.equal(lot.body.receivedAt, '2026-11-16T02:00:00.000Z');
    assert.equal(lot.body.netWeightGrams, null);
    assert.equal(lot.body.intake, null);
    assert.equal(lot.body.milling, null);
    assert.equal(lot.body.status, 'open');
    const syntheticLot = await request(root + '/lots/' + ids.lot + '?synthetic=true');
    assert.equal(syntheticLot.body.netWeightGrams, '1300000.000000000000001');
    assert.deepEqual(syntheticLot.body.intake.document, {
      source: 'synthetic', documentId: id, revisionId: null, revisionNumber: 4,
    });
    assert.equal((await request(root + '/lots/' + ids.lot + '?synthetic=yes')).status, 400);
    assert.equal((await request(root + '/lots/' + ids.lot, 'PATCH', { receivedAt: '2026-11-17T00:00:00Z' })).status, 409);
    assert.equal((await request(root + '/lots/' + ids.lot, 'PATCH', { supplierId: ids.replacementSupplier })).status, 409);
    assert.equal((await request(root + '/lots/' + ids.lot, 'PATCH', { displayCode: 'DEMO-CORRECTED' })).status, 200);

    for (const other of [f.siblingRoot, f.otherRoot]) {
      for (const suffix of ['', '/history', '/revisions']) assert.equal((await request(other + '/intake-documents/' + id + suffix)).status, 404);
      assert.equal((await request(other + '/intake-documents')).body.total, 0);
      assert.equal((await request(other + '/intake-documents/' + id + '/approve', 'POST', { expectedRevision: 4 })).status, 404);
    }
    assert.equal((await f.create(ids.siblingLot)).status, 404);
    assert.equal((await f.create(ids.otherLot)).status, 404);
    const duplicate = await f.create();
    const duplicatePath = root + '/intake-documents/' + duplicate.body.id;
    assert.equal((await request(duplicatePath + '/confirm-synthetic', 'POST', { expectedRevision: 1 })).status, 200);
    assert.equal((await request(duplicatePath + '/approve', 'POST', { expectedRevision: 1 })).status, 409);

    // A failed final audit must undo receipt, movement, status and lot time together.
    const rollbackDraft = await f.create(ids.secondLot);
    const rollbackPath = root + '/intake-documents/' + rollbackDraft.body.id;
    await request(rollbackPath + '/draft', 'PATCH', { expectedRevision: 1, reason: 'Synthetic event time', changes: { occurredAt: '2026-11-16T03:00:00Z' } });
    await request(rollbackPath + '/confirm-synthetic', 'POST', { expectedRevision: 2 });
    await client.query('SAVEPOINT fail_final_audit');
    await client.query("ALTER TABLE sobatnira.intake_document_events ADD CONSTRAINT synthetic_reject_approval CHECK (action <> 'approved') NOT VALID");
    assert.ok((await request(rollbackPath + '/approve', 'POST', { expectedRevision: 2 })).status >= 500);
    assert.equal((await request(rollbackPath)).body.status, 'awaiting_validation');
    assert.equal((await request(root + '/lots/' + ids.secondLot)).body.receivedAt, '2026-11-16T01:00:00.000Z');
    assert.equal((await client.query('SELECT count(*)::int AS count FROM sobatnira.intake_records WHERE lot_id = $1', [ids.secondLot])).rows[0].count, 0);
    assert.equal((await client.query('SELECT count(*)::int AS count FROM sobatnira.sugarcane_stock_movements WHERE lot_id = $1', [ids.secondLot])).rows[0].count, 0);
    await client.query('ROLLBACK TO SAVEPOINT fail_final_audit');
    assert.equal((await request(rollbackPath + '/approve', 'POST', { expectedRevision: 2 }, 'fixture-owner')).status, 200);
    assert.equal((await request(root + '/stock/sugarcane?synthetic=true')).body.quantityKg, '2550.000000000000000001');

    // The ledger cannot be reassigned to another lot or given a different amount.
    await client.query('SAVEPOINT stock_integrity');
    await client.query('SET CONSTRAINTS ALL IMMEDIATE');
    await assert.rejects(client.query(`UPDATE sobatnira.sugarcane_stock_movements SET lot_id = $1
      WHERE tenant_id = $2 AND lot_id = $3`, [ids.thirdLot, ids.tenant, ids.lot]), (error) => error.code === '23503');
    await client.query('ROLLBACK TO SAVEPOINT stock_integrity');
    await client.query('SET CONSTRAINTS ALL IMMEDIATE');
    await assert.rejects(client.query(`UPDATE sobatnira.sugarcane_stock_movements SET quantity_delta_kg = 1
      WHERE tenant_id = $1 AND lot_id = $2`, [ids.tenant, ids.lot]), (error) => error.code === '23503');
    await client.query('ROLLBACK TO SAVEPOINT stock_integrity');

    const rls = await client.query(`SELECT rowsecurity FROM pg_tables WHERE schemaname = 'sobatnira'
      AND tablename IN ('intake_documents','intake_document_revisions','intake_records','sugarcane_stock_movements','intake_document_events')`);
    assert.equal(rls.rows.length, 5);
    assert.ok(rls.rows.every((row) => row.rowsecurity));
    await client.query('SAVEPOINT browser_read');
    await client.query('SET LOCAL ROLE authenticated');
    await assert.rejects(client.query('SELECT * FROM sobatnira.intake_documents'), (error) => error.code === '42501');
    await client.query('ROLLBACK TO SAVEPOINT browser_read');
  } finally { await f.close(); }
});

test('concurrent source retries, draft edits and approvals retain one receipt and one stock movement', async () => {
  const f = await intakeFixture(true);
  const { root, request, ids, client } = f;
  try {
    const source = randomUUID();
    const created = await Promise.all(Array.from({ length: 3 }, () => f.create(ids.lot, source)));
    for (const result of created) assert.equal(result.status, 201, JSON.stringify(result.body));
    assert.equal(new Set(created.map((result) => result.body.id)).size, 1);
    const path = root + '/intake-documents/' + created[0].body.id;
    assert.equal((await request(path + '/history')).body.total, 1);
    const edits = await Promise.all(['1000.1', '1000.2'].map((weight) => request(path + '/draft', 'PATCH', {
      expectedRevision: 1, reason: 'Concurrent synthetic correction', changes: { netWeightKg: weight },
    })));
    assert.deepEqual(edits.map((result) => result.status).sort(), [200, 409]);
    const winner = edits.find((result) => result.status === 200).body;
    assert.equal((await request(path + '/confirm-synthetic', 'POST', { expectedRevision: 2 })).status, 200);
    const approvals = await Promise.all(Array.from({ length: 2 }, () => request(path + '/approve', 'POST', { expectedRevision: 2 })));
    for (const result of approvals) assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.equal(approvals[0].body.intake.id, approvals[1].body.intake.id);
    assert.equal((await request(root + '/stock/sugarcane?synthetic=true')).body.quantityKg, winner.fields.netWeightKg);

    const competing = await Promise.all([f.create(ids.secondLot), f.create(ids.secondLot)]);
    for (const item of competing) assert.equal(item.status, 201);
    for (const item of competing) await request(root + '/intake-documents/' + item.body.id + '/confirm-synthetic', 'POST', { expectedRevision: 1 });
    const results = await Promise.all(competing.map((item) => request(root + '/intake-documents/' + item.body.id + '/approve', 'POST', { expectedRevision: 1 })));
    assert.deepEqual(results.map((result) => result.status).sort(), [200, 409]);
    const counts = await client.query(`SELECT
      (SELECT count(*)::int FROM sobatnira.intake_records WHERE tenant_id = $1) AS receipts,
      (SELECT count(*)::int FROM sobatnira.sugarcane_stock_movements WHERE tenant_id = $1) AS movements`, [ids.tenant]);
    assert.deepEqual(counts.rows[0], { receipts: 2, movements: 2 });

    const third = await f.create(ids.thirdLot);
    const thirdPath = root + '/intake-documents/' + third.body.id;
    await request(thirdPath + '/confirm-synthetic', 'POST', { expectedRevision: 1 });
    const [approval, metadata] = await Promise.all([
      request(thirdPath + '/approve', 'POST', { expectedRevision: 1 }),
      request(root + '/lots/' + ids.thirdLot, 'PATCH', { receivedAt: '2026-11-17T00:00:00Z' }),
    ]);
    assert.equal(approval.status, 200, JSON.stringify(approval.body));
    assert.ok([200, 409].includes(metadata.status), JSON.stringify(metadata.body));
    assert.equal((await request(root + '/lots/' + ids.thirdLot)).body.receivedAt, third.body.fields.occurredAt);
  } finally { await f.close(); }
});
