const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const test = require('node:test');
const { intakeFixture } = require('./intake-fixture.cjs');
const { TruckIntake } = require('../../dist/documents/truck-intake');
const { MillingRepository } = require('../../dist/milling/milling.repository');

async function receive(f, lotId, weight = '1250') {
  const draft = await f.create(lotId);
  assert.equal(draft.status, 201, JSON.stringify(draft.body));
  const path = f.root + '/intake-documents/' + draft.body.id;
  const edited = await f.request(path + '/draft', 'PATCH', { expectedRevision: 1, reason: 'Synthetic intake weight', changes: { netWeightKg: weight } });
  const revision = edited.body.currentRevision;
  assert.equal((await f.request(path + '/confirm-synthetic', 'POST', { expectedRevision: revision })).status, 200);
  const approved = await f.request(path + '/approve', 'POST', { expectedRevision: revision });
  assert.equal(approved.status, 200, JSON.stringify(approved.body));
  return approved.body;
}
async function create(f, lotId = f.ids.lot, requestId = randomUUID()) {
  const draft = await f.request(f.root + '/production-result-documents/synthetic', 'POST', { lotId, requestId });
  assert.equal(draft.status, 201, JSON.stringify(draft.body));
  return { path: f.root + '/production-result-documents/' + draft.body.id, doc: draft.body };
}
async function confirm(f, path, revision = 1) {
  const response = await f.request(path + '/confirm-synthetic', 'POST', { expectedRevision: revision });
  assert.equal(response.status, 200, JSON.stringify(response.body));
}
const approve = (f, path, revision = 1, token) => f.request(path + '/approve', 'POST', { expectedRevision: revision }, token);

test('real milling can debit an OCR receipt and credit nira while preserving revision provenance', async () => {
  const f = await intakeFixture();
  const { app, ids, root, request } = f;
  try {
    const repo = app.get(MillingRepository);
    const access = { userId: ids.admin, tenantId: ids.tenant, factoryId: ids.factory, role: 'admin' };
    const truckDocumentId = randomUUID();
    const truckRevisionId = randomUUID();
    const ocrDocumentId = randomUUID();
    const ocrRevisionId = randomUUID();
    const quantity = '251.000000000000000001';
    await repo.mutate(access, async (tx) => {
      const receipt = await app.get(TruckIntake).post(tx, {
        userId: ids.admin, factoryId: ids.factory, lotId: ids.lot, supplierId: ids.supplier,
        documentId: truckDocumentId, revisionId: truckRevisionId,
        note: { document_type: 'TRUCK_ARRIVAL_NOTE', header: {
          cane_type: { status: 'READ', normalized_value: 'BL' },
          net_weight_kg: { status: 'READ', unit: 'kg', normalized_value: '1250.01' },
        } },
      });
      await repo.lot(tx, access, ids.lot);
      const intake = await repo.intakeAndBalance(tx, access, ids.lot, false);
      assert.equal(intake.id, receipt.id);
      assert.equal(intake.stockMatches, true);
      await repo.postMilling(tx, access, {
        lotId: ids.lot, occurredAt: '2026-11-16T02:00:00Z', juiceProducedLiters: quantity, reportedBatches: [],
      }, intake, { synthetic: false, ocrDocumentId, ocrRevisionId, caneLabel: 'DEMO-A' });
    });
    assert.equal((await request(root + '/stock/sugarcane?lotId=' + ids.lot)).body.quantityKg, '0.00');
    assert.equal((await request(root + '/stock/juice?lotId=' + ids.lot)).body.quantityLiters, quantity);
    assert.equal((await request(root + '/stock/juice?synthetic=true')).body.quantityLiters, '0');
    const { milling } = (await request(root + '/lots/' + ids.lot + '/milling-summary')).body;
    assert.equal(milling.ocrDocumentId, ocrDocumentId);
    assert.equal(milling.ocrRevisionId, ocrRevisionId);
    assert.equal(milling.caneConsumedKg, '1250.01');
    const detail = await request(root + '/lots/' + ids.lot);
    assert.equal(detail.status, 200);
    assert.equal(detail.body.netWeightGrams, '1250010');
    assert.deepEqual(detail.body.intake.document, {
      source: 'ocr', documentId: truckDocumentId, revisionId: truckRevisionId, revisionNumber: null,
    });
    assert.deepEqual(detail.body.milling.document, {
      source: 'ocr', documentId: ocrDocumentId, revisionId: ocrRevisionId, revisionNumber: null,
    });
    assert.equal((await request(root + '/lots/' + ids.lot + '?synthetic=true')).body.netWeightGrams, null);
  } finally { await f.close(); }
});

