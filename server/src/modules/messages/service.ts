// Flow A/B (spec §11): one transaction saves message + task + "created" event + thread time; events and AI jobs only after commit.
import { z } from 'zod';
import type { Env } from '../../config/env';
import type { Db } from '../../db/client';
import type { Message, Priority, Task, Thread, User } from '../../db/schema';
import { badRequest } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { KEY_PATTERN, type StorageProvider } from '../../storage/StorageProvider';
import { type AttachmentRow, messageDto, taskDto } from '../dto';
import { loadOrg } from '../org';
import { NEVER, acceptDue, halt, loadHolidays, shiftOf, start } from '../../workflow/clock';
import { nextTicketNo } from '../../workflow/tickets';
import { available, FINISHED } from '../../workflow/engine';
import { forbidden } from '../../lib/errors';

const Priority = z.enum(['Critical', 'High', 'Medium', 'Low']);
export const Overrides = z.object({
  priority: Priority.optional(),
  customer: z.string().trim().min(1).max(150).optional(),
  license: z.string().trim().min(1).max(60).optional(),
  module: z.string().trim().min(1).max(80).optional(),
}).strict();

export const NewMessage = z.object({
  clientMsgId: Id,
  kind: z.enum(['text', 'voice', 'attachment']),
  bodyText: z.string().trim().max(4000, 'Messages can be up to 4,000 characters.').optional(),
  audioKey: z.string().regex(KEY_PATTERN).optional(),
  audioDurationS: z.number().int().min(1).max(180, 'Voice notes can be up to 3 minutes.').optional(),
  attachmentKeys: z.array(z.string().regex(KEY_PATTERN)).max(10).default([]),
  overrides: Overrides.default({}),
  taggedUserId: Id.optional(),
  /** An answer or comment on an existing task in this chat: saved as a message, no new task. */
  replyToTaskId: Id.optional(),
  /** `/subtask`: this message becomes a sub-task of that task, sent to this chat's department (Ornate's Hand off). */
  parentTaskId: Id.optional(),
}).superRefine((m, ctx) => {
  if (m.kind === 'text' && !m.bodyText) ctx.addIssue({ code: 'custom', path: ['bodyText'], message: 'Type a message.' });
  if (m.kind === 'voice' && (!m.audioKey || !m.audioDurationS)) ctx.addIssue({ code: 'custom', path: ['audioKey'], message: 'Voice note missing.' });
  if (m.kind === 'attachment' && !m.attachmentKeys.length) ctx.addIssue({ code: 'custom', path: ['attachmentKeys'], message: 'Attach a file.' });
});
export type NewMessage = z.infer<typeof NewMessage>;

export const slaHours = (env: Env, p: Priority) => ({ Critical: env.SLA_HOURS_CRITICAL, High: env.SLA_HOURS_HIGH, Medium: env.SLA_HOURS_MEDIUM, Low: env.SLA_HOURS_LOW })[p];
export const dueAt = (env: Env, p: Priority, from = new Date()) => new Date(from.getTime() + slaHours(env, p) * 3600_000);

const isDuplicate = (e: unknown) => [2601, 2627].includes((e as { number?: number }).number ?? 0);
/** Uploads for a thread live under its department id, or "direct". */
const scopeOf = (t: Thread) => (t.type === 'department' ? t.department_id!.toLowerCase() : 'direct');

