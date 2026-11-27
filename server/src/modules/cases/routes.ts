// Ornate Samanvay's lists (docs/ORNATE_UI.md): My Tasks / Queue / All Cases, the chip row, Filters and the department
// picker; one chat per person (party); a person's timeline; and the bell's notification list.
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Message, Task, Thread, User } from '../../db/schema';
import { notFound } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { FINISHED } from '../../workflow/engine';
import { currentUser, otherUserId } from '../access';
import { withTasks } from '../messages/service';
import { loadOrg, manages, teamsLedBy, type OrgSnapshot } from '../org';

const ACTIVE = ['Accepted', 'InProgress', 'WaitingInfo', 'WaitingDept', 'Blocked'];
const OPEN_ROW = (s: string) => !['Closed', 'Rejected', 'Cancelled', 'Transferred'].includes(s);
const DONE_CHIP = ['Verified', 'Closed', 'Rejected', 'Cancelled'];
export const CHIPS = ['All', 'Active', 'To Verify', 'Sent by me', 'Overdue/Escalated', 'Verified / Closed'] as const;
const TABS = ['my', 'queue', 'all'] as const;

interface Row { t: Task; th: Thread; m: Message; senderId: string }

/** Everything the rules need about one task, for one viewer. */
function rules(org: OrgSnapshot, me: User, now: number) {
  const led = teamsLedBy(org, me.id);
  const user = (id: string | null) => org.users.find((u) => u.id === id);
  const head = (t: Task) => me.role === 'dept_head' && !!t.department_id && t.department_id === me.department_id;
  const note = (r: Row) => r.th.type === 'self';
  const recipient = (r: Row) => r.senderId !== me.id && (r.th.type === 'direct'
    ? otherUserId(r.th, r.senderId) === me.id
    : r.th.type === 'department' && me.department_id === r.t.department_id && (!r.t.team_id || me.team_id === r.t.team_id || led.includes(r.t.team_id)));
  const canAccept = (r: Row) => r.t.status === 'Open' && recipient(r);
  const leadFor = (r: Row) => head(r.t) || (!!r.t.assignee_id && manages(org, me.id, r.t.assignee_id)) || (!!r.t.team_id && led.includes(r.t.team_id));
  const overdue = (r: Row) => !note(r) && (r.t.status === 'Open' || ACTIVE.includes(r.t.status)) && new Date(r.t.due_at).getTime() < now;
  const escalatedToMe = (t: Task) => { try { return (JSON.parse(t.escalated_to) as string[]).includes(me.id); } catch { return false; } };

  const canView = (r: Row) => {
    if (note(r)) return r.senderId === me.id;
    if (r.senderId === me.id || r.t.assignee_id === me.id) return true;
    if (r.th.type === 'direct' && otherUserId(r.th, r.senderId) === me.id) return true;
    if (head(r.t) || leadFor(r)) return true;
    if (led.includes(user(r.senderId)?.team_id ?? '')) return true; // raised by a team they lead
    return canAccept(r);
  };
  const inMyTasks = (r: Row) => {
    const s = r.t.status;
    if (note(r)) return r.senderId === me.id && s !== 'Closed';
    if (r.t.assignee_id === me.id && (ACTIVE.includes(s) || s === 'Completed')) return true;
    if (s === 'Open' && canAccept(r) && (r.t.tagged_user_id === me.id || r.th.type === 'direct')) return true;
    if (leadFor(r) && !FINISHED.includes(s) && (r.t.request || r.t.reassign_requested_by || escalatedToMe(r.t))) return true;
    return r.senderId === me.id && (s === 'Open' || ACTIVE.includes(s) || s === 'Completed' || s === 'Verified');
  };
  const inQueue = (r: Row) => !note(r) && r.t.status === 'Open' && (canAccept(r) || head(r.t) || (!!r.t.team_id && led.includes(r.t.team_id))) && !inMyTasks(r);
  const myFinished = (r: Row) => DONE_CHIP.includes(r.t.status) && (r.t.assignee_id === me.id || r.senderId === me.id) && canView(r);

  /** Who is on the other side, like a WhatsApp contact: the requester, or for my own tasks whoever holds them. */
  const party = (r: Row) => {
    if (note(r)) return { key: 'self', name: 'Private notes', sub: 'Only you' };
    const deptName = (id: string | null | undefined) => org.departments.find((d) => d.id === id)?.name ?? '';
    if (r.senderId !== me.id) { const u = user(r.senderId); return { key: `u:${r.senderId}`, name: u?.name ?? 'Unknown', sub: deptName(u?.department_id) }; }
    const who = r.t.assignee_id ?? r.t.tagged_user_id ?? (r.th.type === 'direct' ? otherUserId(r.th, me.id) : null);
    if (who) { const u = user(who); return { key: `u:${who}`, name: u?.name ?? 'Unknown', sub: deptName(u?.department_id ?? r.t.department_id) }; }
    if (r.t.team_id) { const tm = org.teams.find((x) => x.id === r.t.team_id); return { key: `t:${r.t.team_id}`, name: `${tm?.name ?? 'Team'} team`, sub: deptName(r.t.department_id) }; }
    return { key: `d:${r.t.department_id}`, name: `${deptName(r.t.department_id)} Team Leads`, sub: deptName(r.t.department_id) };
  };
  return { canView, inMyTasks, inQueue, myFinished, overdue, party, leadFor, note };
}

