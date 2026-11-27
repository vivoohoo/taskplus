// Flow C (accept, reassign, status) and Flow D (filters), spec §11.
import { sql } from 'kysely';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Task, TaskStatus, Thread, User } from '../../db/schema';
import { badRequest, forbidden, notFound } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { canSeeThread, currentUser, otherUserId, threadRooms } from '../access';
import { taskDto } from '../dto';
import { loadMessage, subtaskSettled, warningsFor, withTasks } from '../messages/service';
import { loadHolidays } from '../../workflow/clock';
import { ACTIONS, run, type Action, type Ctx } from '../../workflow/engine';
import { loadOrg, manages, teamsLedBy } from '../org';
import { kindOf } from '../people/routes';

const OPEN: TaskStatus[] = ['Open', 'Accepted', 'InProgress'];

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

  async function changed(task: Task, thread: Thread, senderId: string, event: { type: string; payload: Record<string, unknown> },
    push?: { kind: string; to?: string[]; text?: string; category?: string }, viewerId?: string) {
    const fresh = await db.selectFrom('tasks').selectAll().where('id', '=', task.id).executeTakeFirstOrThrow();
    const dto = viewerId ? (await withTasks(db, [await db.selectFrom('messages').selectAll().where('id', '=', fresh.message_id).executeTakeFirstOrThrow()], viewerId))[0]!.task!
      : taskDto(fresh, (await warningsFor(db, [fresh])).get(fresh.id) ?? []);
    const rooms = [...threadRooms(thread), `user:${senderId}`, ...(fresh.assignee_id ? [`user:${fresh.assignee_id}`] : [])];
    app.services.realtime.emit(rooms, 'task.updated', { task: dto, event });
    if (push) await app.services.jobs.enqueue('notify', { taskId: task.id, kind: push.kind, toUserIds: push.to, text: push.text, category: push.category }, { jobId: `notify:${task.id}:${push.kind}:${Date.now()}` });
    return dto;
  }

  /** Any workflow action (docs/PARITY.md step 3). The engine checks who may do it; the result is saved, shown live and pushed. */
  async function act(req: { params: unknown; body: unknown; userId: string }, action: Action) {
    const { id } = parse(z.object({ id: Id }), req.params);
    const me = await currentUser(db, req.userId);
    const { task, thread, senderId } = await load(me, id);
    const ctx: Ctx = { db, env: app.env, org: await loadOrg(db), holidays: await loadHolidays(db), now: new Date(), me, task, thread, senderId };
    const r = await run(ctx, action, req.body);
    await db.insertInto('task_events').values({ task_id: task.id, actor_id: me.id, type: r.type, payload: JSON.stringify(r.payload) }).execute();
    const to = [...new Set(r.push?.to ?? [])].filter((x) => x && x !== me.id);
    const dto = await changed(task, thread, senderId, { type: r.type, payload: r.payload }, to.length ? { kind: 'status', to, text: r.push!.text, category: kindOf(r.type) } : undefined, me.id);
    if (r.restructure) await app.services.jobs.enqueue('structure', { taskId: task.id }, { jobId: `structure:${task.id}:${Date.now()}` });
    // A sub-task that just ended moves its parent on (Ornate).
    if (task.parent_task_id && ['Completed', 'Rejected', 'Cancelled', 'Transferred'].includes(dto.status)) await settled(task, me.id);
    for (const sid of r.cancelledSubs ?? []) {
      const sub = await db.selectFrom('tasks').selectAll().where('id', '=', sid).executeTakeFirstOrThrow();
      const sth = await db.selectFrom('threads').selectAll().where('id', '=', sub.thread_id).executeTakeFirstOrThrow();
      app.services.realtime.emit(threadRooms(sth), 'task.updated', { task: taskDto(sub), event: { type: 'cancelled', payload: { reason: 'No longer needed' } } });
    }
    if (r.newTaskId) {
      const nt = await db.selectFrom('tasks').select(['id', 'message_id', 'thread_id']).where('id', '=', r.newTaskId).executeTakeFirstOrThrow();
      const nthread = await db.selectFrom('threads').selectAll().where('id', '=', nt.thread_id).executeTakeFirstOrThrow();
      app.services.realtime.emit(threadRooms(nthread), 'message.created', await loadMessage(db, nt.message_id));
      await app.services.jobs.enqueue('notify', { taskId: nt.id, kind: 'created' }, { jobId: `notify:${nt.id}:created` });
    }
    return { task: dto };
  }

  async function settled(sub: Task, actorId: string) {
    const p = await subtaskSettled(db, sub, actorId);
    if (!p) return;
    const fresh = await db.selectFrom('tasks').selectAll().where('id', '=', p.id).executeTakeFirstOrThrow();
    const pth = await db.selectFrom('threads').selectAll().where('id', '=', p.thread_id).executeTakeFirstOrThrow();
    app.services.realtime.emit([...threadRooms(pth), ...(p.assignee_id ? [`user:${p.assignee_id}`] : [])], 'task.updated', { task: taskDto(fresh), event: { type: 'subtask_done', payload: { subTaskId: sub.id } } });
    if (p.assignee_id) await app.services.jobs.enqueue('notify', { taskId: p.id, kind: 'status', toUserIds: [p.assignee_id], text: `sub-task ${sub.ticket_no ?? ''} finished` }, { jobId: `notify:${p.id}:sub:${sub.id}` });
  }

  /** One task with this viewer's buttons: the app re-reads it after a live event (events are shared by many viewers). */
  app.get('/tasks/:id', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const me = await currentUser(db, req.userId);
    const { task } = await load(me, id);
    const m = await db.selectFrom('messages').selectAll().where('id', '=', task.message_id).executeTakeFirstOrThrow();
    return (await withTasks(db, [m], me.id))[0];
  });

  app.post('/tasks/:id/actions/:action', async (req) => {
    const { action } = parse(z.object({ action: z.enum(ACTIONS) }), req.params);
    return act(req, action);
  });
  app.post('/tasks/:id/accept', async (req) => act(req, 'accept'));
  app.post('/tasks/:id/cancel', async (req) => act(req, 'cancel'));

  app.post('/tasks/:id/reassign', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const { assigneeId } = parse(z.object({ assigneeId: Id }), req.body);
    const me = await currentUser(db, req.userId);
    const { task, thread, senderId } = await load(me, id);
    if (task.status === 'Closed') throw badRequest('This task is closed.');
    const deptId = await handlingDept(thread, senderId);
    const org = await loadOrg(db);
    const isHead = me.role === 'dept_head' && !!deptId && me.department_id === deptId;
    // A team lead may move work in the teams they look after (theirs and those of leads reporting to them).
    const leadOfIt = !!task.assignee_id ? manages(org, me.id, task.assignee_id) : !!task.team_id && teamsLedBy(org, me.id).includes(task.team_id);
    if (!isHead && !leadOfIt && task.assignee_id !== me.id) throw forbidden('Only the assignee, their team lead or the department head can reassign.');
    const target = await db.selectFrom('users').select(['id', 'department_id']).where('id', '=', assigneeId).where('is_active', '=', true).executeTakeFirst();
    if (!target || !deptId || target.department_id !== deptId) throw badRequest('Choose someone in the same department.');
    if (!isHead && task.assignee_id !== me.id && !manages(org, me.id, target.id) && target.id !== me.id) throw badRequest('Choose someone in a team you lead.');
    if (target.id === task.assignee_id) throw badRequest('They already have this task.');
    await db.updateTable('tasks').set({ assignee_id: target.id, status: task.status === 'Open' ? 'Accepted' : task.status, reassign_requested_by: null,
      ...(task.status === 'Open' ? { accepted_at: new Date(), clock_state: 'running' as const, clock_running_since: new Date() } : {}), updated_at: new Date() })
      .where('id', '=', task.id).execute();
    const payload = { from: task.assignee_id, to: target.id };
    await db.insertInto('task_events').values({ task_id: task.id, actor_id: me.id, type: 'reassigned', payload: JSON.stringify(payload) }).execute();
    return { task: await changed(task, thread, senderId, { type: 'reassigned', payload }, { kind: 'reassigned', to: [target.id, senderId] }, me.id) };
  });

  // Flow D. my_pending: open and mine, or unclaimed and sent to me / my department. overdue: that, past due. closed: mine, newest first.
  app.get('/tasks', async (req) => {
    const { filter, cursor, limit } = parse(z.object({
      filter: z.enum(['my_pending', 'overdue', 'sent_by_me', 'closed']),
      cursor: z.coerce.number().int().min(0).default(0),
      limit: z.coerce.number().int().min(1).max(100).default(30),
    }), req.query);
    const me = await currentUser(db, req.userId);
    const myTeams = [...new Set([...(me.team_id ? [me.team_id] : []), ...teamsLedBy(await loadOrg(db), me.id)])];
    let q = db.selectFrom('tasks').innerJoin('messages', 'messages.id', 'tasks.message_id').innerJoin('threads', 'threads.id', 'tasks.thread_id')
      .select('tasks.message_id');
    if (filter === 'sent_by_me') {
      // D1: still-open tasks I sent, soonest due first.
      q = q.where('messages.sender_id', '=', me.id).where('tasks.status', 'not in', ['Closed', 'Rejected', 'Transferred', 'Cancelled', 'Verified'])
        .orderBy('tasks.due_at', 'asc');
    } else if (filter === 'closed') {
      q = q.where('tasks.status', '=', 'Closed').where((eb) => eb.or([eb('tasks.assignee_id', '=', me.id), eb('messages.sender_id', '=', me.id)]))
        .orderBy('tasks.closed_at', 'desc');
    } else {
      q = q.where('tasks.status', 'in', OPEN).where('messages.sender_id', '<>', me.id).where((eb) => eb.or([
        eb('tasks.assignee_id', '=', me.id),
        eb.and([eb('tasks.assignee_id', 'is', null), eb.or([
          eb.and([eb('threads.type', '=', 'direct'), eb.or([eb('threads.user_a_id', '=', me.id), eb('threads.user_b_id', '=', me.id)])]),
          ...(me.department_id ? [eb.and([eb('tasks.department_id', '=', me.department_id),
            eb.or([eb('tasks.team_id', 'is', null), ...(myTeams.length ? [eb('tasks.team_id', 'in', myTeams)] : [])])])] : []),
        ])]),
      ]));
      if (filter === 'overdue') q = q.where('tasks.due_at', '<', new Date());
      q = q.orderBy('tasks.due_at', 'asc');
    }
    const rows = await q.orderBy('tasks.id').offset(cursor).fetch(limit + 1).execute();
    const msgs = rows.length ? await db.selectFrom('messages').selectAll().where('id', 'in', rows.slice(0, limit).map((r) => r.message_id)).execute() : [];
    const byId = new Map((await withTasks(db, msgs, me.id)).map((x) => [x.message.id, x]));
    return {
      items: rows.slice(0, limit).map((r) => byId.get(r.message_id)!),
      nextCursor: rows.length > limit ? cursor + limit : null,
    };
  });

  /** Counts for the filter badges. */
  app.get('/tasks/counts', async (req) => {
    const me = await currentUser(db, req.userId);
    const myTeams = [...new Set([...(me.team_id ? [me.team_id] : []), ...teamsLedBy(await loadOrg(db), me.id)])];
    const base = sql`FROM tasks t JOIN messages m ON m.id = t.message_id JOIN threads th ON th.id = t.thread_id
      WHERE t.status IN ('Open', 'Accepted', 'InProgress') AND m.sender_id <> ${me.id}
      AND (t.assignee_id = ${me.id} OR (t.assignee_id IS NULL AND ((th.type = 'direct' AND (th.user_a_id = ${me.id} OR th.user_b_id = ${me.id}))
        ${me.department_id ? sql`OR (t.department_id = ${me.department_id} AND (t.team_id IS NULL ${myTeams.length ? sql`OR t.team_id IN (${sql.join(myTeams)})` : sql``}))` : sql``})))`;
    const r = await sql<{ pending: number; overdue: number }>`SELECT COUNT(*) AS pending,
      SUM(CASE WHEN t.due_at < SYSDATETIMEOFFSET() THEN 1 ELSE 0 END) AS overdue ${base}`.execute(db);
    const sent = await sql<{ n: number }>`SELECT COUNT(*) AS n FROM tasks t JOIN messages m ON m.id = t.message_id
      WHERE m.sender_id = ${me.id} AND t.status NOT IN ('Closed', 'Rejected', 'Transferred', 'Cancelled', 'Verified')`.execute(db);
    return { myPending: Number(r.rows[0]?.pending ?? 0), overdue: Number(r.rows[0]?.overdue ?? 0), sentByMe: Number(sent.rows[0]?.n ?? 0) };
  });
}
