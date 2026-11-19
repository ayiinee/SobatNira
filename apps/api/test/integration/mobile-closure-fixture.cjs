const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { TruckIntake } = require('../../dist/documents/truck-intake');
const { MillingRepository } = require('../../dist/milling/milling.repository');
const { intakeFixture } = require('./intake-fixture.cjs');

async function mobileClosureFixture({ consume = true } = {}) {
  const fixture = await intakeFixture(false, { BATCH_API_BASE_URL: '' });
  try {
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
    if (consume) {
      const root = fixture.root + '/production';
      const id = randomUUID();
      assert.equal((await fixture.request(root + '/batches', 'POST', {
        id, lotId: ids.lot, code: 'CLOSURE-FIXTURE', wokNumber: 1, occurredAt: '2026-11-16T03:00:00Z',
        quantityMl: '250000', physicalWeightKg: '30',
        grades: [{ code: 'A', weightKg: '30', pricePerKgRupiah: '20000' }],
      })).status, 201);
      assert.equal((await fixture.request(root + '/lots/' + ids.lot + '/costs', 'POST', {
        caneCostRupiah: '100000', operationalCostRupiah: '20000', ingredientCostRupiah: '5000', otherCostRupiah: '0',
      })).status, 200);
      const path = fixture.root + '/lots/' + ids.lot + '/juice/reservations';
      assert.equal((await fixture.request(path, 'POST', { requestId: id, batchId: id, quantityMl: '250000' })).status, 201);
      assert.equal((await fixture.request(root + '/batches/' + id + '/approve', 'POST')).status, 200);
      return { ...fixture, closureLotId: ids.lot };
    }
    for (const [id, code] of [[ids.lot, 'TRANSFER-A'], [ids.secondLot, 'TRANSFER-B'], [ids.thirdLot, 'TRANSFER-C']]) {
      await fixture.client.query('UPDATE sobatnira.lots SET display_code=$2 WHERE id=$1', [id, code]);
    }
    return { ...fixture, transferLotId: ids.lot };
  } catch (error) {
    await fixture.close();
    throw error;
  }
}

module.exports = { mobileClosureFixture };
