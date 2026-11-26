// Builds the Fastify app. index.ts starts it; tests call buildApp() with their own providers.
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { sql } from 'kysely';
import { Redis } from 'ioredis';
import type { Env } from './config/env';
import type { Providers } from './container';
import type { Db } from './db/client';
import { jobHandlers } from './jobs/handlers';
import { bullmqQueue, inlineQueue, type JobHandlers, type JobQueue } from './jobs/queue';
import { AppError, unauthorized } from './lib/errors';
import type { Logger } from './lib/logger';
import { createMetrics, type Metrics } from './lib/metrics';
import { authRoutes } from './modules/auth/routes';
import { departmentRoutes } from './modules/departments/routes';
import { messageRoutes } from './modules/messages/routes';
import { taskRoutes } from './modules/tasks/routes';
import { threadRoutes } from './modules/threads/routes';
import { uploadRoutes } from './modules/uploads/routes';
import { deviceRoutes } from './modules/users/devices';
import { startRealtime, type Realtime } from './realtime';
import { DiskStorage } from './storage/disk';

export interface Services extends Providers { realtime: Realtime; jobs: JobQueue; handlers: JobHandlers; metrics: Metrics }

declare module 'fastify' {
  interface FastifyInstance {
    env: Env;
    db: Db;
    services: Services;
    authenticate: (req: FastifyRequest) => Promise<void>;
  }
  interface FastifyRequest { userId: string }
}

export interface AppDeps {
  env: Env; db: Db; logger: Logger; providers: Providers; metrics?: Metrics;
  /** Tests make retries fast with a small unit (ms). */
  backoffUnitMs?: number;
}

export async function buildApp({ env, db, logger, providers, metrics = createMetrics(), backoffUnitMs }: AppDeps) {
  const app = Fastify({ loggerInstance: logger, trustProxy: env.TRUST_PROXY, bodyLimit: 64 * 1024 });
  app.decorate('env', env);
  app.decorate('db', db);
  app.decorateRequest('userId', '');

  await app.register(jwt, { secret: env.JWT_SECRET });
  await app.register(rateLimit, { global: false, hook: 'preHandler' });

  app.decorate('authenticate', async (req: FastifyRequest) => {
    try {
      const p = await req.jwtVerify<{ sub: string; typ: string }>();
      if (p.typ !== 'access') throw new Error('wrong token type');
      req.userId = p.sub;
    } catch { throw unauthorized(); }
  });

  // Services: realtime needs the HTTP server; jobs need realtime. Built before routes so routes can use them.
  const services = { ...providers, metrics } as Services;
  app.decorate('services', services);
  services.realtime = await startRealtime(app as unknown as FastifyInstance); // pino logger type differs from Fastify's base logger type
  services.handlers = jobHandlers({ env, db, log: logger, realtime: services.realtime, storage: providers.storage, llm: providers.llm,
    stt: providers.stt, push: providers.push, metrics, jobs: () => services.jobs });
  services.jobs = env.QUEUE_MODE === 'bullmq'
    ? bullmqQueue(env.REDIS_URL, env.JOB_MAX_ATTEMPTS)
    : inlineQueue(services.handlers, { maxAttempts: env.JOB_MAX_ATTEMPTS, log: logger, unitMs: backoffUnitMs });
  // D6: every 6 hours, delete stored files older than FILE_RETENTION_DAYS (tasks, text and transcripts stay).
  const store = providers.storage;
  const retention = store instanceof DiskStorage
    ? setInterval(() => { store.deleteOlderThan(env.FILE_RETENTION_DAYS).then((n) => { if (n) logger.info({ removed: n }, 'old files deleted'); }).catch((e) => logger.error({ err: (e as Error).message }, 'file clean-up failed')); }, 6 * 3600_000)
    : undefined;
  retention?.unref();
  app.addHook('onClose', async () => { clearInterval(retention); await services.jobs.close(); await services.realtime.close(); });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof AppError) return reply.code(err.status).send({ error: { code: err.code, message: err.message, details: err.details } });
    const status = (err as { statusCode?: number }).statusCode;
    if (status === 429) return reply.code(429).send({ error: { code: 'RATE_LIMITED', message: 'Too many tries. Wait a little and try again.' } });
    if (status && status < 500) return reply.code(status).send({ error: { code: 'BAD_REQUEST', message: (err as Error).message } });
    req.log.error({ err }, 'unhandled error');
    return reply.code(500).send({ error: { code: 'INTERNAL', message: 'Something went wrong. Try again.' } });
  });
  app.setNotFoundHandler((_req, reply) => reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Not found.' } }));

  app.get('/healthz', async () => ({ ok: true }));
  // Ready = the database answers (and Redis, when the queue or realtime use it).
  app.get('/readyz', async (_req, reply) => {
    const checks: Record<string, boolean> = {};
    try { await sql`SELECT 1`.execute(db); checks.database = true; } catch { checks.database = false; }
    if (env.QUEUE_MODE === 'bullmq' || env.REALTIME_MODE === 'redis') {
      const r = new Redis(env.REDIS_URL, { lazyConnect: true, maxRetriesPerRequest: 1, connectTimeout: 2000 });
      try { await r.connect(); checks.redis = (await r.ping()) === 'PONG'; } catch { checks.redis = false; } finally { r.disconnect(); }
    }
    const ok = Object.values(checks).every(Boolean);
    return reply.code(ok ? 200 : 503).send({ ok, checks });
  });
  app.get('/metrics', async (_req, reply) => reply.type(metrics.registry.contentType).send(await metrics.registry.metrics()));

  await app.register(async (v1) => {
    await v1.register(authRoutes);
    await v1.register(deviceRoutes);
    await v1.register(threadRoutes);
    await v1.register(messageRoutes);
    await v1.register(taskRoutes);
    await v1.register(uploadRoutes);
    await v1.register(departmentRoutes);
  }, { prefix: '/v1' });
  return app;
}
