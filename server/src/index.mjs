import { createApp, loadConfig } from './server.mjs';

const config = loadConfig();
const server = createApp({ config });
server.requestTimeout = 30000;
server.headersTimeout = 15000;
server.listen(Number(process.env.PORT) || 8787, process.env.HOST || '127.0.0.1', () => {
  console.log('QingJi API is ready. No personal request data is logged.');
});
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10000).unref();
  });
}
