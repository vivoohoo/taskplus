// Who may see what. Every thread and task endpoint goes through these.
import type { Db } from '../db/client';
import type { Thread, User } from '../db/schema';
import { forbidden, notFound, unauthorized } from '../lib/errors';

export async function currentUser(db: Db, id: string): Promise<User> {
  const u = await db.selectFrom('users').selectAll().where('id', '=', id).where('is_active', '=', true).executeTakeFirst();
  if (!u) throw unauthorized();
  return u;
}

/** Direct: one of the pair. Department: the requester, or anyone in that department. Private notes: only their writer. */
export const canSeeThread = (u: User, t: Thread) =>
  t.type === 'direct' ? t.user_a_id === u.id || t.user_b_id === u.id
  : t.type === 'self' ? t.requester_id === u.id
  : t.requester_id === u.id || t.department_id === u.department_id;

export async function threadFor(db: Db, u: User, threadId: string): Promise<Thread> {
  if (!isUuid(threadId)) throw notFound('Chat not found.');
  const t = await db.selectFrom('threads').selectAll().where('id', '=', threadId.toUpperCase()).executeTakeFirst();
  if (!t) throw notFound('Chat not found.');
  if (!canSeeThread(u, t)) throw forbidden();
  return t;
}

/** Socket.IO rooms that should hear about activity in a thread. */
export const threadRooms = (t: Thread) =>
  t.type === 'direct'
    ? [`thread:${t.id}`, `user:${t.user_a_id}`, `user:${t.user_b_id}`]
    : t.type === 'self' ? [`thread:${t.id}`, `user:${t.requester_id}`]
    : [`thread:${t.id}`, `user:${t.requester_id}`, `dept:${t.department_id}`];

/** The other side of a direct thread, as seen by `me`. */
export const otherUserId = (t: Thread, me: string) => (t.user_a_id === me ? t.user_b_id : t.user_a_id);

export const isUuid = (v: unknown): v is string => typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
