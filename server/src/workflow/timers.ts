// Ornate's timers, run every minute (in the API with QUEUE_MODE=inline, in the worker with bullmq):
// not accepted in time -> escalate to the lead, then the department head after 1 more working hour;
// warnings at 75% and with 1 hour left; overdue alerts; auto-verify after 2 working days; auto-close 3 later.
import type { Db } from '../db/client';
import type { Task, TaskEventType } from '../db/schema';
import type { JobQueue } from '../jobs/queue';
import type { Logger } from '../lib/logger';
import { threadRooms } from '../modules/access';
import { taskDto } from '../modules/dto';
import { leadChain, loadOrg } from '../modules/org';
import type { Realtime } from '../realtime';
import { loadHolidays, shiftOf, used } from './clock';
import { escalationTargets, workingDaysSince } from './engine';
import { ACCEPT_HOURS, HOUR, LIMITS, workMs } from './time';

export interface TimerDeps { db: Db; realtime: Realtime; jobs: () => JobQueue; log: Logger }

export async function tick(d: TimerDeps, nowDate = new Date()) {
  const { db } = d;
  const now = nowDate.getTime();
  const [org, holidays] = await Promise.all([loadOrg(db), loadHolidays(db)]);
  const tasks = await db.selectFrom('tasks').selectAll().where('status', 'in', ['Open', 'Accepted', 'InProgress', 'Completed', 'Verified']).execute();
  const shifts = new Map((await db.selectFrom('users').select(['id', 'shift']).execute()).map((u) => [u.id, shiftOf(u.shift)]));
  const senders = new Map((await db.selectFrom('messages').select(['id', 'sender_id']).where('id', 'in', tasks.length ? tasks.map((t) => t.message_id) : ['00000000-0000-0000-0000-000000000000']).execute()).map((m) => [m.id, m.sender_id]));

  const record = async (t: Task, type: TaskEventType, payload: Record<string, unknown>, fields: Record<string, unknown>, to: string[], text: string) => {
    await db.updateTable('tasks').set({ ...fields, updated_at: nowDate }).where('id', '=', t.id).where('status', '=', t.status).execute();
    await db.insertInto('task_events').values({ task_id: t.id, actor_id: null, type, payload: JSON.stringify({ ...payload, system: true }) }).execute();
    const fresh = await db.selectFrom('tasks').selectAll().where('id', '=', t.id).executeTakeFirstOrThrow();
    const thread = await db.selectFrom('threads').selectAll().where('id', '=', t.thread_id).executeTakeFirstOrThrow();
    d.realtime.emit([...threadRooms(thread), ...to.map((u) => `user:${u}`)], 'task.updated', { task: taskDto(fresh), event: { type, payload } });
    const recipients = [...new Set(to)].filter(Boolean);
    if (recipients.length) await d.jobs().enqueue('notify', { taskId: t.id, kind: 'status', toUserIds: recipients, text }, { jobId: `notify:${t.id}:${type}:${now}` });
  };

  for (const t of tasks) {
    const senderId = senders.get(t.message_id)!;
    try {
      if (t.status === 'Open') {
        const lim = LIMITS[t.priority];
        const waited = workMs(new Date(t.queued_at ?? t.created_at).getTime(), now, ACCEPT_HOURS, holidays);
        if (!t.auto_escalated_at && waited > lim.acceptMs) {
          const target = escalationTargets({ org, task: t, senderId }, 'team_lead');
          await record(t, 'escalated', { level: target.level, to: target.ids, reason: `Not accepted within ${lim.accept}.` },
            { escalation_level: target.level, escalated_to: JSON.stringify(target.ids), auto_escalated_at: nowDate }, [...target.ids, senderId], `not accepted within ${lim.accept}: escalated`);
        } else if (t.auto_escalated_at && !t.head_alerted && workMs(new Date(t.auto_escalated_at).getTime(), now, ACCEPT_HOURS, holidays) >= HOUR) {
          const head = org.departments.find((x) => x.id === t.department_id)?.head_user_id;
          await record(t, 'warned', { kind: 'needs_assigning' }, { head_alerted: true }, head ? [head] : [], 'still has no owner 1 working hour after escalation: please assign it');
        }
        continue;
      }
      if ((t.status === 'Accepted' || t.status === 'InProgress') && t.clock_state === 'running' && t.assignee_id) {
        const lim = LIMITS[t.priority].completeMs;
        const usedMs = used(t, now, shifts.get(t.assignee_id) ?? shiftOf(0), holidays);
        const warned = JSON.parse(t.warned) as string[];
        const mark = usedMs > lim ? 'over' : lim - usedMs <= HOUR ? '1h' : usedMs >= 0.75 * lim ? '75' : null;
        if (mark && !warned.includes(mark)) {
          const lead = leadChain(org, t.assignee_id)[0];
          const to = mark === 'over' ? [t.assignee_id, ...(lead ? [lead] : [])] : [t.assignee_id];
          const text = mark === 'over' ? 'is overdue' : mark === '1h' ? 'has 1 working hour left' : 'has used 75% of its time';
          await record(t, 'warned', { kind: mark }, { warned: JSON.stringify([...warned, mark]) }, to, text);
        }
        continue;
      }
      if (t.status === 'Completed' && t.completed_at && workingDaysSince(new Date(t.completed_at), nowDate, holidays) >= 2) {
        await record(t, 'verified', { auto: true }, { status: 'Verified', verified_at: nowDate }, [senderId, ...(t.assignee_id ? [t.assignee_id] : [])], 'verified itself after 2 working days');
        continue;
      }
      if (t.status === 'Verified' && t.verified_at && workingDaysSince(new Date(t.verified_at), nowDate, holidays) >= 3) {
        await record(t, 'closed', { auto: true }, { status: 'Closed', closed_at: nowDate, resolution: t.resolution ?? 'Closed automatically after verification.' },
          [senderId], 'closed itself 3 working days after verification');
      }
    } catch (e) {
      d.log.error({ task: t.id, err: (e as Error).message }, 'timer failed for a task');
    }
  }
}
