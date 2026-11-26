// Ornate's core workflow (docs/PARITY.md step 3): who may do what, and what each action changes.
// Every task sent to a phone carries `actions` for that person, so the app shows exactly the allowed buttons.
import { sql } from 'kysely';
import { z } from 'zod';
import type { Env } from '../config/env';
import type { Db } from '../db/client';
import type { EscalationLevel, Priority, Task, TaskEventType, TaskStatus, Thread, User } from '../db/schema';
import { badRequest, conflict, forbidden } from '../lib/errors';
import { Id, parse } from '../lib/validate';
import { otherUserId } from '../modules/access';
import { leadChain, manages, teamsLedBy, type OrgSnapshot } from '../modules/org';
import { acceptDue, halt, shiftOf, start, used } from './clock';
import { WORKING_DAY, workMs } from './time';
import { nextTicketNo } from './tickets';

export const ACTIONS = ['accept', 'decline', 'in_progress', 'ask_reassign', 'keep', 'reassign', 'complete', 'verify', 'close', 'reopen',
  'ask_requester', 'block', 'unblock', 'request_reject', 'request_transfer', 'approve_request', 'refuse_request', 'reject', 'transfer',
  'escalate', 'attend', 'change_priority', 'cancel'] as const;
export type Action = (typeof ACTIONS)[number];

const ACTIVE: TaskStatus[] = ['Accepted', 'InProgress', 'WaitingInfo', 'Blocked'];
export const FINISHED: TaskStatus[] = ['Closed', 'Rejected', 'Transferred', 'Cancelled'];
const PRIORITY_ORDER: Priority[] = ['Low', 'Medium', 'High', 'Critical'];
export const REOPEN_WINDOW_MS = 7 * 86_400_000;
const DAY_MS = 86_400_000;

export interface Ctx {
  db: Db; env: Env; org: OrgSnapshot; holidays: ReadonlySet<string>; now: Date;
  me: Pick<User, 'id' | 'role' | 'department_id' | 'team_id'>;
  task: Task; thread: Thread; senderId: string;
}

const json = <T>(s: string | null | undefined, d: T): T => { try { return s ? (JSON.parse(s) as T) : d; } catch { return d; } };
export const escalatedTo = (t: Task) => json<string[]>(t.escalated_to, []);
export const pendingRequest = (t: Task) => json<{ kind: 'reject' | 'transfer'; by: string; reason: string; departmentId?: string } | null>(t.request, null);

/** Roles the viewer has on this task. */
function roles(c: Ctx) {
  const { me, task: t, thread, org } = c;
  const requester = c.senderId === me.id;
  const assignee = t.assignee_id === me.id;
  const myTeams = teamsLedBy(org, me.id);
  const head = me.role === 'dept_head' && !!t.department_id && me.department_id === t.department_id;
  const lead = head || (!!t.assignee_id && manages(org, me.id, t.assignee_id)) || (!!t.team_id && myTeams.includes(t.team_id))
    || (!t.team_id && !t.assignee_id && me.role === 'team_lead' && me.department_id === t.department_id);
  const recipient = !requester && (thread.type === 'direct'
    ? otherUserId(thread, c.senderId) === me.id
    : me.department_id === t.department_id && (!t.team_id || me.team_id === t.team_id || myTeams.includes(t.team_id)));
  return { requester, assignee, lead: lead && !requester, recipient, staff: me.role === 'staff' };
}

