// Flow A/B (spec §11): one transaction saves message + task + "created" event + thread time; events and AI jobs only after commit.
import { z } from 'zod';
import type { Env } from '../../config/env';
import type { Db } from '../../db/client';
import type { Message, Priority, Task, Thread, User } from '../../db/schema';
import { badRequest } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { KEY_PATTERN, type StorageProvider } from '../../storage/StorageProvider';
import { type AttachmentRow, messageDto, taskDto } from '../dto';

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
const scopeOf = (t: Thread) => (t.type === 'direct' ? 'direct' : t.department_id!.toLowerCase());

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

  const priority: Priority = body.overrides.priority ?? env.DEFAULT_PRIORITY;
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
        message_id: message.id, thread_id: thread.id, priority, due_at: dueAt(env, priority),
        department_id: thread.department_id, team_id: thread.team_id, tagged_user_id: body.taggedUserId ?? null,
        overrides: JSON.stringify(body.overrides),
        subject: null, module: null, customer_name: null, customer_phone: null, customer_location: null, license_no: null,
        details: null, assignee_id: null, ai_error: null, ai_provider: null, prompt_version: null, closed_at: null,
      }).output('inserted.id').executeTakeFirstOrThrow();
      await tx.insertInto('task_events').values({ task_id: task.id, actor_id: me.id, type: 'created', payload: JSON.stringify({ kind: body.kind }) }).execute();
      await tx.updateTable('threads').set({ last_message_at: new Date(), updated_at: new Date() }).where('id', '=', thread.id).execute();
      return message.id;
    });
    return { created: true, ...(await loadMessage(db, out)) };
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

/** Messages with their attachments and task (and the task's latest check warnings). */
export async function withTasks(db: Db, messages: Message[]) {
  if (!messages.length) return [];
  const ids = messages.map((m) => m.id);
  const [atts, tasks] = await Promise.all([
    db.selectFrom('attachments').selectAll().where('message_id', 'in', ids).execute(),
    db.selectFrom('tasks').selectAll().where('message_id', 'in', ids).execute(),
  ]);
  const warnings = await warningsFor(db, tasks);
  return messages.map((m) => {
    const task = tasks.find((t) => t.message_id === m.id);
    return {
      message: messageDto(m, atts.filter((a) => a.message_id === m.id) as AttachmentRow[]),
      task: task ? taskDto(task, warnings.get(task.id) ?? []) : null,
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
export async function listMessages(db: Db, thread: Thread, before: string | undefined, limit: number) {
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
  const items = (await withTasks(db, page.slice(0, limit))).reverse();
  return { items, nextCursor: more ? items[0]!.message.id : null };
}

export type MessageWithTask = Awaited<ReturnType<typeof loadMessage>>;
export type { Task };
