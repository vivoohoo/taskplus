// Flow C (accept, reassign, status) and Flow D (filters), spec §11.
import { sql } from 'kysely';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Task, TaskStatus, Thread, User } from '../../db/schema';
import { badRequest, conflict, forbidden, notFound } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { canSeeThread, currentUser, otherUserId, threadRooms } from '../access';
import { taskDto } from '../dto';
import { warningsFor, withTasks } from '../messages/service';

const OPEN: TaskStatus[] = ['Open', 'Accepted', 'InProgress'];
/** Allowed moves for the assignee. */
const NEXT: Record<TaskStatus, TaskStatus[]> = { Open: [], Accepted: ['InProgress', 'Closed'], InProgress: ['Closed'], Closed: [] };

export async function taskRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);
  const { db } = app;

  async function load(me: User, id: string) {
    const task = await db.selectFrom('tasks').selectAll().where('id', '=', id).executeTakeFirst();
    if (!task) throw notFound('Task not found.');
    const thread = await db.selectFrom('threads').selectAll().where('id', '=', task.thread_id).executeTakeFirstOrThrow();
    if (!canSeeThread(me, thread) && task.assignee_id !== me.id) throw forbidden();
    const senderId = (await db.selectFrom('messages').select('sender_id').where('id', '=', task.message_id).executeTakeFirstOrThrow()).sender_id;
    return { task, thread, senderId };
  }

  /** The department a task is handled in: the thread's, or for a direct chat the recipient's. */
  async function handlingDept(thread: Thread, senderId: string) {
    if (thread.department_id) return thread.department_id;
    const r = await db.selectFrom('users').select('department_id').where('id', '=', otherUserId(thread, senderId)!).executeTakeFirst();
    return r?.department_id ?? null;
  }

  async function changed(task: Task, thread: Thread, senderId: string, event: { type: string; payload: Record<string, unknown> }, push?: { kind: string; to?: string[] }) {
    const fresh = await db.selectFrom('tasks').selectAll().where('id', '=', task.id).executeTakeFirstOrThrow();
    const dto = taskDto(fresh, (await warningsFor(db, [fresh])).get(fresh.id) ?? []);
    const rooms = [...threadRooms(thread), `user:${senderId}`, ...(fresh.assignee_id ? [`user:${fresh.assignee_id}`] : [])];
    app.services.realtime.emit(rooms, 'task.updated', { task: dto, event });
    if (push) await app.services.jobs.enqueue('notify', { taskId: task.id, kind: push.kind, toUserIds: push.to }, { jobId: `notify:${task.id}:${push.kind}:${Date.now()}` });
    return dto;
  }

  app.post('/tasks/:id/accept', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const me = await currentUser(db, req.userId);
    const { task, thread, senderId } = await load(me, id);
    if (senderId === me.id) throw forbidden('You sent this task.');
    const recipient = thread.type === 'direct' ? otherUserId(thread, senderId) === me.id : thread.department_id === me.department_id;
    if (!recipient) throw forbidden('Only the recipient can accept this task.');
    // Atomic: only one person can move it out of Open.
    const won = await sql<{ id: string }>`UPDATE tasks SET status = 'Accepted', assignee_id = ${me.id}, updated_at = SYSDATETIMEOFFSET()
      OUTPUT inserted.id WHERE id = ${task.id} AND status = 'Open'`.execute(db);
    if (!won.rows.length) {
      const now = await db.selectFrom('tasks').innerJoin('users', 'users.id', 'tasks.assignee_id').select(['users.id', 'users.name']).where('tasks.id', '=', task.id).executeTakeFirst();
      throw conflict('ALREADY_ACCEPTED', now ? `${now.name} already accepted this task.` : 'This task is no longer open.', { acceptedBy: now ?? null });
    }
    const payload = { by: me.id };
    await db.insertInto('task_events').values({ task_id: task.id, actor_id: me.id, type: 'accepted', payload: JSON.stringify(payload) }).execute();
    return { task: await changed(task, thread, senderId, { type: 'accepted', payload }, { kind: 'accepted' }) };
  });

  app.post('/tasks/:id/reassign', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const { assigneeId } = parse(z.object({ assigneeId: Id }), req.body);
    const me = await currentUser(db, req.userId);
    const { task, thread, senderId } = await load(me, id);
    if (task.status === 'Closed') throw badRequest('This task is closed.');
    const deptId = await handlingDept(thread, senderId);
    const isHead = me.role === 'dept_head' && !!deptId && me.department_id === deptId;
    if (!isHead && task.assignee_id !== me.id) throw forbidden('Only the department head or the assignee can reassign.');
    const target = await db.selectFrom('users').select(['id', 'department_id']).where('id', '=', assigneeId).where('is_active', '=', true).executeTakeFirst();
    if (!target || !deptId || target.department_id !== deptId) throw badRequest('Choose someone in the same department.');
    if (target.id === task.assignee_id) throw badRequest('They already have this task.');
    await db.updateTable('tasks').set({ assignee_id: target.id, status: task.status === 'Open' ? 'Accepted' : task.status, updated_at: new Date() })
      .where('id', '=', task.id).execute();
    const payload = { from: task.assignee_id, to: target.id };
    await db.insertInto('task_events').values({ task_id: task.id, actor_id: me.id, type: 'reassigned', payload: JSON.stringify(payload) }).execute();
    return { task: await changed(task, thread, senderId, { type: 'reassigned', payload }, { kind: 'reassigned', to: [target.id, senderId] }) };
  });

  app.post('/tasks/:id/status', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const { status } = parse(z.object({ status: z.enum(['InProgress', 'Closed']) }), req.body);
    const me = await currentUser(db, req.userId);
    const { task, thread, senderId } = await load(me, id);
    if (task.assignee_id !== me.id) throw forbidden('Only the assignee can change the status.');
    if (!NEXT[task.status].includes(status)) throw badRequest(`Can't go from ${task.status} to ${status}.`);
    const now = new Date();
    const r = await db.updateTable('tasks').set({ status, closed_at: status === 'Closed' ? now : null, updated_at: now })
      .where('id', '=', task.id).where('status', '=', task.status).executeTakeFirst();
    if (!Number(r.numUpdatedRows)) throw conflict('CHANGED', 'This task just changed. Refresh and try again.');
    const type = status === 'Closed' ? 'closed' : 'status_changed';
    const payload = { from: task.status, to: status };
    await db.insertInto('task_events').values({ task_id: task.id, actor_id: me.id, type, payload: JSON.stringify(payload) }).execute();
    return { task: await changed(task, thread, senderId, { type, payload }, { kind: 'status' }) };
  });

  // Flow D. my_pending: open and mine, or unclaimed and sent to me / my department. overdue: that, past due. closed: mine, newest first.
  app.get('/tasks', async (req) => {
    const { filter, cursor, limit } = parse(z.object({
      filter: z.enum(['my_pending', 'overdue', 'closed']),
      cursor: z.coerce.number().int().min(0).default(0),
      limit: z.coerce.number().int().min(1).max(100).default(30),
    }), req.query);
    const me = await currentUser(db, req.userId);
    let q = db.selectFrom('tasks').innerJoin('messages', 'messages.id', 'tasks.message_id').innerJoin('threads', 'threads.id', 'tasks.thread_id')
      .select('tasks.message_id');
    if (filter === 'closed') {
      q = q.where('tasks.status', '=', 'Closed').where((eb) => eb.or([eb('tasks.assignee_id', '=', me.id), eb('messages.sender_id', '=', me.id)]))
        .orderBy('tasks.closed_at', 'desc');
    } else {
      q = q.where('tasks.status', 'in', OPEN).where('messages.sender_id', '<>', me.id).where((eb) => eb.or([
        eb('tasks.assignee_id', '=', me.id),
        eb.and([eb('tasks.assignee_id', 'is', null), eb.or([
          eb.and([eb('threads.type', '=', 'direct'), eb.or([eb('threads.user_a_id', '=', me.id), eb('threads.user_b_id', '=', me.id)])]),
          ...(me.department_id ? [eb('tasks.department_id', '=', me.department_id)] : []),
        ])]),
      ]));
      if (filter === 'overdue') q = q.where('tasks.due_at', '<', new Date());
      q = q.orderBy('tasks.due_at', 'asc');
    }
    const rows = await q.orderBy('tasks.id').offset(cursor).fetch(limit + 1).execute();
    const msgs = rows.length ? await db.selectFrom('messages').selectAll().where('id', 'in', rows.slice(0, limit).map((r) => r.message_id)).execute() : [];
    const byId = new Map((await withTasks(db, msgs)).map((x) => [x.message.id, x]));
    return {
      items: rows.slice(0, limit).map((r) => byId.get(r.message_id)!),
      nextCursor: rows.length > limit ? cursor + limit : null,
    };
  });

  /** Counts for the filter badges. */
  app.get('/tasks/counts', async (req) => {
    const me = await currentUser(db, req.userId);
    const base = sql`FROM tasks t JOIN messages m ON m.id = t.message_id JOIN threads th ON th.id = t.thread_id
      WHERE t.status IN ('Open', 'Accepted', 'InProgress') AND m.sender_id <> ${me.id}
      AND (t.assignee_id = ${me.id} OR (t.assignee_id IS NULL AND ((th.type = 'direct' AND (th.user_a_id = ${me.id} OR th.user_b_id = ${me.id}))
        ${me.department_id ? sql`OR t.department_id = ${me.department_id}` : sql``})))`;
    const r = await sql<{ pending: number; overdue: number }>`SELECT COUNT(*) AS pending,
      SUM(CASE WHEN t.due_at < SYSDATETIMEOFFSET() THEN 1 ELSE 0 END) AS overdue ${base}`.execute(db);
    return { myPending: Number(r.rows[0]?.pending ?? 0), overdue: Number(r.rows[0]?.overdue ?? 0) };
  });
}