/** The buttons this person gets on this task. */
export function available(c: Ctx): Action[] {
  const t = c.task, r = roles(c), now = c.now.getTime();
  const out = new Set<Action>();
  if (FINISHED.includes(t.status) && t.status !== 'Closed') return [];

  // A staff request waiting on this lead: only the answer to it (Ornate rule: nothing else to misclick).
  if (r.lead && pendingRequest(t)) return ['approve_request', 'refuse_request'];
  if (r.lead && t.reassign_requested_by && ACTIVE.includes(t.status)) return ['reassign', 'keep'];

  if (t.status === 'Open') {
    if (r.recipient) out.add('accept');
    if (r.recipient && t.tagged_user_id === c.me.id) out.add('decline');
    if (r.recipient && r.staff && !pendingRequest(t)) out.add('request_reject').add('request_transfer');
    if (r.lead) out.add('reassign').add('reject').add('transfer').add('change_priority');
    if (r.requester) out.add('cancel').add('change_priority');
  }
  if (ACTIVE.includes(t.status)) {
    if (r.assignee) {
      if (t.status === 'Accepted') out.add('in_progress');
      out.add('complete').add('change_priority');
      if (t.status !== 'WaitingInfo') out.add('ask_requester');
      out.add(t.status === 'Blocked' ? 'unblock' : 'block');
      if (r.staff) {
        const asked = json<Record<string, string>>(t.reassign_asked, {})[c.me.id];
        if (!t.reassign_requested_by && (!asked || now - Date.parse(asked) >= DAY_MS)) out.add('ask_reassign');
        if (!pendingRequest(t)) out.add('request_reject').add('request_transfer');
      } else out.add('reject').add('transfer');
    }
    if (r.lead) out.add('reassign').add('reject').add('transfer').add('change_priority');
  }
  if (r.requester) {
    if (t.status === 'Completed') out.add('verify').add('reopen');
    if (t.status === 'Verified') out.add('close').add('reopen');
    if (t.status === 'Closed' && t.closed_at && now - new Date(t.closed_at).getTime() <= REOPEN_WINDOW_MS) out.add('reopen');
  }
  if (!FINISHED.includes(t.status) && t.status !== 'Completed' && t.status !== 'Verified') {
    if ((r.requester || r.assignee || r.recipient || r.lead) && !t.escalation_level) out.add('escalate');
    if (t.escalation_level && escalatedTo(t).includes(c.me.id)) out.add('attend');
  }
  return ACTIONS.filter((a) => out.has(a));
}

/** Who an escalation goes to; a level nobody holds moves to the next one. */
export function escalationTargets(c: Pick<Ctx, 'org' | 'task' | 'senderId'>, want: EscalationLevel): { level: EscalationLevel; ids: string[] } {
  const { org, task: t } = c;
  const levels: EscalationLevel[] = ['team_lead', 'dept_head', 'management'];
  for (const level of levels.slice(levels.indexOf(want))) {
    let ids: string[] = [];
    if (level === 'team_lead') {
      const team = org.teams.find((x) => x.id === t.team_id);
      const lead = t.assignee_id ? leadChain(org, t.assignee_id).find((id) => org.users.find((u) => u.id === id)?.role === 'team_lead') : team?.lead_id;
      ids = lead ? [lead] : [];
    } else if (level === 'dept_head') {
      const head = org.departments.find((d) => d.id === t.department_id)?.head_user_id;
      ids = head ? [head] : [];
    } else ids = org.users.filter((u) => u.role === 'admin' && u.is_active).map((u) => u.id);
    ids = ids.filter((id) => id !== c.senderId);
    if (ids.length) return { level, ids };
  }
  return { level: want, ids: [] };
}

const Reason = z.string().trim().min(1, 'Add a short reason.').max(2000);
export interface Result { type: TaskEventType; payload: Record<string, unknown>; push?: { to: string[]; text: string }; newTaskId?: string }

