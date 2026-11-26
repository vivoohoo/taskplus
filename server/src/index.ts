// Starts the API. Bad or missing settings stop it here with a readable message.
import { buildApp } from './app';
import { loadEnv } from './config/env';
import { createProviders } from './container';
import { createDb } from './db/client';
import { createLogger } from './lib/logger';
import { createMetrics } from './lib/metrics';

let env;
try { env = loadEnv(); } catch (e) { console.error((e as Error).message); process.exit(1); }

const logger = createLogger(env.LOG_LEVEL, env.NODE_ENV === 'development');
const metrics = createMetrics();
let providers;
try { providers = createProviders(env, logger, metrics); } catch (e) { console.error((e as Error).message); process.exit(1); }
const db = createDb(env.DATABASE_URL);
const app = await buildApp({ env, db, logger, providers, metrics });

const stop = async () => { await app.close(); await db.destroy(); process.exit(0); };
process.on('SIGINT', stop);
process.on('SIGTERM', stop);

await app.listen({ port: env.PORT, host: '0.0.0.0' });
if (env.QUEUE_MODE === 'bullmq') logger.info('QUEUE_MODE=bullmq: start the worker with `npm run worker`');
