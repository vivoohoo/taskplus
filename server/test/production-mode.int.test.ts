// The production switches (spec §12): QUEUE_MODE=bullmq with a separate worker, REALTIME_MODE=redis, two API copies.
import { randomUUID } from 'node:crypto';
import { GenericContainer, type StartedTestContainer } from 'testcontainers';
import { io as connect } from 'socket.io-client';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app';
import { bullmqWorker } from '../src/jobs/queue';
import { createLogger } from '../src/lib/logger';
import { startTestApp, type TestApp } from './helpers/app';

let redis: StartedTestContainer | undefined;
let redisUrl: string;
let t: TestApp;
let worker: { close: () => Promise<void> };

beforeAll(async () => {
  redisUrl = process.env.TEST_REDIS_URL ?? '';
  if (!redisUrl) {
    redis = await new GenericContainer('redis:7-alpine').withExposedPorts(6379).start();
    redisUrl = `redis://${redis.getHost()}:${redis.getMappedPort(6379)}`;
  }
  t = await startTestApp({ QUEUE_MODE: 'bullmq', REALTIME_MODE: 'redis', REDIS_URL: redisUrl });
  // The worker is a separate consumer; here it shares the test's fake providers.
  worker = bullmqWorker(redisUrl, t.app.services.handlers, { log: createLogger('error'), unitMs: 5 });
}, 300_000);
afterAll(async () => { await worker?.close(); await t?.stop(); await redis?.stop(); });

describe('production mode', () => {
  it('structures through BullMQ and the worker', async () => {
    const tok = await t.token('9800000002');
    const dev = (await t.db.selectFrom('departments').select('id').where('name', '=', 'Development').executeTakeFirstOrThrow()).id;
    const th = (await t.as(tok).post('/v1/threads/open', { targetType: 'department', targetId: dev })).body.thread;
    const r = await t.as(tok).post(`/v1/threads/${th.id}/messages`, { clientMsgId: randomUUID(), kind: 'text', bodyText: 'Ornate invoice total off by one rupee' });
    expect(r.status).toBe(201);
    await t.app.services.jobs.idle();
    const task = await t.db.selectFrom('tasks').select(['ai_status', 'subject']).where('id', '=', r.body.task.id).executeTakeFirstOrThrow();
    expect(task).toEqual({ ai_status: 'done', subject: 'Test Task' });
    expect((await t.as(tok).get('/readyz')).body.checks).toEqual({ database: true, redis: true });
  });

  it('delivers an event from one API copy to a phone connected to another', async () => {
    const second = await buildApp({ env: t.env, db: t.db, logger: createLogger('error'), providers: t.fakes as never });
    await second.listen({ port: 0, host: '127.0.0.1' });
    try {
      const port = (second.server.address() as { port: number }).port;
      const dhaval = await t.token('9800000005');
      const riya = await t.token('9800000002');
      const s = connect(`http://127.0.0.1:${port}`, { auth: { token: dhaval }, transports: ['websocket'], forceNew: true });
      await new Promise<void>((res, rej) => { s.on('connect', () => res()); s.on('connect_error', rej); });
      const got = new Promise<{ message: { bodyText: string } }>((res) => s.once('message.created', res));
      const dhavalId = t.ids.get('9800000005')!;
      const th = (await t.as(riya).post('/v1/threads/open', { targetType: 'user', targetId: dhavalId })).body.thread;
      await t.as(riya).post(`/v1/threads/${th.id}/messages`, { clientMsgId: randomUUID(), kind: 'text', bodyText: 'cross-copy hello' });
      expect((await got).message.bodyText).toBe('cross-copy hello');
      s.disconnect();
    } finally {
      await second.close();
    }
  });
});
