import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { Id, parse } from '../../lib/validate';
import { currentUser } from '../access';
import { listThreads, openThread, search } from './service';

export async function threadRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);

  app.get('/search', async (req) => {
    const { q } = parse(z.object({ q: z.string().max(100).default('') }), req.query);
    return { results: await search(app.db, await currentUser(app.db, req.userId), q.trim()) };
  });

  app.post('/threads/open', async (req) => {
    const body = parse(z.object({ targetType: z.enum(['user', 'department', 'team', 'self']), targetId: Id.optional() }), req.body);
    const me = await currentUser(app.db, req.userId);
    const t = await openThread(app.db, me, body);
    return { thread: (await listThreads(app.db, me)).find((x) => x.id === t.id) };
  });

  app.get('/threads', async (req) => ({ threads: await listThreads(app.db, await currentUser(app.db, req.userId)) }));
}
