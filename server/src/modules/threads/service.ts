import { sql } from 'kysely';
import type { Db } from '../../db/client';
import type { Message, Thread, User } from '../../db/schema';
import { badRequest, notFound } from '../../lib/errors';
import { otherUserId } from '../access';

const OPEN_STATUSES = ['Open', 'Accepted', 'InProgress'] as const;
const isDuplicate = (e: unknown) => [2601, 2627].includes((e as { number?: number }).number ?? 0);

/** The threads someone sees: their direct chats, chats they started with a department, and their department's inbox. */
export function threadsQuery(db: Db, u: User) {
  return db.selectFrom('threads').selectAll().where((eb) => eb.or([
    eb('user_a_id', '=', u.id),
    eb('user_b_id', '=', u.id),
    eb('requester_id', '=', u.id),
    ...(u.department_id ? [eb('department_id', '=', u.department_id)] : []),
  ]));
}

/** Get or create; two people opening the same chat at once still get one thread. */
export async function openThread(db: Db, me: User, target: { targetType: 'user' | 'department'; targetId: string }): Promise<Thread> {
  if (target.targetType === 'user') {
    if (target.targetId === me.id) throw badRequest('You cannot start a chat with yourself.');
    const other = await db.selectFrom('users').select('id').where('id', '=', target.targetId).where('is_active', '=', true).executeTakeFirst();
    if (!other) throw notFound('Person not found.');
    const [a, b] = [me.id, other.id].sort() as [string, string];
    const find = () => db.selectFrom('threads').selectAll().where('type', '=', 'direct').where('user_a_id', '=', a).where('user_b_id', '=', b).executeTakeFirst();
    const insert = () => db.insertInto('threads').values({ type: 'direct', user_a_id: a, user_b_id: b }).output('inserted.id').executeTakeFirstOrThrow();
    return getOrCreate(find, insert, db);
  }
  const dept = await db.selectFrom('departments').select('id').where('id', '=', target.targetId).executeTakeFirst();
  if (!dept) throw notFound('Department not found.');
  const find = () => db.selectFrom('threads').selectAll().where('type', '=', 'department').where('requester_id', '=', me.id).where('department_id', '=', dept.id).executeTakeFirst();
  const insert = () => db.insertInto('threads').values({ type: 'department', requester_id: me.id, department_id: dept.id }).output('inserted.id').executeTakeFirstOrThrow();
  return getOrCreate(find, insert, db);
}

async function getOrCreate(find: () => Promise<Thread | undefined>, insert: () => Promise<{ id: string }>, db: Db): Promise<Thread> {
  const found = await find();
  if (found) return found;
  try {
    const { id } = await insert();
    return await db.selectFrom('threads').selectAll().where('id', '=', id).executeTakeFirstOrThrow();
  } catch (e) {
    if (!isDuplicate(e)) throw e;
    return (await find())!;
  }
}

/** Chat list rows: who it is with, the last message, and how many tasks in it are still open. */
export async function listThreads(db: Db, me: User) {
  const threads = await threadsQuery(db, me).orderBy('last_message_at', 'desc').orderBy('created_at', 'desc').execute();
  if (!threads.length) return [];
  const ids = threads.map((t) => t.id);
  const [users, depts, lasts, open] = await Promise.all([
    db.selectFrom('users').select(['id', 'name', 'department_id', 'avatar_url']).execute(),
    db.selectFrom('departments').select(['id', 'name']).execute(),
    sql<Message>`SELECT * FROM (SELECT m.*, ROW_NUMBER() OVER (PARTITION BY m.thread_id ORDER BY m.created_at DESC) AS rn
      FROM messages m WHERE m.thread_id IN (${sql.join(ids)})) x WHERE x.rn = 1`.execute(db),
    db.selectFrom('tasks').select(['thread_id', db.fn.countAll<number>().as('n')]).where('thread_id', 'in', ids)
      .where('status', 'in', [...OPEN_STATUSES]).groupBy('thread_id').execute(),
  ]);
  const user = new Map(users.map((u) => [u.id, u])), dept = new Map(depts.map((d) => [d.id, d.name]));
  const last = new Map(lasts.rows.map((m) => [m.thread_id, m])), count = new Map(open.map((o) => [o.thread_id, Number(o.n)]));
  return threads.map((t) => {
    const m = last.get(t.id);
    let title: string, subtitle: string | null = null, avatarUrl: string | null = null;
    if (t.type === 'direct') {
      const o = user.get(otherUserId(t, me.id)!);
      title = o?.name ?? 'Unknown';
      subtitle = o?.department_id ? dept.get(o.department_id) ?? null : null;
      avatarUrl = o?.avatar_url ?? null;
    } else if (t.requester_id === me.id) {
      title = dept.get(t.department_id!) ?? 'Department';
      subtitle = 'Department';
    } else {
      title = user.get(t.requester_id!)?.name ?? 'Unknown';
      subtitle = `To ${dept.get(t.department_id!) ?? 'department'}`;
    }
    return {
      id: t.id, type: t.type, title, subtitle, avatarUrl,
      departmentId: t.department_id, requesterId: t.requester_id,
      lastMessage: m ? { senderId: m.sender_id, kind: m.kind, text: m.body_text ?? m.transcript, at: new Date(m.created_at).toISOString() } : null,
      lastMessageAt: t.last_message_at ? new Date(t.last_message_at).toISOString() : null,
      openTasks: count.get(t.id) ?? 0,
    };
  });
}

/** People and departments for the search screen. Empty search: recent chats first. */
export async function search(db: Db, me: User, q: string) {
  const like = `%${q.replace(/[%_[]/g, '[$&]')}%`;
  let users = db.selectFrom('users').select(['id', 'name', 'department_id', 'avatar_url']).where('is_active', '=', true).where('id', '<>', me.id);
  let depts = db.selectFrom('departments').select(['id', 'name']);
  if (q) {
    users = users.where((eb) => eb.or([eb('name', 'like', like), eb('phone', 'like', like)]));
    depts = depts.where('name', 'like', like);
  }
  const [us, ds] = await Promise.all([users.orderBy('name').execute(), depts.orderBy('name').execute()]);
  const deptName = new Map(ds.map((d) => [d.id, d.name]));
  const allDepts = q ? new Map((await db.selectFrom('departments').select(['id', 'name']).execute()).map((d) => [d.id, d.name])) : deptName;
  const items = [
    ...ds.map((d) => ({ type: 'department' as const, id: d.id, name: d.name, subtitle: 'Department', avatarUrl: null })),
    ...us.map((u) => ({ type: 'user' as const, id: u.id, name: u.name, subtitle: u.department_id ? allDepts.get(u.department_id) ?? null : null, avatarUrl: u.avatar_url })),
  ];
  if (!q) {
    // Recent chats first, in the order of their last message.
    const recent = (await threadsQuery(db, me).where('last_message_at', 'is not', null).orderBy('last_message_at', 'desc').execute())
      .map((t) => (t.type === 'direct' ? `user:${otherUserId(t, me.id)}` : t.requester_id === me.id ? `department:${t.department_id}` : null))
      .filter((k): k is string => !!k);
    const rank = (i: { type: string; id: string }) => { const r = recent.indexOf(`${i.type}:${i.id}`); return r < 0 ? Infinity : r; };
    items.sort((a, b) => rank(a) - rank(b));
  }
  return items.slice(0, 20);
}
