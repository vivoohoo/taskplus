import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { Id, parse } from '../../lib/validate';
import { currentUser, threadFor, threadRooms } from '../access';
import { createMessage, listMessages } from './service';

export async function messageRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);

  app.get('/threads/:id/messages', async (req) => {
    const { id } = req.params as { id: string };
    const { before, limit } = parse(z.object({ before: Id.optional(), limit: z.coerce.number().int().min(1).max(100).default(30) }), req.query);
    const me = await currentUser(app.db, req.userId);
    return listMessages(app.db, await threadFor(app.db, me, id), before, limit);
  });

  app.post('/threads/:id/messages', {
    // 30 messages a minute per person. The limiter may run before sign-in is checked, so it reads the token itself.
    config: { rateLimit: { max: 30, timeWindow: '1 minute', keyGenerator: (req) => `msg:${app.jwt.decode<{ sub?: string }>(String(req.headers.authorization ?? '').replace(/^Bearer /, ''))?.sub ?? req.ip}` } },
  }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const me = await currentUser(app.db, req.userId);
    const thread = await threadFor(app.db, me, id);
    const r = await createMessage(app.db, app.env, app.services.storage, me, thread, req.body);
    if (r.created) {
      app.services.realtime.emit(threadRooms(thread), 'message.created', { message: r.message, task: r.task });
      const taskId = r.task!.id;
      if (r.message.kind === 'voice') await app.services.jobs.enqueue('transcribe', { messageId: r.message.id, taskId }, { jobId: `transcribe:${taskId}` });
      else await app.services.jobs.enqueue('structure', { taskId }, { jobId: `structure:${taskId}` });
    }
    return reply.code(r.created ? 201 : 200).send({ message: r.message, task: r.task });
  });
}
