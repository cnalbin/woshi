import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp, loadConfig } from '../src/server.mjs';
import { validateResult } from '../src/validation.mjs';

const config = {
  apiKey: 'test-provider-key-not-real', accessToken: 'test-token-abcdefghijklmnopqrstuvwxyz',
  baseURL: 'https://provider.invalid', visionModel: 'vision-test', textModel: 'text-test',
  timeoutMS: 1000, rateLimit: 60, maxConcurrent: 3
};
const meal = { isFood: true, items: [{ name: '米饭', estimatedGrams: 150, estimatedKcal: 174 }],
  summary: '按可见米饭和常见熟重估算，需确认份量。', assumptions: ['份量未称重'], questions: ['实际吃下多少？'] };
const profile = { sex: 'male', age: 30, heightCM: 175, weightKG: 70 };
const photo = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(25)]).toString('base64');
const success = value => new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: {
  content: JSON.stringify(value), reasoning_content: 'PRIVATE_CHAIN_MUST_NEVER_BE_FORWARDED'
} }] }), { status: 200 });

async function fixture(t, fetchImpl = async () => success(meal), overrides = {}) {
  const app = createApp({ config: { ...config, ...overrides }, fetchImpl });
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { app.closeAllConnections(); app.close(resolve); }));
  return `http://127.0.0.1:${app.address().port}`;
}
function post(url, path, body, token = config.accessToken) {
  return fetch(`${url}/v1/analyze/${path}`, { method: 'POST', headers: {
    Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'
  }, body: JSON.stringify(body) });
}
function events(raw) {
  return raw.split('\n\n').filter(block => block.startsWith('event:')).map(block => {
    const lines = block.split('\n');
    return { type: lines[0].slice(7), data: JSON.parse(lines[1].slice(6)) };
  });
}

test('healthcheck exposes no secrets and all analysis routes require a token', async t => {
  const url = await fixture(t);
  assert.deepEqual(await (await fetch(`${url}/healthz`)).json(), { status: 'ok' });
  const response = await post(url, 'meal', { imageBase64: photo }, 'wrong');
  assert.equal(response.status, 401);
  assert.equal((await response.json()).code, 'UNAUTHORIZED');
});

test('real SSE stages, result shape and no internal reasoning or secret leakage', async t => {
  let request;
  const url = await fixture(t, async (endpoint, init) => {
    request = { endpoint, ...JSON.parse(init.body) };
    assert.equal(init.headers.Authorization, `Bearer ${config.apiKey}`);
    return success(meal);
  });
  const response = await post(url, 'meal', { imageBase64: photo, note: '半碗饭' });
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /text\/event-stream/);
  const raw = await response.text();
  const parsed = events(raw);
  assert.deepEqual(parsed.map(v => v.type), ['progress', 'progress', 'progress', 'result']);
  assert.deepEqual(parsed.slice(0, 3).map(v => v.data.stage), ['received', 'analyzing', 'validating']);
  assert.equal(parsed[3].data.items[0].estimatedKcal, 174);
  assert.equal(request.model, 'vision-test');
  assert.equal(request.response_format.type, 'json_object');
  assert.match(request.messages[1].content[1].image_url.url, /^data:image\/jpeg;base64,/);
  assert.doesNotMatch(raw, /PRIVATE_CHAIN|test-provider-key/);
});

test('metabolism forwards only necessary fields, independent of baseline calculation', async t => {
  let input;
  const expected = { estimatedKcal: 1700, summary: '按个人资料估算，并非代谢测量。', assumptions: ['没有体成分信息'] };
  const url = await fixture(t, async (_, init) => {
    const body = JSON.parse(init.body);
    input = JSON.parse(body.messages[1].content);
    assert.equal(body.model, 'text-test');
    return success(expected);
  });
  const response = await post(url, 'metabolism', { ...profile, healthData: 'do-not-send', formulaKcal: 1649 });
  const output = events(await response.text()).at(-1).data;
  assert.deepEqual(input, profile);
  assert.deepEqual(output, expected);
});

test('invalid profiles and photos are rejected before contacting provider', async t => {
  let calls = 0;
  const url = await fixture(t, async () => { calls++; return success(meal); });
  for (const input of [{ ...profile, age: 17 }, { ...profile, weightKG: -5 }, { ...profile, heightCM: '175' }, null]) {
    assert.equal((await post(url, 'metabolism', input)).status, 400);
  }
  for (const input of [{ imageBase64: 'not-an-image' }, { imageBase64: Buffer.alloc(30).toString('base64') },
    { imageBase64: photo, note: 'a'.repeat(501) }]) {
    assert.equal((await post(url, 'meal', input)).status, 400);
  }
  assert.equal(calls, 0);
});