test('combined result note approves whole-lot milling, nira and reported batches atomically with scoped revisions', async () => {
  const f = await intakeFixture();
  const { root, ids, request } = f;
  try {
    const sourceId = randomUUID();
    const { path, doc } = await create(f, ids.lot, sourceId);
    assert.equal(doc.sourcePayload.noteKind, 'combined_production_result');
    assert.equal(doc.milling, null);
    assert.equal((await create(f, ids.lot, sourceId)).doc.id, doc.id);
    assert.equal((await request(root + '/production-result-documents/synthetic', 'POST', { lotId: ids.secondLot, requestId: sourceId })).status, 409);
    assert.equal((await approve(f, path)).status, 409);
    assert.equal((await request(path, 'GET', undefined, null)).status, 401);
    assert.equal((await request(root + '/production-result-documents/synthetic', 'POST', { lotId: ids.otherLot, requestId: randomUUID() })).status, 404);
    assert.equal((await request(path + '/draft', 'PATCH', { expectedRevision: 1, reason: 'Cannot forge input mass', changes: { caneConsumedKg: '1' } })).status, 400);
    const incomplete = await request(path + '/draft', 'PATCH', { expectedRevision: 1, reason: 'Unknown extraction', changes: { juiceProducedLiters: null } });
    assert.equal(incomplete.body.currentRevision, 2);
    assert.equal((await request(path + '/confirm-synthetic', 'POST', { expectedRevision: 2 })).status, 400);
    const fixed = await request(path + '/draft', 'PATCH', { expectedRevision: 2, reason: 'Synthetic measured output', changes: { juiceProducedLiters: '250.000000000000000001' } });
    assert.equal(fixed.body.currentRevision, 3);
    await confirm(f, path, 3);
    assert.equal((await approve(f, path, 3)).status, 409, 'receipt required');
    assert.equal((await request(root + '/production-result-documents?status=awaiting_validation&lotId=' + ids.lot)).body.total, 1);
    assert.equal((await request(root + '/stock/juice?synthetic=true')).body.quantityLiters, '0');
    const intake = await receive(f, ids.lot, '1250.000000000000000001');
    const reviewed = await request(path + '/draft', 'PATCH', { expectedRevision: 3, reason: 'Add source contribution to mixed batch', changes: {
      reportedBatches: [...fixed.body.fields.reportedBatches, { batchReference: 'MIXED-1', wokNumber: 3, totalJuiceLiters: '100', sourceJuiceLiters: '20' }],
    } });
    assert.equal(reviewed.body.currentRevision, 4);
    assert.equal(reviewed.body.confirmedRevision, 3);
    assert.equal((await approve(f, path, 3)).status, 409);
    const approved = await approve(f, path, 4);
    assert.equal(approved.status, 200, JSON.stringify(approved.body));
    assert.equal(approved.body.status, 'approved');
    assert.equal(approved.body.milling.intakeRecordId, intake.intake.id);
    assert.equal(approved.body.milling.caneConsumedKg, '1250.000000000000000001');
    assert.equal(approved.body.milling.juiceProducedLiters, '250.000000000000000001');
    assert.equal(approved.body.milling.reportedBatchCount, 3);
    assert.equal((await request(root + '/stock/sugarcane?synthetic=true&lotId=' + ids.lot)).body.quantityKg, '0.000000000000000000');
    assert.equal((await request(root + '/stock/juice?synthetic=true&lotId=' + ids.lot)).body.quantityLiters, '250.000000000000000001');
    assert.equal((await request(root + '/stock/juice')).body.quantityLiters, '0');
    const summary = await request(root + '/lots/' + ids.lot + '/milling-summary?synthetic=true');
    assert.equal(summary.body.milling.reportedBatchCount, 3);
    assert.equal(summary.body.milling.documentId, doc.id);
    assert.equal((await request(root + '/lots/' + ids.lot + '/milling-summary')).body.milling, null);
    assert.equal((await request(root + '/lots/' + ids.secondLot + '/milling-summary?synthetic=true')).body.milling, null);
    const retry = await approve(f, path, 4, 'fixture-owner');
    assert.equal(retry.status, 200);
    assert.equal(retry.body.milling.id, approved.body.milling.id);
    assert.equal(retry.body.approvedBy, ids.admin);
    assert.equal((await create(f, ids.lot, sourceId)).doc.currentRevision, 4);
    assert.equal((await request(path + '/revisions')).body.total, 4);
    assert.equal((await request(path + '/history')).body.total, 6);
    assert.equal((await request(root + '/production-result-documents?offset=99')).body.total, 1);
    assert.equal((await request(path + '/draft', 'PATCH', { expectedRevision: 4, reason: 'No rewriting approved note', changes: { juiceProducedLiters: '1' } })).status, 409);
    for (const other of [f.siblingRoot, f.otherRoot]) {
      for (const suffix of ['', '/history', '/revisions']) assert.equal((await request(other + '/production-result-documents/' + doc.id + suffix)).status, 404);
      assert.equal((await request(other + '/production-result-documents')).body.total, 0);
      assert.equal((await request(other + '/lots/' + ids.lot + '/milling-summary?synthetic=true')).status, 404);
      assert.equal((await request(other + '/stock/juice?synthetic=true')).body.quantityLiters, '0');
      assert.equal((await request(other + '/production-result-documents/' + doc.id + '/approve', 'POST', { expectedRevision: 4 })).status, 404);
    }
    const duplicate = await create(f);
    await confirm(f, duplicate.path);
    assert.equal((await approve(f, duplicate.path)).status, 409);

    await receive(f, ids.secondLot);
    const rollback = await create(f, ids.secondLot);
    await request(rollback.path + '/draft', 'PATCH', { expectedRevision: 1, reason: 'Invalid chronological report', changes: { occurredAt: '2026-11-15T01:00:00Z' } });
    await confirm(f, rollback.path, 2);
    assert.equal((await approve(f, rollback.path, 2)).status, 409);
    await request(rollback.path + '/draft', 'PATCH', { expectedRevision: 2, reason: 'Correct time', changes: { occurredAt: '2026-11-16T02:00:00Z' } });
    await f.client.query('SAVEPOINT fail_milling_audit');
    await f.client.query("ALTER TABLE sobatnira.milling_document_events ADD CONSTRAINT synthetic_milling_reject CHECK (action <> 'approved') NOT VALID");
    assert.ok((await approve(f, rollback.path, 3)).status >= 500);
    assert.equal((await request(rollback.path)).body.status, 'awaiting_validation');
    assert.equal((await request(root + '/stock/sugarcane?synthetic=true&lotId=' + ids.secondLot)).body.quantityKg, '1250');
    assert.equal((await request(root + '/stock/juice?synthetic=true&lotId=' + ids.secondLot)).body.quantityLiters, '0');
    assert.equal((await f.client.query('SELECT count(*)::int AS count FROM sobatnira.milling_records WHERE lot_id = $1', [ids.secondLot])).rows[0].count, 0);
    await f.client.query('ROLLBACK TO SAVEPOINT fail_milling_audit');
    assert.equal((await approve(f, rollback.path, 3)).status, 200);
  } finally { await f.close(); }
});

