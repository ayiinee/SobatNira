import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { compare, gateway, nativeInsight } from './production-insight.mjs';

const tenantId = '11111111-1111-1111-1111-111111111111';
const factoryId = '22222222-2222-2222-2222-222222222222';
const lotId = '33333333-3333-3333-3333-333333333333';
const flowId = '44444444-4444-4444-4444-444444444444';
const json = (response, status, body) => response.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify(body));

async function listen(t, server) {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  return `http://127.0.0.1:${server.address().port}`;
}

test('POC-01 REST harness checks parity, denies unauthenticated access and fails closed', async t => {
  const from = '2026-11-16T00:00:00Z', before = '2026-11-17T00:00:00Z';
  const ownerToken = 'synthetic-poc-owner', langflowKey = 'synthetic-flow-key';
  const gatewaySecret = 'test-secret-for-isolated-poc-contract';
  const sources = [{ lotId, snapshotId: flowId, batchIds: [] }];
  const scope = { tenantId, factoryId };
  const totals = { finalSugarKg: '25', productionMarginRupiah: '375000' };
  const grades = [{ code: 'A', weightKg: '25' }];
  const contributionBasis = 'consumed_nira_by_lot_received_at';
  const contributions = { basis: contributionBasis, status: 'complete', leadingCount: 1,
    leaders: [{ originLotId: lotId, lotCode: 'OCR-A-UJI', quantityMl: '40000' }], unit: 'mL', incompleteBatchIds: [] };
  const period = { from, before, periodBasis: 'lot_received_at' };
  let requests = 0;
  const apiOrigin = await listen(t, createServer(async (req, res) => {
    requests += 1;
    assert.equal(req.url, `/tenants/${tenantId}/factories/${factoryId}/capabilities/query`);
    if (req.headers.authorization !== `Bearer ${ownerToken}`) return json(res, 403, {});
    const input = await new Response(req).json();
    assert.equal(input.operation, 'get_production_insight');
    assert.deepEqual(input.arguments, { from, before, contributionBasis });
    return json(res, 200, { operation: input.operation, scope, status: 'ok', missing_relations: [],
      sources, result: { ...period, totals, grades, contributions } });
  }));
  const config = { apiOrigin, tenantId, factoryId, from, before, ownerToken, gatewaySecret, flowId, langflowKey };
  const gatewayOrigin = await listen(t, gateway(config));
  let changeResult = false;
  const langflowOrigin = await listen(t, createServer(async (req, res) => {
    assert.equal(req.url, `/api/v1/run/${flowId}`);
    if (req.headers['x-api-key'] !== langflowKey) return json(res, 401, {});
    assert.deepEqual(await new Response(req).json(), { output_type: 'chat' });
    const result = await fetch(gatewayOrigin + '/production-insight', { headers: { 'x-poc-secret': gatewaySecret } }).then(r => r.json());
    if (changeResult) result.totals.finalSugarKg = '999';
    return json(res, 200, { outputs: [{ outputs: [{ results: { message: { text: JSON.stringify(result) } } }] }] });
  }));
  assert.equal((await fetch(gatewayOrigin + '/production-insight')).status, 401);
  assert.equal((await fetch(gatewayOrigin + '/production-insight?factory=other')).status, 404);
  assert.equal(requests, 0);
  const report = await compare({ ...config, langflowOrigin });
  assert.equal(report.parity, true);
  assert.equal(requests, 2);
  t.diagnostic(`HTTP stub only: native ${report.native_ms} ms, REST ${report.langflow_ms} ms`);
  await assert.rejects(nativeInsight({ ...config, ownerToken: 'unauthorized' }), /HTTP 403/);
  await assert.rejects(compare({ ...config, langflowOrigin, langflowKey: 'unauthorized' }), /HTTP 401/);
  changeResult = true;
  await assert.rejects(compare({ ...config, langflowOrigin }), /keluaran langflow berbeda/i);
});