export async function createMessage(db: Db, env: Env, storage: StorageProvider, me: User, thread: Thread, raw: unknown) {
  const body = parse(NewMessage, raw);

  const existing = await findExisting(db, me.id, body.clientMsgId);
  if (existing) return { created: false, ...existing };

  // Tagging is for department threads: the person must be in that department.
  if (body.taggedUserId) {
    if (thread.type !== 'department') throw badRequest('Tagging is only for department chats.');
    const member = await db.selectFrom('users').select('id').where('id', '=', body.taggedUserId).where('department_id', '=', thread.department_id).where('is_active', '=', true).executeTakeFirst();
    if (!member) throw badRequest('That person is not in this department.');
  }
  // Files must already be uploaded, under this thread's folder.
  const scope = scopeOf(thread);
  const keys = [...(body.audioKey ? [body.audioKey] : []), ...body.attachmentKeys];
  const heads = new Map<string, { sizeBytes: number; mime: string }>();
  for (const k of keys) {
    if (!k.startsWith(`${scope}/`)) throw badRequest('That file belongs to another chat.');
    const h = await storage.head(k);
    if (!h) throw badRequest('Upload the file again.');
    heads.set(k, h);
  }

  if (body.replyToTaskId) return reply(db, me, thread, body);
  const parent = body.parentTaskId ? await subtaskParent(db, me, thread, body.parentTaskId) : null;
  const note = thread.type === 'self';

  const priority: Priority = body.overrides.priority ?? parent?.priority ?? env.DEFAULT_PRIORITY;
  const holidays = await loadHolidays(db);
  const now = new Date();
  try {
    const out = await db.transaction().execute(async (tx) => {
      const message = await tx.insertInto('messages').values({
        thread_id: thread.id, sender_id: me.id, client_msg_id: body.clientMsgId, kind: body.kind,
        body_text: body.bodyText || null, audio_key: body.audioKey ?? null, audio_duration_s: body.audioDurationS ?? null,
        transcript: null, transcript_lang: null,
      }).output('inserted.id').executeTakeFirstOrThrow();
      for (const k of body.attachmentKeys) {
        const h = heads.get(k)!;
        await tx.insertInto('attachments').values({ message_id: message.id, r2_key: k, mime: h.mime, size_bytes: h.sizeBytes, width: null, height: null }).execute();
      }
      const task = await tx.insertInto('tasks').values({
        message_id: message.id, thread_id: thread.id, priority,
        // A private note is yours from the start: in progress, no clock, never routed (Ornate).
        ...(note ? { status: 'InProgress' as const, assignee_id: me.id, accepted_at: now, queued_at: null, due_at: NEVER }
          : { queued_at: now, due_at: acceptDue(now, priority, holidays), assignee_id: null }),
        ticket_no: parent ? await subtaskNo(tx, parent) : await nextTicketNo(tx, now), parent_task_id: parent?.id ?? null,
        department_id: thread.department_id, team_id: thread.team_id, tagged_user_id: body.taggedUserId ?? null,
        overrides: JSON.stringify(body.overrides),
        subject: null, module: null, customer_name: null, customer_phone: null, customer_location: null, license_no: null,
        details: null, ai_error: null, ai_provider: null, prompt_version: null, closed_at: null,
      }).output('inserted.id').executeTakeFirstOrThrow();
      await tx.insertInto('task_events').values({ task_id: task.id, actor_id: me.id, type: 'created', payload: JSON.stringify({ kind: body.kind, ...(parent ? { parentTaskId: parent.id } : {}) }) }).execute();
      if (parent) {
        // The parent waits for the other department; its clock pauses (Ornate: Waiting for Another Dept).
        const shift = shiftOf((await tx.selectFrom('users').select('shift').where('id', '=', me.id).executeTakeFirst())?.shift);
        await tx.updateTable('tasks').set({ status: 'WaitingDept', ...halt(parent, now, 'paused', shift, holidays), updated_at: now }).where('id', '=', parent.id).execute();
        await tx.insertInto('task_events').values({ task_id: parent.id, actor_id: me.id, type: 'handed_off', payload: JSON.stringify({ subTaskId: task.id, departmentId: thread.department_id }) }).execute();
      }
      await tx.updateTable('threads').set({ last_message_at: new Date(), updated_at: new Date() }).where('id', '=', thread.id).execute();
      return message.id;
    });
    return { created: true, parentId: parent?.id ?? null, ...(await loadMessage(db, out)) };
  } catch (e) {
    // The same message sent twice at the same moment: the second one gets the first one's result.
    if (isDuplicate(e)) { const again = await findExisting(db, me.id, body.clientMsgId); if (again) return { created: false, ...again }; }
    throw e;
  }
}

async function findExisting(db: Db, senderId: string, clientMsgId: string) {
  const m = await db.selectFrom('messages').select('id').where('sender_id', '=', senderId).where('client_msg_id', '=', clientMsgId).executeTakeFirst();
  return m ? loadMessage(db, m.id) : null;
}

