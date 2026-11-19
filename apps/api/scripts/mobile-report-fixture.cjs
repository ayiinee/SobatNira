const { randomUUID } = require('node:crypto');
const { createInterface } = require('node:readline');
const { mobileClosureFixture } = require('../test/integration/mobile-closure-fixture.cjs');

// All identities and business writes stay in the fixture's rollback transaction.
// No migrations, Auth requests to Supabase, or persistent seed writes are made.
async function main() {
  const fixture = await mobileClosureFixture({ consume: false });
  try {
    const root = fixture.root + '/production';
    const batch = randomUUID();
    const checked = async (path, method, body) => {
      const result = await fixture.request(path, method, body);
      if (result.status < 200 || result.status >= 300) throw new Error('Synthetic fixture operation failed.');
      return result.body;
    };
    await checked(root + '/batches', 'POST', { id: batch, lotId: fixture.ids.lot, code: 'BATCH-FLUTTER-REPORT', wokNumber: 1,
      occurredAt: '2026-11-16T03:00:00Z', quantityMl: '100000', physicalWeightKg: '32',
      grades: [{ code: 'A', weightKg: '30', pricePerKgRupiah: '20000' }] });
    await checked(root + '/lots/' + fixture.ids.lot + '/costs', 'POST', {
      caneCostRupiah: '100000', operationalCostRupiah: '20000', ingredientCostRupiah: '5000', otherCostRupiah: '0' });
    await checked(fixture.root + '/lots/' + fixture.ids.lot + '/juice/reservations', 'POST', {
      requestId: randomUUID(), batchId: batch, quantityMl: '100000' });
    await checked(root + '/batches/' + batch + '/approve', 'POST');
    console.log(JSON.stringify({ REPORT_TEST_API: fixture.base, REPORT_TEST_TENANT: fixture.ids.tenant,
      REPORT_TEST_FACTORY: fixture.ids.factory }));
    // Close explicitly so the caller can verify that PostgreSQL was rolled back.
    const input = createInterface({ input: process.stdin });
    await new Promise(resolve => { input.on('line', line => { if (line.trim() === 'stop') resolve(); }); input.on('close', resolve); });
    input.close();
  } finally { await fixture.close(); }
}
main().catch(() => { console.error('Fixture laporan gagal; periksa database development, migrasi dan CA.'); process.exitCode = 1; });
