// Only for end-to-end UI verification; no external network or provider credentials.
import { createApp } from '../../src/server.mjs';
if (process.env.QINGJI_CI_MOCK !== '1') throw new Error('This fixture requires explicit QINGJI_CI_MOCK=1.');
const server = createApp({
  config: {
    apiKey: 'ci-fake-provider-key', accessToken: 'ci-only-token-abcdefghijklmnopqrstuvwxyz',
    baseURL: 'https://not-used.invalid', visionModel: 'mock', textModel: 'mock',
    timeoutMS: 15000, rateLimit: 100, maxConcurrent: 3
  },
  fetchImpl: async (_, { signal }) => {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(resolve, 2500);
      signal.addEventListener('abort', () => { clearTimeout(timer); reject(new Error('cancelled')); }, { once: true });
    });
    return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
      estimatedKcal: 1700, summary: 'UI 集成测试：已通过真实 SSE 接收代谢结果。', assumptions: ['测试模拟值，不是实测或真实模型回答']
    }) } }] }));
  }
});
server.listen(8787, '127.0.0.1');