test('non-food yields an actionable error, never a fabricated meal', async t => {
  const url = await fixture(t, async () => success({ ...meal, isFood: false, items: [] }));
  const raw = await (await post(url, 'meal', { imageBase64: photo })).text();
  assert.equal(events(raw).at(-1).type, 'error');
  assert.equal(events(raw).at(-1).data.code, 'NO_FOOD');
  assert.equal(events(raw).some(v => v.type === 'result'), false);
});

test('malformed, blank, truncated and out-of-range AI answers do not become results', async t => {
  const cases = [
    { choices: [{ finish_reason: 'stop', message: { content: '   ' } }] },
    { choices: [{ finish_reason: 'length', message: { content: JSON.stringify(meal) } }] },
    { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ ...meal, items: [{ name: '饭', estimatedGrams: 100, estimatedKcal: -1 }] }) } }] }
  ];
  let index = 0;
  const url = await fixture(t, async () => new Response(JSON.stringify(cases[index++])));
  for (let i = 0; i < cases.length; i++) {
    const output = events(await (await post(url, 'meal', { imageBase64: photo })).text());
    assert.equal(output.at(-1).type, 'error');
    assert.equal(output.some(v => v.type === 'result'), false);
  }
});

test('provider errors are sanitized, including provider authentication response', async t => {
  const url = await fixture(t, async () => new Response('provider-secret-stacktrace', { status: 401 }));
  const raw = await (await post(url, 'metabolism', profile)).text();
  assert.equal(events(raw).at(-1).data.code, 'PROVIDER_ERROR');
  assert.doesNotMatch(raw, /provider-secret-stacktrace/);
});

test('rate limiting rejects work without extra model calls', async t => {
  let calls = 0;
  const url = await fixture(t, async () => { calls++; return success(meal); }, { rateLimit: 1 });
  await (await post(url, 'meal', { imageBase64: photo })).text();
  const response = await post(url, 'meal', { imageBase64: photo });
  assert.equal(response.status, 429);
  assert.equal(calls, 1);
});

test('timeout is emitted over SSE and releases the concurrency slot', async t => {
  let first = true;
  const url = await fixture(t, async (_, { signal }) => {
    if (!first) return success(meal);
    first = false;
    return new Promise((_, reject) => signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }));
  }, { timeoutMS: 35, maxConcurrent: 1 });
  assert.equal(events(await (await post(url, 'meal', { imageBase64: photo })).text()).at(-1).data.code, 'TIMEOUT');
  assert.equal(events(await (await post(url, 'meal', { imageBase64: photo })).text()).at(-1).type, 'result');
});

test('client cancellation aborts the in-flight provider request', async t => {
  let observedAbort;
  const aborted = new Promise(resolve => { observedAbort = resolve; });
  const url = await fixture(t, async (_, { signal }) => new Promise((_, reject) => {
    signal.addEventListener('abort', () => { observedAbort(true); reject(new Error('cancelled')); }, { once: true });
  }));
  const response = await post(url, 'meal', { imageBase64: photo });
  const reader = response.body.getReader();
  await reader.read();
  await reader.cancel();
  assert.equal(await Promise.race([aborted, new Promise(resolve => setTimeout(() => resolve(false), 1500))]), true);
});

test('configuration rejects missing credentials and insecure upstream URLs', () => {
  assert.throws(() => loadConfig({}), /DEEPSEEK_API_KEY/);
  assert.throws(() => loadConfig({ DEEPSEEK_API_KEY: 'x', APP_ACCESS_TOKEN: 'short' }), /APP_ACCESS_TOKEN/);
  assert.throws(() => loadConfig({ DEEPSEEK_API_KEY: 'x', APP_ACCESS_TOKEN: 'a'.repeat(32), DEEPSEEK_BASE_URL: 'http://example.com' }), /HTTPS/);
});

test('validation strips arbitrary model fields and rejects non-finite metabolism', () => {
  assert.throws(() => validateResult('metabolism', { estimatedKcal: Infinity, summary: 'test', assumptions: [] }));
  assert.deepEqual(Object.keys(validateResult('meal', { ...meal, hidden: 'discard' })).sort(), ['assumptions', 'items', 'questions', 'summary']);
});