test('concurrent combined-note retries and competing approvals book each whole lot only once', async () => {
  const f = await intakeFixture(true);
  const { ids, root, request, client } = f;
  try {
    await receive(f, ids.lot);
    const requestId = randomUUID();
    const created = await Promise.all(Array.from({ length: 3 }, () => create(f, ids.lot, requestId)));
    assert.equal(new Set(created.map((item) => item.doc.id)).size, 1);
    const path = created[0].path;
    const edits = await Promise.all(['251.1', '251.2'].map((value) => request(path + '/draft', 'PATCH', {
      expectedRevision: 1, reason: 'Concurrent output correction', changes: { juiceProducedLiters: value },
    })));
    assert.deepEqual(edits.map((item) => item.status).sort(), [200, 409]);
    const winner = edits.find((item) => item.status === 200).body;
    await confirm(f, path, 2);
    const results = await Promise.all([approve(f, path, 2), approve(f, path, 2)]);
    for (const result of results) assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.equal(results[0].body.milling.id, results[1].body.milling.id);
    assert.equal((await request(root + '/stock/sugarcane?synthetic=true')).body.quantityKg, '0');
    assert.equal((await request(root + '/stock/juice?synthetic=true')).body.quantityLiters, winner.fields.juiceProducedLiters);

    await receive(f, ids.secondLot);
    const competing = await Promise.all([create(f, ids.secondLot), create(f, ids.secondLot)]);
    for (const item of competing) await confirm(f, item.path);
    const approvals = await Promise.all(competing.map((item) => approve(f, item.path)));
    assert.deepEqual(approvals.map((item) => item.status).sort(), [200, 409]);
    const counts = (await client.query(`SELECT
      (SELECT count(*)::int FROM sobatnira.milling_records WHERE tenant_id = $1) AS records,
      (SELECT count(*)::int FROM sobatnira.sugarcane_stock_movements WHERE tenant_id = $1 AND movement_type = 'milling') AS cane,
      (SELECT count(*)::int FROM sobatnira.juice_stock_movements WHERE tenant_id = $1) AS juice`, [ids.tenant])).rows[0];
    assert.deepEqual(counts, { records: 2, cane: 2, juice: 2 });
    assert.equal((await request(root + '/stock/sugarcane?synthetic=true')).body.quantityKg, '0');

    // A valid inbound movement can only be removed for this deliberately corrupt fixture;
    // the next approval must stop instead of driving its stock below zero.
    await receive(f, ids.thirdLot);
    const inconsistent = await create(f, ids.thirdLot);
    await confirm(f, inconsistent.path);
    await client.query('DELETE FROM sobatnira.sugarcane_stock_movements WHERE tenant_id = $1 AND lot_id = $2', [ids.tenant, ids.thirdLot]);
    assert.equal((await approve(f, inconsistent.path)).status, 409);
    assert.equal((await request(inconsistent.path)).body.status, 'awaiting_validation');

    await client.query('BEGIN');
    for (const sql of [
      'UPDATE sobatnira.sugarcane_stock_movements SET quantity_delta_kg = -1 WHERE tenant_id = $1 AND movement_type = \'milling\'',
      'UPDATE sobatnira.juice_stock_movements SET quantity_delta_liters = 1 WHERE tenant_id = $1',
      'UPDATE sobatnira.milling_records SET cane_consumed_kg = 1 WHERE tenant_id = $1',
    ]) {
      await client.query('SAVEPOINT ledger_integrity');
      await assert.rejects(client.query(sql, [ids.tenant]), (error) => error.code === '23503');
      await client.query('ROLLBACK TO SAVEPOINT ledger_integrity');
    }
    const rls = await client.query(`SELECT rowsecurity FROM pg_tables WHERE schemaname = 'sobatnira'
      AND tablename IN ('milling_documents','milling_document_revisions','milling_document_events','milling_records','juice_stock_movements')`);
    assert.equal(rls.rows.length, 5);
    assert.ok(rls.rows.every((row) => row.rowsecurity));
    await client.query('SAVEPOINT browser_denied');
    await client.query('SET LOCAL ROLE authenticated');
    await assert.rejects(client.query('SELECT * FROM sobatnira.milling_records'), (error) => error.code === '42501');
    await client.query('ROLLBACK');
  } finally { await f.close(); }
});
