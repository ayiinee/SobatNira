const test = require('node:test');
const assert = require('node:assert/strict');
const { AdaptivePoller, documentPollSettings } = require('../dist/documents/adaptive-poller');

test('serial poller bounds idle/error backoff, resets after work and cancels shutdown timer', async () => {
  const timers = [], outcomes = [false, false, false, true, new Error('private')];
  let warnings = 0;
  const schedule = (work, delay) => { const timer = { work, delay, cancelled: false }; timers.push(timer); return () => { timer.cancelled = true; }; };
  const p = new AdaptivePoller(async () => { const result = outcomes.shift(); if (result instanceof Error) throw result; return result; },
    { minMs: 500, maxMs: 2000 }, () => { warnings++; }, schedule);
  p.start(); p.start(); assert.equal(timers.length, 1);
  assert.equal(timers.at(-1).delay, 500);
  for (const expected of [1000, 2000, 2000, 0, 1000]) { await timers.at(-1).work(); assert.equal(timers.at(-1).delay, expected); }
  assert.equal(warnings, 1); assert.equal(p.statistics().errors, 1); assert.equal(p.statistics().empty, 3);
  await p.stop(); assert.equal(timers.at(-1).cancelled, true);
  const count = timers.length; await timers.at(-1).work(); assert.equal(timers.length, count);
});

test('shutdown waits for current claim/work and does not rearm when it finishes', async () => {
  let tick, release;
  const gate = new Promise(resolve => { release = resolve; });
  let scheduled = 0;
  const p = new AdaptivePoller(async () => { await gate; return true; }, { minMs: 500, maxMs: 500 }, () => {},
    work => { scheduled++; tick = work; return () => {}; });
  p.start(); const running = tick();
  let stopped = false; const stopping = p.stop().then(() => { stopped = true; });
  await Promise.resolve(); assert.equal(stopped, false);
  release(); await running; await stopping;
  assert.equal(stopped, true); assert.equal(scheduled, 1);
});

test('poll settings retain legacy idle interval unless explicitly changed and reject invalid bounds', () => {
  assert.deepEqual(documentPollSettings({}), { minMs: 500, maxMs: 500 });
  for (const env of [{ DOCUMENT_POLL_MIN_MS: '0' }, { DOCUMENT_POLL_MAX_MS: 'NaN' },
    { DOCUMENT_POLL_MAX_MS: '30001' }, { DOCUMENT_POLL_MIN_MS: '1000', DOCUMENT_POLL_MAX_MS: '500' }]) assert.throws(() => documentPollSettings(env));
});
