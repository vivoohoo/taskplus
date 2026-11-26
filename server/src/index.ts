// Starts the API. Bad or missing settings stop it here with a readable message.
import { buildApp } from './app';
import { loadEnv } from './config/env';
import { createDb } from './db/client';
import { createLogger } from './lib/logger';

let env;
try { env = loadEnv(); } catch (e) { console.error((e as Error).message); process.exit(1); }

const logger = createLogger(env.LOG_LEVEL, env.NODE_ENV === 'development');
const db = createDb(env.DATABASE_URL);
const app = await buildApp({ env, db, logger });

const stop = async () => { await app.close(); await db.destroy(); process.exit(0); };
process.on('SIGINT', stop);
process.on('SIGTERM', stop);

await app.listen({ port: env.PORT, host: '0.0.0.0' });