export async function loadMessage(db: Db, id: string) {
  const [m] = await withTasks(db, await db.selectFrom('messages').selectAll().where('id', '=', id).execute());
  return m!;
}

/** Messages with their attachments and task (and the task's latest check warnings). With a viewer, each task
 *  also carries the actions that person may take. */
export async function withTasks(db: Db, messages: Message[], viewerId?: string) {
  if (!messages.length) return [];
  const ids = messages.map((m) => m.id);
  const [atts, tasks] = await Promise.all([
    db.selectFrom('attachments').selectAll().where('message_id', 'in', ids).execute(),
    db.selectFrom('tasks').selectAll().where('message_id', 'in', ids).execute(),
  ]);
  const warnings = await warningsFor(db, tasks);
  let actionsOf = (_t: Task): string[] => [];
  if (viewerId && tasks.length) {
    const [org, holidays, me, threads] = await Promise.all([loadOrg(db), loadHolidays(db),
      db.selectFrom('users').select(['id', 'role', 'department_id', 'team_id']).where('id', '=', viewerId).executeTakeFirst(),
      db.selectFrom('threads').selectAll().where('id', 'in', [...new Set(tasks.map((t) => t.thread_id))]).execute()]);
    const now = new Date();
    if (me) actionsOf = (t) => available({ db, env: undefined as never, org, holidays, now, me, task: t,
      thread: threads.find((x) => x.id === t.thread_id)!, senderId: messages.find((m) => m.id === t.message_id)!.sender_id });
  }
  return messages.map((m) => {
    const task = tasks.find((t) => t.message_id === m.id);
    return {
      message: messageDto(m, atts.filter((a) => a.message_id === m.id) as AttachmentRow[]),
      task: task ? taskDto(task, warnings.get(task.id) ?? [], actionsOf(task)) : null,
    };
  });
}

/** Check hints saved with the latest "structured" event of each task. */
export async function warningsFor(db: Db, tasks: Pick<Task, 'id'>[]) {
  const out = new Map<string, string[]>();
  if (!tasks.length) return out;
  const rows = await db.selectFrom('task_events').select(['task_id', 'payload', 'created_at']).where('type', '=', 'structured')
    .where('task_id', 'in', tasks.map((t) => t.id)).orderBy('created_at', 'asc').execute();
  for (const r of rows) out.set(r.task_id, (JSON.parse(r.payload as unknown as string).warnings as string[] | undefined) ?? []);
  return out;
}

/** History page: oldest first within the page; `before` is the oldest message id the phone already has. */
export async function listMessages(db: Db, thread: Thread, before: string | undefined, limit: number, viewerId?: string) {
  let q = db.selectFrom('messages').selectAll().where('thread_id', '=', thread.id);
  if (before) {
    const ref = await db.selectFrom('messages').select('id').where('id', '=', before).where('thread_id', '=', thread.id).executeTakeFirst();
    if (!ref) throw badRequest('Unknown cursor.');
    // Compare inside SQL: a time sent back from JS is rounded by the driver and can skip or repeat a message.
    const refTime = db.selectFrom('messages').select('created_at').where('id', '=', ref.id);
    q = q.where((eb) => eb.or([eb('created_at', '<', refTime), eb.and([eb('created_at', '=', refTime), eb('id', '<', ref.id)])]));
  }
  const page = await q.orderBy('created_at', 'desc').orderBy('id', 'desc').top(limit + 1).execute();
  const more = page.length > limit;
  const items = (await withTasks(db, page.slice(0, limit), viewerId)).reverse();
  return { items, nextCursor: more ? items[0]!.message.id : null };
}

export type MessageWithTask = Awaited<ReturnType<typeof loadMessage>>;
export type { Task };

/** A reply on a task (Ornate's "answer the question"): no new task. When the requester answers a question,
 *  the task goes back to In progress and its clock runs again. */
