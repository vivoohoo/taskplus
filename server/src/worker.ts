// npm run worker: runs background jobs from Redis (QUEUE_MODE=bullmq). Real-time events reach phones through the Redis adapter.
import { Emitter } from '@socket.io/redis-emitter';
import { Redis } from 'ioredis';
import { loadEnv } from './config/env';
import { createProviders } from './container';
import { createDb } from './db/client';
import { jobHandlers } from './jobs/handlers';
import { bullmqQueue, bullmqWorker } from './jobs/queue';
import { createLogger } from './lib/logger';
import { createMetrics } from './lib/metrics';
import type { Realtime } from './realtime';


const env = loadEnv();
if (env.QUEUE_MODE !== 'bullmq') { console.error('The worker is only for QUEUE_MODE=bullmq.'); process.exit(1); }
if (env.REALTIME_MODE !== 'redis') console.warn('REALTIME_MODE is not redis: events from the worker will not reach phones.');

const log = createLogger(env.LOG_LEVEL, env.NODE_ENV === 'development');
const metrics = createMetrics();
const providers = createProviders(env, log, metrics);
const db = createDb(env.DATABASE_URL);
const redis = new Redis(env.REDIS_URL, { maxRetriesPerRequest: null });
const emitter = new Emitter(redis);
const realtime: Realtime = {
  emit: (rooms, event, payload) => { if (rooms.length) emitter.to([...new Set(rooms)]).emit(event, payload); },
  close: async () => { redis.disconnect(); },
};
const jobs = bullmqQueue(env.REDIS_URL, env.JOB_MAX_ATTEMPTS);
const handlers = jobHandlers({ env, db, log, realtime, ...providers, metrics, jobs: () => jobs });
const worker = bullmqWorker(env.REDIS_URL, handlers, { log });
log.info('worker started');

const stop = async () => { await worker.close(); await jobs.close(); await realtime.close(); await db.destroy(); process.exit(0); };
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
