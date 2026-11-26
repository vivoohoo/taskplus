// What each background job does (spec §9.5). Jobs never block the sender: the task already exists when they run.
import type { Env } from '../config/env';
import type { Db } from '../db/client';
import type { Overrides, Task, Thread } from '../db/schema';
import type { Logger } from '../lib/logger';
import { otherUserId, threadRooms } from '../modules/access';
import { taskDto } from '../modules/dto';
import { warningsFor } from '../modules/messages/service';
import { acceptDue, loadHolidays } from '../workflow/clock';
import type { Realtime } from '../realtime';
import type { PushProvider } from '../push/PushProvider';
import type { StorageProvider } from '../storage/StorageProvider';
import { AiUnavailableError } from '../ai/llm/LlmProvider';
import type { LlmGateway } from '../ai/llm/gateway';
import { PROMPT_VERSION, structurePrompt } from '../ai/prompts/structure.v2';
import { providerSchema } from '../ai/schema/taskExtraction';
import type { SttProvider } from '../ai/stt/SttProvider';
import { validateExtraction } from '../ai/validate';
import type { JobHandlers, JobName, JobQueue } from './queue';
import type { Metrics } from '../lib/metrics';

export type NotifyKind = 'created' | 'accepted' | 'reassigned' | 'status';
export interface JobDeps {
  env: Env; db: Db; log: Logger; realtime: Realtime; storage: StorageProvider; llm: LlmGateway; stt: SttProvider;
  push: PushProvider; metrics: Metrics; jobs: () => JobQueue;
}

const FALLBACK_MODULES = ['Other'];

