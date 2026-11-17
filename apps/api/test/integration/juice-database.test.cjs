const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');
const { createServer } = require('node:http');
const test = require('node:test');
const { intakeFixture } = require('./intake-fixture.cjs');

async function mill(f, lotId) {
  const intake = await f.create(lotId);
  assert.equal(intake.status, 201);
  const note = await f.request(f.root + '/production-result-documents/synthetic', 'POST', { lotId, requestId: randomUUID() });
  assert.equal(note.status, 201);
  for (const path of [f.root + '/intake-documents/' + intake.body.id, f.root + '/production-result-documents/' + note.body.id]) {
    for (const action of ['confirm-synthetic', 'approve']) {
      const response = await f.request(path + '/' + action, 'POST', { expectedRevision: 1 });
      assert.equal(response.status, 200, JSON.stringify(response.body));
    }
  }
}

const root = (f, lotId = f.ids.lot) => f.root + '/lots/' + lotId + '/juice';
const reserve = (f, input, lotId) => f.request(root(f, lotId) + '/reservations', 'POST', input);
const requestFor = (quantityMl) => ({ requestId: randomUUID(), batchId: randomUUID(), quantityMl, synthetic: true });

test('reservations compete for available ml, retain idempotency and finalize exactly once', async () => {
  const f = await intakeFixture(true);
  try {
    await mill(f, f.ids.lot);
    const path = root(f);
    assert.equal((await f.request(path + '/availability')).body.availableMl, '0');
    const requests = [requestFor('200000.25'), requestFor('200000.25')];
    const results = await Promise.all(requests.map((input) => reserve(f, input)));
    assert.deepEqual(results.map((result) => result.status).sort(), [201, 409]);
    const winner = requests[results.findIndex((result) => result.status === 201)];
    assert.equal((await reserve(f, winner)).body.state, 'reserved');
    assert.equal((await reserve(f, { ...winner, batchId: randomUUID() })).status, 409);
    assert.equal((await reserve(f, winner, f.ids.secondLot)).status, 409);
    const availability = () => f.request(path + '/availability?synthetic=true');
    assert.equal((await availability()).body.availableMl, '49999.75');
    assert.equal((await availability()).body.reservedMl, '200000.25');
    const finish = path + '/reservations/' + winner.requestId;
    const outcomes = await Promise.all([f.request(finish + '/consume', 'POST'), f.request(finish + '/release', 'POST')]);
    assert.deepEqual(outcomes.map((result) => result.status).sort(), [200, 409]);
    const final = outcomes.find((result) => result.status === 200).body.state;
    const action = final === 'consumed' ? 'consume' : 'release';
    assert.equal((await f.request(finish + '/' + action, 'POST')).body.state, final);
    assert.equal((await reserve(f, winner)).body.state, final);
    assert.equal((await availability()).body.onHandMl, final === 'consumed' ? '49999.75' : '250000');
    assert.equal((await availability()).body.reservedMl, '0');
    assert.equal((await f.request(path + '/availability', 'GET', undefined, null)).status, 401);
    assert.equal((await f.request(f.siblingRoot + '/lots/' + f.ids.lot + '/juice/availability')).status, 404);
  } finally { await f.close(); }
});

test('transfer and reservation serialize, conserve ml and preserve origin through onward transfer', async () => {
  const f = await intakeFixture(true);
  try {
    await mill(f, f.ids.lot);
    const transfer = (lotId, input) => f.request(root(f, lotId) + '/transfers', 'POST', input);
    const held = requestFor('230000');
    assert.equal((await reserve(f, held)).status, 201);
    const move = { requestId: randomUUID(), toLotId: f.ids.secondLot, quantityMl: '20000', synthetic: true };
    const competitor = await Promise.all([transfer(f.ids.lot, move), reserve(f, requestFor('20000'))]);
    assert.deepEqual(competitor.map((result) => result.status).sort((a, b) => a - b), [201, 409]);
    if (competitor[1].status === 201) {
      await f.request(root(f) + '/reservations/' + competitor[1].body.requestId + '/release', 'POST');
    }
    const moved = await transfer(f.ids.lot, move);
    assert.equal(moved.status, 201, JSON.stringify(moved.body));
    assert.equal(moved.body.originLotId, f.ids.lot);
    assert.deepEqual((await transfer(f.ids.lot, move)).body, moved.body);
    assert.equal((await transfer(f.ids.lot, { ...move, quantityMl: '1' })).status, 409);
    assert.equal((await transfer(f.ids.lot, { ...move, requestId: randomUUID(), toLotId: f.ids.siblingLot })).status, 404);
    assert.equal((await transfer(f.ids.lot, { ...move, requestId: randomUUID(), toLotId: f.ids.otherLot })).status, 404);
    assert.equal((await transfer(f.ids.lot, { ...move, requestId: randomUUID(), toLotId: f.ids.lot })).status, 400);
    assert.equal((await reserve(f, requestFor('1'), f.ids.secondLot)).status, 409);
    const onward = await transfer(f.ids.secondLot, {
      ...move, requestId: randomUUID(), toLotId: f.ids.thirdLot, originLotId: f.ids.lot, quantityMl: '5000',
    });
    assert.equal(onward.status, 201, JSON.stringify(onward.body));
    const availability = (lotId) => f.request(root(f, lotId) + '/availability?synthetic=true');
    assert.equal((await availability(f.ids.lot)).body.onHandMl, '230000');
    assert.deepEqual((await availability(f.ids.secondLot)).body.origins, [{
      originLotId: f.ids.lot, onHandMl: '15000', reservedMl: '0', availableMl: '15000',
    }]);
    const use = await reserve(f, { ...requestFor('5000'), originLotId: f.ids.lot }, f.ids.thirdLot);
    assert.equal(use.status, 201, JSON.stringify(use.body));
    assert.equal(use.body.originLotId, f.ids.lot);
    assert.equal((await availability(f.ids.thirdLot)).body.availableMl, '0');
  } finally { await f.close(); }
});

