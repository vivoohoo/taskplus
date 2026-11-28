// People and settings from Ornate (docs/PARITY.md step 4): away, shift, muted alerts, holidays, suggestions, customers,
// a task's history and files, and task search.
import type { FastifyInstance } from 'fastify';
import { sql } from 'kysely';
import { z } from 'zod';
import { badRequest, forbidden, notFound } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { SHIFT_LABELS } from '../../workflow/time';
import { canSeeThread, currentUser } from '../access';
import { withTasks } from '../messages/service';
import { manages, loadOrg } from '../org';
import { escalatedTo, hiddenFromLeads } from '../../workflow/engine';

/** Alert kinds. Must-haves (Ornate / User Guide section 19) can't be switched off. */
export const NOTIF_KINDS = [
  { id: 'new', label: 'New task for you or your team', required: true },
  { id: 'accept', label: 'Accepted, reassigned, rejected', required: true },
  { id: 'question', label: 'Questions and answers', required: true },
  { id: 'escalation', label: 'Escalations' },
  { id: 'deadline', label: 'Due soon and overdue' },
  { id: 'update', label: 'Other updates (in progress, completed, verified, blocked…)' },
] as const;

/** Which alert kind a task event belongs to. */
export const kindOf = (eventType: string): string =>
  ({ created: 'new', accepted: 'accept', reassigned: 'accept', rejected: 'accept', transferred: 'accept', cancelled: 'accept',
    question: 'question', answered: 'question', escalated: 'escalation', attended: 'escalation', warned: 'deadline' } as Record<string, string>)[eventType] ?? 'update';

const isHeadOrAdmin = (u: { role: string }) => u.role === 'dept_head' || u.role === 'admin';