/** Run one action. Throws a readable error if it isn't allowed now. */
export async function run(c: Ctx, action: Action, body: unknown): Promise<Result> {
  if (!available(c).includes(action)) throw forbidden('You can\'t do that on this task now.');
  const { db, task: t, now, org, holidays } = c;
  const ownerShift = await userShift(db, t.assignee_id ?? c.me.id);
  const upd = (fields: Record<string, unknown>, onlyIf: TaskStatus[] = [t.status]) =>
    db.updateTable('tasks').set({ ...fields, updated_at: now }).where('id', '=', t.id).where('status', 'in', onlyIf).executeTakeFirst()
      .then((r) => { if (!Number(r.numUpdatedRows)) throw conflict('CHANGED', 'This task just changed. Refresh and try again.'); });
  const leads = () => (t.assignee_id ? leadChain(org, t.assignee_id) : escalationTargets(c, 'team_lead').ids).slice(0, 1);

  switch (action) {
    case 'accept': {
      const won = await sql<{ id: string }>`UPDATE tasks SET status = 'Accepted', assignee_id = ${c.me.id}, accepted_at = ${now},
        clock_state = 'running', clock_running_since = ${now}, updated_at = ${now} OUTPUT inserted.id WHERE id = ${t.id} AND status = 'Open'`.execute(db);
      if (!won.rows.length) {
        const by = await db.selectFrom('tasks').innerJoin('users', 'users.id', 'tasks.assignee_id').select(['users.id', 'users.name']).where('tasks.id', '=', t.id).executeTakeFirst();
        throw conflict('ALREADY_ACCEPTED', by ? `${by.name} already accepted this task.` : 'This task is no longer open.', { acceptedBy: by ?? null });
      }
      const s = start(t, now, await userShift(db, c.me.id), holidays);
      await db.updateTable('tasks').set({ due_at: s.due_at }).where('id', '=', t.id).execute();
      return { type: 'accepted', payload: { by: c.me.id }, push: { to: [c.senderId], text: 'accepted' } };
    }
    case 'decline': {
      const { reason } = parse(z.object({ reason: Reason }), body);
      const declined = [...json<string[]>(t.declined_by, []), c.me.id];
      await upd({ tagged_user_id: null, declined_by: JSON.stringify(declined) });
      return { type: 'declined', payload: { by: c.me.id, reason }, push: { to: [c.senderId, ...escalationTargets(c, 'team_lead').ids], text: `declined: ${reason}` } };
    }
    case 'in_progress':
      await upd({ status: 'InProgress' });
      return { type: 'status_changed', payload: { from: t.status, to: 'InProgress' }, push: { to: [c.senderId], text: 'in progress' } };
    case 'ask_reassign': {
      const { reason } = parse(z.object({ reason: Reason }), body);
      const asked = { ...json<Record<string, string>>(t.reassign_asked, {}), [c.me.id]: now.toISOString() };
      await upd({ reassign_requested_by: c.me.id, reassign_asked: JSON.stringify(asked) });
      return { type: 'reassign_asked', payload: { by: c.me.id, reason }, push: { to: leads(), text: `asked to be reassigned: ${reason}` } };
    }
    case 'keep': {
      const asker = t.reassign_requested_by;
      await upd({ reassign_requested_by: null });
      return { type: 'reassign_refused', payload: { by: c.me.id }, push: { to: asker ? [asker] : [], text: 'stays with you' } };
    }
    case 'complete': {
      const { remarks } = parse(z.object({ remarks: Reason }), body);
      await upd({ status: 'Completed', completed_at: now, ...halt(t, now, 'stopped', ownerShift, holidays), due_at: dueForVerify(now) });
      return { type: 'completed', payload: { remarks, usedMs: used(t, now.getTime(), ownerShift, holidays) }, push: { to: [c.senderId], text: 'completed: please verify' } };
    }
    case 'verify':
      await upd({ status: 'Verified', verified_at: now });
      return { type: 'verified', payload: { by: c.me.id }, push: { to: t.assignee_id ? [t.assignee_id] : [], text: 'verified' } };
    case 'close': {
      const { resolution, customerInformed } = parse(z.object({ resolution: Reason, customerInformed: z.enum(['yes', 'no', 'n/a']) }), body);
      await upd({ status: 'Closed', closed_at: now, resolution, customer_informed: customerInformed });
      return { type: 'closed', payload: { resolution, customerInformed }, push: { to: t.assignee_id ? [t.assignee_id] : [], text: 'closed' } };
    }
    case 'reopen': {
      const { reason } = parse(z.object({ reason: Reason }), body);
      const s = start({ ...t, clock_used_ms: t.clock_used_ms }, now, ownerShift, holidays);
      await upd({ status: 'InProgress', closed_at: null, completed_at: null, verified_at: null, resolution: null, customer_informed: null, ...s }, ['Completed', 'Verified', 'Closed']);
      return { type: 'reopened', payload: { reason }, push: { to: [...(t.assignee_id ? [t.assignee_id] : []), ...leads()], text: `reopened: ${reason}` } };
    }
    case 'ask_requester': {
      const { question } = parse(z.object({ question: Reason }), body);
      await upd({ status: 'WaitingInfo', ...halt(t, now, 'paused', ownerShift, holidays) });
      return { type: 'question', payload: { question }, push: { to: [c.senderId], text: `question: ${question}` } };
    }
    case 'block': {
      const { reason } = parse(z.object({ reason: Reason }), body);
      await upd({ status: 'Blocked', ...halt(t, now, 'paused', ownerShift, holidays) });
      return { type: 'blocked', payload: { reason }, push: { to: [c.senderId, ...leads()], text: `blocked: ${reason}` } };
    }
    case 'unblock':
      await upd({ status: 'InProgress', ...start(t, now, ownerShift, holidays) });
      return { type: 'unblocked', payload: {}, push: { to: [c.senderId], text: 'work resumed' } };
    case 'request_reject':
    case 'request_transfer': {
      const kind = action === 'request_reject' ? 'reject' : 'transfer';
      const b = parse(z.object({ reason: Reason, departmentId: Id.optional() }), body);
      if (kind === 'transfer' && (!b.departmentId || b.departmentId === t.department_id)) throw badRequest('Choose a different department.');
      await upd({ request: JSON.stringify({ kind, by: c.me.id, reason: b.reason, departmentId: b.departmentId }) });
      return { type: 'request', payload: { kind, reason: b.reason, departmentId: b.departmentId }, push: { to: escalationTargets(c, 'team_lead').ids, text: `asks to ${kind}: ${b.reason}` } };
    }
    case 'refuse_request': {
      const req = pendingRequest(t)!;
      await upd({ request: null });
      return { type: 'request_refused', payload: { kind: req.kind }, push: { to: [req.by], text: `request to ${req.kind} refused` } };
    }
    case 'approve_request': {
      const req = pendingRequest(t)!;
      await upd({ request: null });
      return run({ ...c, task: { ...t, request: null }, me: { ...c.me, role: 'dept_head' } }, req.kind, { reason: req.reason, departmentId: req.departmentId });
    }
    case 'reject': {
      const { reason } = parse(z.object({ reason: Reason }), body);
      await upd({ status: 'Rejected', closed_at: now, ...halt(t, now, 'stopped', ownerShift, holidays) });
      return { type: 'rejected', payload: { reason }, push: { to: [c.senderId], text: `rejected: ${reason}` } };
    }
    case 'transfer': return transfer(c, body, ownerShift);
    case 'escalate': {
      const { level, reason } = parse(z.object({ level: z.enum(['team_lead', 'dept_head', 'management']).default('team_lead'), reason: Reason }), body);
      const target = escalationTargets(c, level);
      if (!target.ids.length) throw badRequest('Nobody holds that level yet.');
      await upd({ escalation_level: target.level, escalated_to: JSON.stringify(target.ids) });
      return { type: 'escalated', payload: { level: target.level, to: target.ids, reason }, push: { to: target.ids, text: `escalated to you: ${reason}` } };
    }
    case 'attend':
      await upd({ escalation_level: null, escalated_to: '[]' });
      return { type: 'attended', payload: { by: c.me.id }, push: { to: [c.senderId, ...(t.assignee_id ? [t.assignee_id] : [])], text: 'escalation attended' } };
    case 'change_priority': {
      const { priority, reason } = parse(z.object({ priority: z.enum(['Critical', 'High', 'Medium', 'Low']), reason: Reason }), body);
      if (priority === t.priority) throw badRequest('Choose a different priority.');
      const lowering = PRIORITY_ORDER.indexOf(priority) < PRIORITY_ORDER.indexOf(t.priority);
      if (lowering && c.me.role === 'staff') throw forbidden('Only a team lead or department head can lower the priority.');
      const p = { ...t, priority };
      const due = t.status === 'Open' ? { due_at: acceptDue(new Date(t.queued_at ?? t.created_at), priority, holidays) }
        : t.clock_state === 'running' ? { due_at: start({ ...p, clock_used_ms: used(t, now.getTime(), ownerShift, holidays) }, now, ownerShift, holidays).due_at } : {};
      await upd({ priority, warned: '[]', ...due });
      return { type: 'priority_changed', payload: { from: t.priority, to: priority, reason }, push: { to: [c.senderId, ...(t.assignee_id ? [t.assignee_id] : [])].filter((x) => x !== c.me.id), text: `priority ${priority}` } };
    }
    case 'cancel':
      await upd({ status: 'Cancelled', closed_at: now, clock_state: 'stopped' }, ['Open']);
      return { type: 'cancelled', payload: {}, push: { to: [t.assignee_id ?? t.tagged_user_id].filter((x): x is string => !!x), text: 'cancelled' } };
    case 'reassign':
      throw badRequest('Use the reassign endpoint.');
  }
}

