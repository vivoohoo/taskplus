// Builds the Fastify app. index.ts starts it; tests call buildApp() directly.
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyRequest } from 'fastify';
import type { Env } from './config/env';
import type { Db } from './db/client';
import { AppError, unauthorized } from './lib/errors';
import type { Logger } from './lib/logger';
import { authRoutes } from './modules/auth/routes';
import { deviceRoutes } from './modules/users/devices';

declare module 'fastify' {
  interface FastifyInstance {
    env: Env;
    db: Db;
    authenticate: (req: FastifyRequest) => Promise<void>;
  }
  interface FastifyRequest { userId: string }
}

export async function buildApp({ env, db, logger }: { env: Env; db: Db; logger: Logger }) {
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
  await app.register(async (v1) => {
    await v1.register(authRoutes);
    await v1.register(deviceRoutes);
  }, { prefix: '/v1' });
  return app;
}