export async function peopleRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);
  const { db } = app;

  // ---- you ----
  app.put('/me/away', async (req) => {
    const { away } = parse(z.object({ away: z.boolean() }), req.body);
    await db.updateTable('users').set({ away, updated_at: new Date() }).where('id', '=', req.userId).execute();
    return { away };
  });
  app.get('/shifts', async () => ({ shifts: SHIFT_LABELS.map((label, id) => ({ id, label: `${label}, Mon–Sat` })) }));
  app.put('/me/shift', async (req) => {
    const { shift } = parse(z.object({ shift: z.number().int().min(0).max(SHIFT_LABELS.length - 1) }), req.body);
    await db.updateTable('users').set({ shift }).where('id', '=', req.userId).execute();
    return { shift };
  });
  /** A lead sets the shift of someone in a team they look after. */
  app.put('/users/:id/shift', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const { shift } = parse(z.object({ shift: z.number().int().min(0).max(SHIFT_LABELS.length - 1) }), req.body);
    if (!manages(await loadOrg(db), req.userId, id)) throw forbidden('You can only set shifts in your own teams.');
    await db.updateTable('users').set({ shift }).where('id', '=', id).execute();
    return { shift };
  });
  app.get('/me/notifications', async (req) => {
    const me = await currentUser(db, req.userId);
    return { kinds: NOTIF_KINDS, muted: JSON.parse(me.muted_kinds) as string[] };
  });
  app.put('/me/notifications', async (req) => {
    const { muted } = parse(z.object({ muted: z.array(z.string()).max(20) }), req.body);
    const allowed = NOTIF_KINDS.filter((k) => !('required' in k)).map((k) => k.id as string);
    const clean = [...new Set(muted.filter((m) => allowed.includes(m)))];
    await db.updateTable('users').set({ muted_kinds: JSON.stringify(clean) }).where('id', '=', req.userId).execute();
    return { muted: clean };
  });

  // ---- public holidays: the clock skips them; department heads and admins edit ----
  app.get('/holidays', async () => ({
    holidays: (await db.selectFrom('holidays').selectAll().orderBy('day').execute()).map((h) => ({ day: new Date(h.day).toISOString().slice(0, 10), name: h.name })),
  }));
  app.post('/holidays', async (req) => {
    const { day, name } = parse(z.object({ day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), name: z.string().trim().max(80).optional() }), req.body);
    if (!isHeadOrAdmin(await currentUser(db, req.userId))) throw forbidden('Only department heads can change holidays.');
    if (await db.selectFrom('holidays').select('day').where(sql`day`, '=', sql`CAST(${day} AS date)`).executeTakeFirst()) throw badRequest('That day is already a holiday.');
    await sql`INSERT INTO holidays (day, name) VALUES (CAST(${day} AS date), ${name ?? null})`.execute(db);
    return { day, name: name ?? null };
  });
  app.delete('/holidays/:day', async (req, reply) => {
    const { day } = parse(z.object({ day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) }), req.params);
    if (!isHeadOrAdmin(await currentUser(db, req.userId))) throw forbidden('Only department heads can change holidays.');
    await sql`DELETE FROM holidays WHERE day = CAST(${day} AS date)`.execute(db);
    return reply.code(204).send();
  });

  // ---- suggest an improvement: everyone writes; heads and admins see all and set the status ----
  app.get('/suggestions', async (req) => {
    const me = await currentUser(db, req.userId);
    let q = db.selectFrom('suggestions').innerJoin('users', 'users.id', 'suggestions.by_id')
      .select(['suggestions.id', 'suggestions.text', 'suggestions.status', 'suggestions.created_at', 'users.name as byName']);
    if (!isHeadOrAdmin(me)) q = q.where('suggestions.by_id', '=', me.id);
    return { suggestions: await q.orderBy('suggestions.created_at', 'desc').execute(), canReview: isHeadOrAdmin(me) };
  });
  app.post('/suggestions', async (req) => {
    const { text } = parse(z.object({ text: z.string().trim().min(5, 'Say a little more.').max(2000) }), req.body);
    const r = await db.insertInto('suggestions').values({ by_id: req.userId, text }).output(['inserted.id', 'inserted.status']).executeTakeFirstOrThrow();
    return { id: r.id, status: r.status };
  });
  app.put('/suggestions/:id', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const { status } = parse(z.object({ status: z.enum(['New', 'Seen', 'Planned', 'Done', 'Not planned']) }), req.body);
    if (!isHeadOrAdmin(await currentUser(db, req.userId))) throw forbidden('Only department heads can set the status.');
    await db.updateTable('suggestions').set({ status }).where('id', '=', id).execute();
    return { id, status };
  });

  // ---- customers: the /customer picker ----
  app.get('/customers', async () => ({ customers: await db.selectFrom('customers').select(['id', 'name']).where('active', '=', true).orderBy('name').execute() }));
  app.post('/customers', async (req) => {
    const { name } = parse(z.object({ name: z.string().trim().min(2).max(150) }), req.body);
    const found = await db.selectFrom('customers').select(['id', 'name']).where('name', '=', name).executeTakeFirst();
    if (found) return found;
    return db.insertInto('customers').values({ name }).output(['inserted.id', 'inserted.name']).executeTakeFirstOrThrow();
  });

  // ---- a task's history (Ornate's Audit trail) and files ----
  app.get('/tasks/:id/history', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const me = await currentUser(db, req.userId);
    const t = await db.selectFrom('tasks').selectAll().where('id', '=', id).executeTakeFirst();
    if (!t) throw notFound('Task not found.');
    const thread = await db.selectFrom('threads').selectAll().where('id', '=', t.thread_id).executeTakeFirstOrThrow();
    if (!canSeeThread(me, thread) && t.assignee_id !== me.id && !escalatedTo(t).includes(me.id)
      && !(thread.type !== 'self' && !hiddenFromLeads(thread, t, me.id) && t.assignee_id && manages(await loadOrg(db), me.id, t.assignee_id))) throw forbidden();
    const events = await db.selectFrom('task_events').leftJoin('users', 'users.id', 'task_events.actor_id')
      .select(['task_events.type', 'task_events.payload', 'task_events.created_at', 'users.name as actorName'])
      .where('task_id', '=', id).orderBy('task_events.created_at').execute();
    const files = await db.selectFrom('attachments').innerJoin('messages', 'messages.id', 'attachments.message_id')
      .select(['attachments.r2_key as key', 'attachments.mime', 'attachments.size_bytes as sizeBytes', 'messages.created_at as at'])
      .where((eb) => eb.or([eb('messages.id', '=', t.message_id), eb('messages.reply_to_task_id', '=', id)])).execute();
    // Ornate's case page: replies under the task, its sub-tasks and its parent.
    const replies = await db.selectFrom('messages').selectAll().where('reply_to_task_id', '=', id).orderBy('created_at').execute();
    const subs = await db.selectFrom('tasks').innerJoin('departments', 'departments.id', 'tasks.department_id')
      .select(['tasks.id', 'tasks.ticket_no', 'tasks.subject', 'tasks.status', 'tasks.thread_id', 'departments.name as department'])
      .where('tasks.parent_task_id', '=', id).orderBy('tasks.created_at').execute();
    const parent = t.parent_task_id ? await db.selectFrom('tasks').select(['id', 'ticket_no', 'subject', 'status', 'thread_id']).where('id', '=', t.parent_task_id).executeTakeFirst() : null;
    return {
      events: events.map((e) => ({ type: e.type, by: e.actorName ?? 'System', at: new Date(e.created_at).toISOString(), payload: JSON.parse(e.payload as unknown as string) })),
      files,
      replies: await withTasks(db, replies, me.id),
      subTasks: subs.map((s) => ({ id: s.id, ticketNo: s.ticket_no, subject: s.subject, status: s.status, threadId: s.thread_id, department: s.department })),
      parent: parent ? { id: parent.id, ticketNo: parent.ticket_no, subject: parent.subject, status: parent.status, threadId: parent.thread_id } : null,
    };
  });

  // ---- search tasks: ticket number, subject, customer or the message text ----
  app.get('/tasks/search', async (req) => {
    const { q } = parse(z.object({ q: z.string().trim().min(2).max(100) }), req.query);
    const me = await currentUser(db, req.userId);
    const like = `%${q.replace(/[%_[]/g, '[$&]')}%`;
    const rows = await db.selectFrom('tasks').innerJoin('messages', 'messages.id', 'tasks.message_id').innerJoin('threads', 'threads.id', 'tasks.thread_id')
      .selectAll('messages').select(['threads.type as tType', 'threads.user_a_id', 'threads.user_b_id', 'threads.requester_id', 'threads.department_id as tDept',
        'tasks.assignee_id as tAssignee', 'tasks.escalated_to as tEscalatedTo'])
      .where((eb) => eb.or([eb('tasks.ticket_no', 'like', like), eb('tasks.subject', 'like', like), eb('tasks.customer_name', 'like', like), eb('messages.body_text', 'like', like)]))
      .orderBy('messages.created_at', 'desc').top(50).execute();
    // Same rule as opening the task: private notes only their writer; person to person the two, the reassignee, or whoever it's escalated to.
    const visible = rows.filter((r) => r.tType === 'self' ? r.requester_id === me.id
      : r.tType === 'direct' ? r.user_a_id === me.id || r.user_b_id === me.id || r.tAssignee === me.id || escalatedTo({ escalated_to: r.tEscalatedTo } as never).includes(me.id)
      : r.requester_id === me.id || (!!me.department_id && r.tDept === me.department_id)).slice(0, 20);
    return { items: await withTasks(db, visible as never, me.id) };
  });
}
