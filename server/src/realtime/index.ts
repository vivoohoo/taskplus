// Socket.IO on the API's own HTTP server (spec §8).
// Rooms: user:{id}, dept:{departmentId}, thread:{id} (joined while a chat screen is open).
// REALTIME_MODE=redis shares rooms across several API copies through Redis.
import { createAdapter } from '@socket.io/redis-adapter';
import type { FastifyInstance } from 'fastify';
import { Redis } from 'ioredis';
import { Server } from 'socket.io';
import { canSeeThread, currentUser, isUuid } from '../modules/access';

export type RealtimeEvent = 'message.created' | 'task.transcribed' | 'task.structured' | 'task.updated' | 'notification';

/** What the rest of the server uses: send one event to a set of rooms. */
export interface Realtime { emit(rooms: string[], event: RealtimeEvent, payload: unknown): void; close(): Promise<void> }

export async function startRealtime(app: FastifyInstance): Promise<Realtime> {
  const io = new Server(app.server, { cors: { origin: false }, serveClient: false });
  let pub: Redis | undefined, sub: Redis | undefined;
  if (app.env.REALTIME_MODE === 'redis') {
    pub = new Redis(app.env.REDIS_URL, { lazyConnect: false, maxRetriesPerRequest: 3 });
    sub = pub.duplicate();
    io.adapter(createAdapter(pub, sub));
  }

  io.use(async (socket, next) => {
    try {
      const token = String(socket.handshake.auth?.token ?? '');
      const p = app.jwt.verify<{ sub: string; typ: string }>(token);
      if (p.typ !== 'access') throw new Error('wrong token type');
      const user = await currentUser(app.db, p.sub);
      socket.data.user = user;
      await socket.join(`user:${user.id}`);
      if (user.department_id) await socket.join(`dept:${user.department_id}`);
      next();
    } catch {
      next(new Error('UNAUTHORIZED'));
    }
  });

  io.on('connection', (socket) => {
    // The chat screen joins its thread room; access is checked like the HTTP endpoints.
    socket.on('thread.join', async (threadId: unknown, ack?: (r: { ok: boolean }) => void) => {
      if (!isUuid(threadId)) return ack?.({ ok: false });
      const t = await app.db.selectFrom('threads').selectAll().where('id', '=', threadId.toUpperCase()).executeTakeFirst();
      const ok = !!t && canSeeThread(socket.data.user, t);
      if (ok) await socket.join(`thread:${t.id}`);
      ack?.({ ok });
    });
    socket.on('thread.leave', (threadId: unknown) => { if (isUuid(threadId)) void socket.leave(`thread:${threadId.toUpperCase()}`); });
  });

  return {
    emit: (rooms, event, payload) => { if (rooms.length) io.to([...new Set(rooms)]).emit(event, payload); },
    close: async () => { await io.close(); pub?.disconnect(); sub?.disconnect(); },
  };
}