/** Ornate: a completed task verifies itself after 2 working days; due date for the requester's check. */
const dueForVerify = (now: Date) => new Date(now.getTime() + 2 * DAY_MS);

async function userShift(db: Db, id: string) {
  return shiftOf((await db.selectFrom('users').select('shift').where('id', '=', id).executeTakeFirst())?.shift);
}

/** Transfer: the task ends here as Transferred, and continues as a new task in the requester's chat with the other department.
 *  The clock restarts there; the time used here is kept on the new task. */
async function transfer(c: Ctx, body: unknown, ownerShift: [number, number]): Promise<Result> {
  const { db, task: t, now, holidays } = c;
  const { reason, departmentId } = parse(z.object({ reason: Reason, departmentId: Id }), body);
  if (departmentId === t.department_id) throw badRequest('Choose a different department.');
  const dept = await db.selectFrom('departments').select(['id', 'name']).where('id', '=', departmentId).executeTakeFirst();
  if (!dept) throw badRequest('Department not found.');
  const usedMs = used(t, now.getTime(), ownerShift, holidays) + Number(t.used_before_transfer ?? 0);
  const orig = await db.selectFrom('messages').selectAll().where('id', '=', t.message_id).executeTakeFirstOrThrow();
  let newTaskId = '';
  await db.transaction().execute(async (tx) => {
    const r = await tx.updateTable('tasks').set({ status: 'Transferred', closed_at: now, clock_state: 'stopped', clock_running_since: null, updated_at: now })
      .where('id', '=', t.id).where('status', 'not in', FINISHED).executeTakeFirst();
    if (!Number(r.numUpdatedRows)) throw conflict('CHANGED', 'This task just changed. Refresh and try again.');
    let th = await tx.selectFrom('threads').selectAll().where('type', '=', 'department').where('requester_id', '=', c.senderId)
      .where('department_id', '=', dept.id).where('team_id', 'is', null).executeTakeFirst();
    if (!th) {
      const { id } = await tx.insertInto('threads').values({ type: 'department', requester_id: c.senderId, department_id: dept.id, team_id: null }).output('inserted.id').executeTakeFirstOrThrow();
      th = await tx.selectFrom('threads').selectAll().where('id', '=', id).executeTakeFirstOrThrow();
    }
    const m = await tx.insertInto('messages').values({
      thread_id: th.id, sender_id: c.senderId, client_msg_id: crypto.randomUUID(), kind: 'text',
      body_text: orig.body_text ?? orig.transcript ?? '(voice note)', audio_key: null, audio_duration_s: null, transcript: null, transcript_lang: null,
    }).output('inserted.id').executeTakeFirstOrThrow();
    const nt = await tx.insertInto('tasks').values({
      message_id: m.id, thread_id: th.id, priority: t.priority, department_id: dept.id, team_id: null, tagged_user_id: null, assignee_id: null,
      overrides: t.overrides as unknown as string, subject: t.subject, module: 'Other', customer_name: t.customer_name, customer_phone: t.customer_phone,
      customer_location: t.customer_location, license_no: t.license_no, details: t.details, ai_status: t.ai_status === 'pending' ? 'pending' : 'done',
      ai_error: null, ai_provider: t.ai_provider, prompt_version: t.prompt_version, closed_at: null,
      due_at: acceptDue(now, t.priority, holidays), queued_at: now, used_before_transfer: usedMs, transferred_from_id: t.id, ticket_no: await nextTicketNo(tx, now),
    }).output('inserted.id').executeTakeFirstOrThrow();
    newTaskId = nt.id;
    await tx.insertInto('task_events').values({ task_id: nt.id, actor_id: c.me.id, type: 'created', payload: JSON.stringify({ transferredFrom: t.id, reason }) }).execute();
    await tx.updateTable('threads').set({ last_message_at: now }).where('id', '=', th.id).execute();
  });
  return { type: 'transferred', payload: { to: dept.id, toName: dept.name, reason, newTaskId, usedMs }, push: { to: [c.senderId], text: `moved to ${dept.name}: ${reason}` }, newTaskId };
}

/** For Ornate's auto-verify (2 working days) and auto-close (3 more). */
export const workingDaysSince = (from: Date, now: Date, holidays: ReadonlySet<string>) => workMs(from.getTime(), now.getTime(), [9, 18], holidays) / WORKING_DAY;