export function jobHandlers(d: JobDeps): JobHandlers {
  const loadTask = (id: string) => d.db.selectFrom('tasks').selectAll().where('id', '=', id).executeTakeFirstOrThrow();
  const loadThread = (id: string) => d.db.selectFrom('threads').selectAll().where('id', '=', id).executeTakeFirstOrThrow();

  /** Everyone who should see a task change live: the thread, its department and the assignee. */
  const rooms = (t: Thread, task: Task) => [...threadRooms(t), ...(task.assignee_id ? [`user:${task.assignee_id}`] : [])];
  const broadcastStructured = async (task: Task) => {
    const thread = await loadThread(task.thread_id);
    const warnings = (await warningsFor(d.db, [task])).get(task.id) ?? [];
    d.realtime.emit(rooms(thread, task), 'task.structured', { task: taskDto(task, warnings) });
  };

  async function transcribe({ messageId, taskId }: { messageId: string; taskId: string }) {
    const m = await d.db.selectFrom('messages').selectAll().where('id', '=', messageId).executeTakeFirstOrThrow();
    if (!m.transcript) {
      const head = await d.storage.head(m.audio_key!);
      const audio = await d.storage.get(m.audio_key!);
      const r = await d.stt.transcribe({ audio, mime: head?.mime ?? 'audio/ogg', hintLangs: ['en', 'hi', 'gu'] });
      await d.db.updateTable('messages').set({ transcript: r.text, transcript_lang: r.lang ?? null }).where('id', '=', m.id).execute();
      const thread = await loadThread(m.thread_id);
      d.realtime.emit(threadRooms(thread), 'task.transcribed', { taskId, messageId: m.id, transcript: r.text });
    }
    await d.jobs().enqueue('structure', { taskId }, { jobId: `structure:${taskId}` });
  }

  async function structure({ taskId }: { taskId: string }) {
    const task = await loadTask(taskId);
    if (task.ai_status !== 'pending') return; // already done (a retry after success, or a duplicate)
    const [m, thread] = await Promise.all([
      d.db.selectFrom('messages').selectAll().where('id', '=', task.message_id).executeTakeFirstOrThrow(),
      loadThread(task.thread_id),
    ]);
    const text = (m.body_text ?? m.transcript ?? '').trim();
    const overrides = JSON.parse(task.overrides as unknown as string) as Overrides;
    if (!text) return finish(task, null, 'No text to read: the message has only attachments.', [], null);

    const sender = await d.db.selectFrom('users').select(['name', 'department_id']).where('id', '=', m.sender_id).executeTakeFirstOrThrow();
    // Department thread: that department. Direct chat: the recipient's department, for its module list.
    const recipientId = thread.type === 'direct' ? otherUserId(thread, m.sender_id) : null;
    const recipient = recipientId ? await d.db.selectFrom('users').select(['name', 'department_id']).where('id', '=', recipientId).executeTakeFirst() : null;
    const deptId = thread.department_id ?? recipient?.department_id ?? sender.department_id;
    const dept = deptId ? await d.db.selectFrom('departments').select(['name', 'modules']).where('id', '=', deptId).executeTakeFirst() : null;
    const modules = dept ? (JSON.parse(dept.modules as unknown as string) as string[]) : FALLBACK_MODULES;

    const input = {
      departmentName: dept?.name ?? 'General', modules, senderName: sender.name,
      recipientLabel: recipient?.name ?? `${dept?.name ?? 'Department'} team`, text,
    };
    d.log.debug({ prompt: structurePrompt(input) }, 'LLM prompt'); // debug only: contains message text
    const { data, provider } = await d.llm.extract({ ...input, prompt: structurePrompt(input), jsonSchema: providerSchema(modules) });
    const v = validateExtraction(data, { modules, overrides, licenseRegex: d.env.LICENSE_REGEX });
    if (!v.ok) return finish(task, null, v.error, [], provider);
    return finish(task, v.value, null, v.warnings, provider);
  }

  /** Save the result (or the reason there is none), tell the room, and send the push. */
  async function finish(task: Task, value: import('../ai/validate').Structured | null, error: string | null, warnings: string[], provider: string | null) {
    const now = new Date();
    await d.db.transaction().execute(async (tx) => {
      await tx.updateTable('tasks').set({
        ...(value ? { ...value, ...(task.status === 'Open' ? { due_at: acceptDue(new Date(task.queued_at ?? task.created_at), value.priority, await loadHolidays(d.db)) } : {}) } : {}),
        ai_status: value ? 'done' : 'needs_review',
        ai_error: error?.slice(0, 400) ?? null,
        ai_provider: provider,
        prompt_version: PROMPT_VERSION,
        updated_at: now,
      }).where('id', '=', task.id).where('ai_status', '=', 'pending').execute();
      await tx.insertInto('task_events').values({ task_id: task.id, actor_id: null, type: 'structured',
        payload: JSON.stringify({ provider, promptVersion: PROMPT_VERSION, warnings, error }) }).execute();
    });
    d.metrics.aiJobs.inc({ status: value ? 'done' : 'needs_review', provider: provider ?? 'none' });
    await broadcastStructured(await loadTask(task.id));
    await d.jobs().enqueue('notify', { taskId: task.id, kind: 'created' }, { jobId: `notify:${task.id}:created` });
  }

  async function notify({ taskId, kind, toUserIds, text }: { taskId: string; kind: NotifyKind; toUserIds?: string[]; text?: string }) {
    const task = await loadTask(taskId);
    const [m, thread] = await Promise.all([
      d.db.selectFrom('messages').select(['sender_id', 'body_text', 'transcript']).where('id', '=', task.message_id).executeTakeFirstOrThrow(),
      loadThread(task.thread_id),
    ]);
    let to: string[];
    if (toUserIds) to = toUserIds;
    else if (kind === 'created') to = await recipientsOfNew(thread, task, m.sender_id);
    else to = [m.sender_id];
    to = [...new Set(to)].filter(Boolean);
    if (!to.length) return;

    const sender = await d.db.selectFrom('users').select('name').where('id', '=', m.sender_id).executeTakeFirstOrThrow();
    const what = task.subject ?? (m.body_text ?? m.transcript ?? 'Voice note').slice(0, 80);
    const msg = kind === 'created'
      ? { title: `${sender.name}${task.priority === 'High' ? ' · High' : ''}`, body: what }
      : { title: what, body: text ? text.charAt(0).toUpperCase() + text.slice(1) : (task.status === 'InProgress' ? 'In progress' : task.status) };

    const tokens = await d.db.selectFrom('device_tokens').select('fcm_token').where('user_id', 'in', to).execute();
    const { invalidTokens } = await d.push.send(tokens.map((t) => t.fcm_token), { ...msg, threadId: thread.id, taskId: task.id });
    if (invalidTokens.length) await d.db.deleteFrom('device_tokens').where('fcm_token', 'in', invalidTokens).execute();
  }

  /** D3 (owner, 26 Nov): a tagged department task pushes to the tagged person only; otherwise the whole department. */
  async function recipientsOfNew(thread: Thread, task: Task, senderId: string) {
    if (thread.type === 'direct') return [otherUserId(thread, senderId)!];
    if (task.tagged_user_id) return task.tagged_user_id === senderId ? [] : [task.tagged_user_id];
    if (thread.team_id) {
      const team = await d.db.selectFrom('users').select('id').where('team_id', '=', thread.team_id).where('is_active', '=', true).execute();
      return team.map((u) => u.id).filter((id) => id !== senderId);
    }
    const members = await d.db.selectFrom('users').select('id').where('department_id', '=', thread.department_id).where('is_active', '=', true).execute();
    return members.map((u) => u.id).filter((id) => id !== senderId);
  }

  return {
    async run(name: JobName, data: unknown) {
      if (name === 'transcribe') return transcribe(data as { messageId: string; taskId: string });
      if (name === 'structure') return structure(data as { taskId: string });
      return notify(data as { taskId: string; kind: NotifyKind; toUserIds?: string[] });
    },
    /** After the last attempt: the task still reaches the recipient, marked "Needs review", with the raw text. */
    async failed(name: JobName, data: unknown, err: Error) {
      if (name === 'notify') return;
      const { taskId } = data as { taskId: string };
      const task = await loadTask(taskId);
      if (task.ai_status !== 'pending') return;
      const why = err instanceof AiUnavailableError ? 'AI unavailable' : name === 'transcribe' ? 'Could not transcribe the voice note' : 'AI processing failed';
      await finish(task, null, `${why}: ${err.message}`, [], null);
    },
  };
}