export async function caseRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);
  const { db } = app;

  // ponytail: reads every task and filters in JS (fine for Phase 1 volumes); move the rules into SQL if lists get slow.
  async function rows(): Promise<Row[]> {
    const [tasks, threads] = await Promise.all([db.selectFrom('tasks').selectAll().execute(), db.selectFrom('threads').selectAll().execute()]);
    if (!tasks.length) return [];
    const msgs = await db.selectFrom('messages').selectAll().where('id', 'in', tasks.map((t) => t.message_id)).execute();
    const th = new Map(threads.map((x) => [x.id, x])), mm = new Map(msgs.map((x) => [x.id, x]));
    return tasks.map((t) => ({ t, th: th.get(t.thread_id)!, m: mm.get(t.message_id)!, senderId: mm.get(t.message_id)!.sender_id }));
  }
  async function lastMessages(taskIds: string[]) {
    const out = new Map<string, Message>();
    if (!taskIds.length) return out;
    const replies = await db.selectFrom('messages').selectAll().where('reply_to_task_id', 'in', taskIds).orderBy('created_at').execute();
    for (const m of replies) out.set(m.reply_to_task_id!, m);
    return out;
  }
  async function present(me: User, list: Row[], r: ReturnType<typeof rules>) {
    const items = await withTasks(db, list.map((x) => x.m), me.id);
    const last = await lastMessages(list.map((x) => x.t.id));
    const names = new Map((await db.selectFrom('users').select(['id', 'name']).execute()).map((u) => [u.id, u.name]));
    return list.map((x, i) => {
      const lm = last.get(x.t.id) ?? x.m;
      const by = lm.sender_id === me.id ? 'You' : (names.get(lm.sender_id) ?? '').split(' ')[0];
      const text = lm.body_text ?? lm.transcript ?? (lm.kind === 'voice' ? 'Voice message' : 'File');
      return { ...items[i]!, party: r.party(x), overdue: r.overdue(x), requesterId: x.senderId,
        last: { text: `${by}: ${text}`, at: new Date(lm.created_at).toISOString() } };
    });
  }

  const Filters = z.object({
    tab: z.enum(TABS).default('my'),
    chip: z.enum(CHIPS).default('All'),
    dept: Id.optional(),
    q: z.string().max(100).default(''),
    status: z.string().max(16).optional(),
    priority: z.enum(['Critical', 'High', 'Medium', 'Low']).optional(),
    requester: Id.optional(),
    owner: Id.optional(),
    type: z.enum(['Internal', 'Self']).optional(),
    from: z.string().date().optional(), to: z.string().date().optional(),
    closedFrom: z.string().date().optional(), closedTo: z.string().date().optional(),
    openOnly: z.coerce.boolean().default(false),
  });

  /** One list: the tab, then the chip, Filters, department and search (Ornate's CaseList). Newest activity first. */
  app.get('/cases', async (req) => {
    const f = parse(Filters, req.query);
    const me = await currentUser(db, req.userId);
    const org = await loadOrg(db);
    const now = Date.now();
    const r = rules(org, me, now);
    const all = (await rows()).filter(r.canView);
    const finished = f.chip === 'Verified / Closed';
    const source = finished ? (f.tab === 'my' ? all.filter(r.myFinished) : all) : all.filter(f.tab === 'my' ? r.inMyTasks : f.tab === 'queue' ? r.inQueue : () => true);
    const day = (d: string, end = false) => new Date(`${d}T${end ? '23:59:59' : '00:00:00'}+05:30`).getTime();
    const names = new Map(org.users.map((u) => [u.id, u.name]));
    const words = f.q.toLowerCase().split(/\s+/).filter(Boolean);
    const hay = (x: Row) => [x.t.ticket_no, x.t.subject, x.t.details, x.t.customer_name, x.m.body_text, x.m.transcript, names.get(x.senderId), x.t.assignee_id && names.get(x.t.assignee_id)]
      .filter(Boolean).join(' ').toLowerCase();
    const list = source.filter((x) => {
      const t = x.t, s = t.status;
      const chipOk = f.chip === 'All' || finished ? (!finished || DONE_CHIP.includes(s))
        : f.chip === 'Active' ? s === 'Open' || ACTIVE.includes(s)
        : f.chip === 'To Verify' ? s === 'Completed' && x.senderId === me.id
        : f.chip === 'Sent by me' ? x.senderId === me.id
        : r.overdue(x) || !!t.escalation_level;
      if (!chipOk) return false;
      if (f.dept && t.department_id !== f.dept && org.users.find((u) => u.id === x.senderId)?.department_id !== f.dept) return false;
      if (f.status && s !== f.status) return false;
      if (f.priority && t.priority !== f.priority) return false;
      if (f.requester && x.senderId !== f.requester) return false;
      if (f.owner && t.assignee_id !== f.owner) return false;
      if (f.type && (f.type === 'Self') !== r.note(x)) return false;
      const created = new Date(t.created_at).getTime();
      if (f.from && created < day(f.from)) return false;
      if (f.to && created > day(f.to, true)) return false;
      if ((f.closedFrom || f.closedTo) && !t.closed_at) return false;
      if (f.closedFrom && new Date(t.closed_at!).getTime() < day(f.closedFrom)) return false;
      if (f.closedTo && new Date(t.closed_at!).getTime() > day(f.closedTo, true)) return false;
      if (f.openOnly && !OPEN_ROW(s)) return false;
      return words.every((w) => hay(x).includes(w));
    });
    const items = (await present(me, list, r)).sort((a, b) => b.last.at.localeCompare(a.last.at));
    // A lead's Queue opens with their department at a glance (Ornate).
    const lead = me.role !== 'staff' && f.tab === 'queue' && me.department_id;
    const deptRows = lead ? (await rows()).filter((x) => x.t.department_id === me.department_id && !r.note(x)) : [];
    return {
      items,
      // Grouped into one chat per person: open tasks only, and not while searching or looking at finished work (Ornate).
      grouped: !finished && !words.length,
      stats: lead ? {
        waiting: deptRows.filter((x) => x.t.status === 'Open').length,
        inProgress: deptRows.filter((x) => ACTIVE.includes(x.t.status)).length,
        overdue: deptRows.filter((x) => r.overdue(x)).length,
      } : null,
    };
  });

  /** Badges on the bottom bar: how many tasks each tab holds. */
  app.get('/cases/counts', async (req) => {
    const me = await currentUser(db, req.userId);
    const r = rules(await loadOrg(db), me, Date.now());
    const all = (await rows()).filter(r.canView);
    return { my: all.filter(r.inMyTasks).length, queue: all.filter(r.inQueue).length, all: all.length };
  });

  /** One person's chat: every task between you and them (open and finished) with its replies, oldest first. */
  app.get('/timeline', async (req) => {
    const { party } = parse(z.object({ party: z.string().regex(/^(self|[udt]:[0-9A-Fa-f-]{36})$/, 'Unknown chat.') }), req.query);
    const me = await currentUser(db, req.userId);
    const r = rules(await loadOrg(db), me, Date.now());
    const mine = (await rows()).filter((x) => r.canView(x) && r.party(x).key.toUpperCase() === party.toUpperCase());
    const replies = mine.length ? await db.selectFrom('messages').selectAll().where('reply_to_task_id', 'in', mine.map((x) => x.t.id)).execute() : [];
    const msgs = [...mine.map((x) => x.m), ...replies].sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());
    const first = mine[0];
    return { party: first ? r.party(first) : null, items: await withTasks(db, msgs, me.id) };
  });

  // ---- the bell ----
  app.get('/notifications', async (req) => {
    const me = await currentUser(db, req.userId);
    const list = await db.selectFrom('notifications').innerJoin('tasks', 'tasks.id', 'notifications.task_id')
      .select(['notifications.id', 'notifications.task_id', 'notifications.text', 'notifications.read_at', 'notifications.created_at', 'tasks.ticket_no', 'tasks.subject', 'tasks.thread_id'])
      .where('notifications.user_id', '=', me.id).orderBy('notifications.created_at', 'desc').top(100).execute();
    return {
      unread: list.filter((n) => !n.read_at).length,
      items: list.map((n) => ({ id: n.id, taskId: n.task_id, threadId: n.thread_id, ticketNo: n.ticket_no, subject: n.subject, text: n.text,
        read: !!n.read_at, at: new Date(n.created_at).toISOString() })),
    };
  });
  app.post('/notifications/read-all', async (req) => {
    await db.updateTable('notifications').set({ read_at: new Date() }).where('user_id', '=', req.userId).where('read_at', 'is', null).execute();
    return { ok: true };
  });
  app.post('/notifications/:id/read', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const r = await db.updateTable('notifications').set({ read_at: new Date() }).where('id', '=', id).where('user_id', '=', req.userId).executeTakeFirst();
    if (!Number(r.numUpdatedRows)) throw notFound('Notification not found.');
    return { ok: true };
  });
}
