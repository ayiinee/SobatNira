const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { test } = require('node:test');
const { intakeFixture } = require('./intake-fixture.cjs');

test('owner updates factory profile and admin access within its scope', async () => {
  const fixture = await intakeFixture();
  const { client, root, siblingRoot, ids } = fixture;
  const owner = (path, method = 'GET', body) => fixture.request(path, method, body, 'fixture-owner');
  try {
    const profile = { version: 1, displayCode: 'PG-A', branchName: 'Cabang Uji', supportPhone: '+12025550101' };
    assert.equal((await fixture.request(root + '/profile', 'PATCH', profile)).status, 403);
    const updated = await owner(root + '/profile', 'PATCH', profile);
    assert.equal(updated.status, 200, JSON.stringify(updated.body));
    assert.equal(updated.body.version, 2);
    assert.equal((await fixture.request(root)).body.supportPhone, profile.supportPhone);
    assert.equal((await owner(root + '/profile', 'PATCH', profile)).status, 409);
    assert.equal((await fixture.request(siblingRoot)).body.supportPhone, null);

    const newAdmin = randomUUID();
    const email = 'new-admin@example.invalid';
    await client.query("INSERT INTO auth.users(id,aud,role,email) VALUES($1,'authenticated','authenticated',$2)", [newAdmin, email]);
    const add = await owner(root + '/memberships/admin', 'POST', { email });
    assert.equal(add.status, 201, JSON.stringify(add.body));
    assert.deepEqual(add.body, { userId: newAdmin, role: 'admin', isActive: true, inviteSent: false });
    assert.equal((await owner(root + '/memberships/admin', 'POST', { email })).status, 201);
    const target = root + '/memberships/' + ids.admin;
    assert.equal((await fixture.request(target, 'PATCH', { isActive: false })).status, 403);
    assert.equal((await owner(root + '/memberships/' + ids.owner, 'PATCH', { isActive: false })).status, 404);
    assert.equal((await owner(target, 'PATCH', { isActive: false })).status, 200);
    assert.equal((await fixture.request(root)).status, 403);
    assert.equal((await fixture.request(siblingRoot)).status, 200);
    assert.equal((await owner(target, 'PATCH', { isActive: true })).status, 200);
    assert.equal((await fixture.request(root)).status, 200);
    const audit = await client.query('SELECT action FROM sobatnira.factory_admin_events WHERE factory_id=$1 ORDER BY id', [ids.factory]);
    assert.deepEqual(audit.rows.map(row => row.action), [
      'profile_updated', 'admin_added', 'admin_deactivated', 'admin_activated',
    ]);
  } finally {
    await fixture.close();
  }
});
