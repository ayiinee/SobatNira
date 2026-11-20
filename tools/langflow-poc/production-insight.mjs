import { timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { isDeepStrictEqual } from 'node:util';
import { pathToFileURL } from 'node:url';

const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;

function loopback(value) {
  const url = new URL(value);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || url.username || url.password ||
    url.pathname !== '/' || url.search || url.hash) throw new Error('Gunakan origin HTTP loopback.');
  return url.origin;
}

async function post(url, headers, body) {
  const response = await fetch(url, {
    method: 'POST', headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

export async function nativeInsight(config) {
  const { tenantId, factoryId, from, before, ownerToken } = config;
  if (![tenantId, factoryId].every(id => uuid.test(id)) || !ownerToken) {
    throw new Error('Konfigurasi pabrik dan sesi sintetis diperlukan.');
  }
  const route = `${loopback(config.apiOrigin)}/tenants/${tenantId}/factories/${factoryId}/capabilities/query`;
  const operation = 'get_production_insight';
  const contributionBasis = 'consumed_nira_by_lot_received_at';
  const value = await post(route, { authorization: `Bearer ${ownerToken}` },
    { operation, arguments: { from, before, contributionBasis } });
  if (value.operation !== operation || value.scope?.tenantId !== tenantId || value.scope?.factoryId !== factoryId ||
    !['ok', 'partial'].includes(value.status) || value.result?.contributions?.basis !== contributionBasis) {
    throw new Error('Scope, status, atau basis dari NestJS tidak sesuai.');
  }
  const { result, sources, missing_relations, scope } = value;
  return { scope, period: { from: result.from, before: result.before, basis: result.periodBasis },
    totals: result.totals, grades: result.grades, contributions: result.contributions, sources, missing_relations };
}

export function gateway(config) {
  const token = Buffer.from(config.gatewaySecret ?? '');
  if (token.length < 32) throw new Error('Secret gateway POC minimal 32 byte.');
  return createServer(async (req, res) => {
    const handler = (status, value) => {
      res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      res.end(JSON.stringify(value));
    };
    if (req.method !== 'GET' || req.url !== '/production-insight') return handler(404, { error: 'NOT_FOUND' });
    const candidate = Buffer.from(req.headers['x-poc-secret'] ?? '');
    if (candidate.length !== token.length || !timingSafeEqual(candidate, token)) {
      return handler(401, { error: 'UNAUTHORIZED' });
    }
    try { handler(200, await nativeInsight(config)); }
    catch { handler(502, { error: 'CAPABILITIES_UNAVAILABLE' }); }
  });
}

export async function runLangflow(config) {
  if (!uuid.test(config.flowId) || !config.langflowKey) throw new Error('UUID flow dan API key Langflow diperlukan.');
  const response = await post(`${loopback(config.langflowOrigin)}/api/v1/run/${config.flowId}`,
    { 'x-api-key': config.langflowKey }, { output_type: 'chat' });
  const message = response.outputs?.[0]?.outputs?.[0]?.results?.message;
  const answer = message?.text ?? message?.data?.text;
  if (typeof answer !== 'string') throw new Error('Keluaran chat Langflow tidak sesuai kontrak POC.');
  return JSON.parse(answer);
}

export async function compare(config) {
  const start = performance.now();
  const native = await nativeInsight(config);
  const nativeMs = performance.now() - start;
  const langflowStart = performance.now();
  const langflow = await runLangflow(config);
  const langflowMs = performance.now() - langflowStart;
  if (!isDeepStrictEqual(native, langflow)) throw new Error('Keluaran Langflow berbeda dari data resmi NestJS.');
  return { parity: true, native_ms: Math.round(nativeMs), langflow_ms: Math.round(langflowMs) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const env = process.env;
  const config = { apiOrigin: 'http://127.0.0.1:8000', tenantId: env.POC_TENANT_ID, factoryId: env.POC_FACTORY_ID,
    ownerToken: env.POC_OWNER_TOKEN, from: env.POC_FROM, before: env.POC_BEFORE,
    gatewaySecret: env.SOBATNIRA_POC_GATEWAY_SECRET, langflowOrigin: env.POC_LANGFLOW_ORIGIN ?? 'http://127.0.0.1:7860',
    langflowKey: env.POC_LANGFLOW_KEY, flowId: env.POC_LANGFLOW_ID };
  try {
    if (process.argv[2] === 'gateway') gateway(config).listen(8765, '127.0.0.1', () => console.log('POC gateway 127.0.0.1:8765'));
    else if (process.argv[2] === 'compare') console.log(JSON.stringify(await compare(config)));
    else throw new Error('Gunakan gateway atau compare.');
  } catch (failure) {
    console.error(failure.message);
    process.exitCode = 1;
  }
}