test('lot closure checks drained stock and Backend B, then blocks new stock operations', async () => {
  const calls = [];
  let reply = { canClose: false };
  const batches = createServer((req, res) => {
    calls.push({ url: req.url, auth: req.headers.authorization });
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(reply));
  });
  batches.listen(0, '127.0.0.1');
  await once(batches, 'listening');
  let f;
  try {
    f = await intakeFixture(true, { BATCH_API_BASE_URL: 'http://127.0.0.1:' + batches.address().port });
    const { lot, secondLot, tenant, factory, admin } = f.ids;
    const closure = f.root + '/lots/' + lot + '/closure';
    const status = () => f.request(closure + '?synthetic=true');
    const close = () => f.request(closure, 'POST', { synthetic: true });
    assert.equal((await status()).body.status, 'open');
    assert.equal((await close()).status, 409);
    await mill(f, lot);
    assert.equal((await close()).status, 409);
    const held = requestFor('230000');
    assert.equal((await reserve(f, held)).status, 201);
    assert.equal((await f.request(root(f) + '/transfers', 'POST',
      { requestId: randomUUID(), toLotId: secondLot, quantityMl: '20000', synthetic: true })).status, 201);
    assert.equal((await close()).status, 409);
    assert.equal(calls.length, 0);
    const consume = root(f) + '/reservations/' + held.requestId + '/consume';
    assert.equal((await f.request(consume, 'POST')).status, 200);
    assert.equal((await close()).status, 409);
    assert.deepEqual(calls[0], {
      url: '/batches/closure-check/' + lot + '?tenantId=' + tenant + '&factoryId=' + factory + '&synthetic=true',
      auth: 'Bearer fixture-admin',
    });
    reply = { canClose: 'yes' };
    assert.equal((await close()).status, 503);
    assert.equal((await status()).body.status, 'open');
    reply = { canClose: true };
    const closed = await close();
    assert.equal(closed.status, 200, JSON.stringify(closed.body));
    assert.equal(closed.body.status, 'closed');
    assert.equal(closed.body.closedBy, admin);
    const lotDetail = await f.request(f.root + '/lots/' + lot + '?synthetic=true');
    assert.equal(lotDetail.status, 200);
    assert.equal(lotDetail.body.status, 'closed');
    assert.equal(lotDetail.body.closedAt, closed.body.closedAt);
    assert.equal(lotDetail.body.closedBy, admin);
    assert.equal((await f.request(f.root + '/lots/' + lot)).body.status, 'open');
    assert.deepEqual((await close()).body, closed.body);
    assert.equal(calls.length, 3);
    assert.equal((await f.request(closure)).body.status, 'open');
    assert.equal((await reserve(f, requestFor('1'))).status, 409);
    assert.equal((await f.request(root(f, secondLot) + '/transfers', 'POST', {
      requestId: randomUUID(), toLotId: lot, originLotId: lot, quantityMl: '1', synthetic: true,
    })).status, 409);
    assert.equal((await f.request(consume, 'POST')).body.state, 'consumed');
    assert.equal((await f.request(f.siblingRoot + '/lots/' + lot + '/closure')).status, 404);
  } finally {
    try { await f?.close(); }
    finally {
      batches.closeAllConnections();
      await new Promise((done) => batches.close(done));
    }
  }
});
