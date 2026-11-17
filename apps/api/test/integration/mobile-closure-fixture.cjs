const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');
const { createServer } = require('node:http');
const { TruckIntake } = require('../../dist/documents/truck-intake');
const { MillingRepository } = require('../../dist/milling/milling.repository');
const { intakeFixture } = require('./intake-fixture.cjs');

async function mobileClosureFixture() {
  const batches = createServer((request, response) => {
    response.setHeader('Content-Type', 'application/json');
    const url = new URL(request.url, 'http://127.0.0.1');
    if (request.method !== 'GET' || !url.pathname.startsWith('/batches/closure-check/')
      || request.headers.authorization !== 'Bearer fixture-admin') {
      response.writeHead(403).end('{}');
      return;
    }
    response.end(JSON.stringify({ canClose: true }));
  });
  batches.listen(0, '127.0.0.1');
  await once(batches, 'listening');
  let fixture;
  const close = async () => {
    try { await fixture?.close(); }
    finally {
      batches.closeAllConnections();
      await new Promise((resolve) => batches.close(resolve));
    }
  };
  try {
    fixture = await intakeFixture(false, { BATCH_API_BASE_URL: 'http://127.0.0.1:' + batches.address().port });
    const { ids, app } = fixture;
    const access = { userId: ids.admin, tenantId: ids.tenant, factoryId: ids.factory, role: 'admin' };
    const milling = app.get(MillingRepository);
    // Synthetic identities in the rollback fixture exercise the normal OCR source category.
    await milling.mutate(access, async (transaction) => {
      await app.get(TruckIntake).post(transaction, {
        userId: ids.admin, factoryId: ids.factory, lotId: ids.lot, supplierId: ids.supplier,
        documentId: randomUUID(), revisionId: randomUUID(), note: {
          document_type: 'TRUCK_ARRIVAL_NOTE', header: {
            cane_type: { status: 'READ', normalized_value: 'DEMO' },
            net_weight_kg: { status: 'READ', unit: 'kg', normalized_value: '1250' },
          },
        },
      });
      await milling.lot(transaction, access, ids.lot);
      const intake = await milling.intakeAndBalance(transaction, access, ids.lot, false);
      await milling.postMilling(transaction, access, {
        lotId: ids.lot, occurredAt: '2026-11-16T02:00:00Z', juiceProducedLiters: '250', reportedBatches: [],
      }, intake, { synthetic: false, ocrDocumentId: randomUUID(), ocrRevisionId: randomUUID(), caneLabel: 'DEMO' });
    });
    const path = fixture.root + '/lots/' + ids.lot + '/juice/reservations';
    const requestId = randomUUID();
    assert.equal((await fixture.request(path, 'POST', { requestId, batchId: randomUUID(), quantityMl: '250000' })).status, 201);
    assert.equal((await fixture.request(path + '/' + requestId + '/consume', 'POST')).status, 200);
    return { ...fixture, close, closureLotId: ids.lot };
  } catch (error) {
    await close();
    throw error;
  }
}

module.exports = { mobileClosureFixture };
