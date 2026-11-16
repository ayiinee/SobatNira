const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
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