async function reply(db: Db, me: User, thread: Thread, body: NewMessage) {
  const t = await db.selectFrom('tasks').selectAll().where('id', '=', body.replyToTaskId!).where('thread_id', '=', thread.id).executeTakeFirst();
  if (!t) throw badRequest('That task is not in this chat.');
  const sender = (await db.selectFrom('messages').select('sender_id').where('id', '=', t.message_id).executeTakeFirstOrThrow()).sender_id;
  const now = new Date();
  let answered = false;
  const holidays = await loadHolidays(db);
  const id = await db.transaction().execute(async (tx) => {
    const m = await tx.insertInto('messages').values({
      thread_id: thread.id, sender_id: me.id, client_msg_id: body.clientMsgId, kind: body.kind, body_text: body.bodyText || null,
      audio_key: body.audioKey ?? null, audio_duration_s: body.audioDurationS ?? null, transcript: null, transcript_lang: null, reply_to_task_id: t.id,
    }).output('inserted.id').executeTakeFirstOrThrow();
    if (t.status === 'WaitingInfo' && sender === me.id) {
      const shift = shiftOf((await tx.selectFrom('users').select('shift').where('id', '=', t.assignee_id ?? me.id).executeTakeFirst())?.shift);
      await tx.updateTable('tasks').set({ status: 'InProgress', ...start(t, now, shift, holidays), updated_at: now }).where('id', '=', t.id).execute();
      await tx.insertInto('task_events').values({ task_id: t.id, actor_id: me.id, type: 'answered', payload: JSON.stringify({ messageId: m.id }) }).execute();
      answered = true;
    }
    await tx.updateTable('threads').set({ last_message_at: now }).where('id', '=', thread.id).execute();
    return m.id;
  });
  return { created: true, answered, replyTo: t, ...(await loadMessage(db, id)) };
}

/** `/subtask` rules: only the person working on the task, while it is accepted or in progress, to another department's chat. */
async function subtaskParent(db: Db, me: User, thread: Thread, parentId: string) {
  const p = await db.selectFrom('tasks').selectAll().where('id', '=', parentId).executeTakeFirst();
  if (!p) throw badRequest('That task was not found.');
  if (p.assignee_id !== me.id || !['Accepted', 'InProgress'].includes(p.status) || !p.department_id) throw forbidden('Only the person working on the task can hand off part of it.');
  if (thread.type !== 'department' || thread.requester_id !== me.id) throw badRequest('Send a sub-task to a department.');
  if (thread.department_id === p.department_id) throw badRequest('Choose another department.');
  return p;
}

/** Sub-task numbers follow the parent: ORN-SS-2627-00042/T2, /T3 ... (Ornate). */
async function subtaskNo(db: Db, parent: Task) {
  const n = await db.selectFrom('tasks').select(db.fn.countAll<number>().as('n')).where('parent_task_id', '=', parent.id).executeTakeFirstOrThrow();
  return `${parent.ticket_no ?? 'T'}/T${Number(n.n) + 2}`;
}

/** A sub-task ended: its parent hears about it, and goes back to In progress once none are left open. */
export async function subtaskSettled(db: Db, sub: Pick<Task, 'id' | 'parent_task_id' | 'subject'>, actorId: string | null) {
  if (!sub.parent_task_id) return null;
  const p = await db.selectFrom('tasks').selectAll().where('id', '=', sub.parent_task_id).executeTakeFirst();
  if (!p) return null;
  await db.insertInto('task_events').values({ task_id: p.id, actor_id: actorId, type: 'subtask_done', payload: JSON.stringify({ subTaskId: sub.id, subject: sub.subject }) }).execute();
  const open = await db.selectFrom('tasks').select('id').where('parent_task_id', '=', p.id)
    .where('status', 'not in', [...FINISHED, 'Completed', 'Verified']).execute();
  if (p.status === 'WaitingDept' && !open.length) {
    const holidays = await loadHolidays(db);
    const shift = shiftOf((await db.selectFrom('users').select('shift').where('id', '=', p.assignee_id ?? '').executeTakeFirst())?.shift);
    await db.updateTable('tasks').set({ status: 'InProgress', ...start(p, new Date(), shift, holidays), updated_at: new Date() }).where('id', '=', p.id).where('status', '=', 'WaitingDept').execute();
  }
  return p;
}
