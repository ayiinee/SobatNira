const { intakeFixture } = require('../test/integration/intake-fixture.cjs');
const { mobileClosureFixture } = require('../test/integration/mobile-closure-fixture.cjs');

// This server keeps all synthetic changes inside one rollback-only transaction.
async function main() {
  const url = new URL(process.env.TEST_DATABASE_URL ?? '');
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)) {
    throw new Error('TEST_DATABASE_URL harus menunjuk PostgreSQL pengujian lokal.');
  }
  process.env.DATABASE_URL = url.href;
  process.env.DATABASE_SSL_CA_FILE = '';
  process.env.NODE_ENV = 'test';
  process.env.SOBATNIRA_MODE = 'legacy';
  const fixture = process.argv.includes('--transfer') ? await mobileClosureFixture({ consume: false })
    : process.argv.includes('--closure') ? await mobileClosureFixture() : await intakeFixture(false);
  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    await fixture.close();
  };
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.once(signal, () => {
      void stop().then(() => process.exit(0)).catch(() => process.exit(1));
    });
  }
  console.log(JSON.stringify({
    PRODUCTION_TEST_API: fixture.base,
    PRODUCTION_TEST_TENANT: fixture.ids.tenant,
    PRODUCTION_TEST_FACTORY: fixture.ids.factory,
    ...(fixture.closureLotId ? { PRODUCTION_TEST_CLOSURE_LOT: fixture.closureLotId } : {}),
    ...(fixture.transferLotId ? {
      PRODUCTION_TEST_TRANSFER_LOT: fixture.transferLotId,
      PRODUCTION_TEST_TRANSFER_TO: fixture.ids.secondLot,
      PRODUCTION_TEST_TRANSFER_THIRD: fixture.ids.thirdLot,
    } : {}),
  }));
}

main().catch(() => {
  console.error('Fixture mobile gagal. Periksa TEST_DATABASE_URL, migrasi bisnis, dan schema auth pada PostgreSQL pengujian lokal.');
  process.exitCode = 1;
});
