// The task clock: runs only while someone is working on it, in the owner's shift; pauses while waiting or blocked.
import type { Db } from '../db/client';
import type { Priority, Task } from '../db/schema';
import { ACCEPT_HOURS, LIMITS, SHIFTS, addWorkMs, workMs } from './time';

/** Far-future due date for a paused clock, so paused tasks never show as overdue. */
export const NEVER = new Date('9999-12-31T00:00:00Z');

export async function loadHolidays(db: Db): Promise<Set<string>> {
  const rows = await db.selectFrom('holidays').select('day').execute();
  return new Set(rows.map((r) => new Date(r.day).toISOString().slice(0, 10)));
}

export const shiftOf = (shift: number | undefined | null): [number, number] => SHIFTS[shift ?? 0] ?? SHIFTS[0]!;

/** Working time used so far (including a running stretch). */
export function used(t: Pick<Task, 'clock_used_ms' | 'clock_running_since'>, now: number, shift: [number, number], holidays: ReadonlySet<string>) {
  const base = Number(t.clock_used_ms);
  return t.clock_running_since ? base + workMs(new Date(t.clock_running_since).getTime(), now, shift, holidays) : base;
}

/** Accept deadline for an Open task. */
export const acceptDue = (queuedAt: Date, p: Priority, holidays: ReadonlySet<string>) =>
  new Date(addWorkMs(queuedAt.getTime(), LIMITS[p].acceptMs, ACCEPT_HOURS, holidays));

/** Fields to start (or resume) the clock now. */
export function start(t: Pick<Task, 'clock_used_ms' | 'priority'>, now: Date, shift: [number, number], holidays: ReadonlySet<string>) {
  const left = LIMITS[t.priority].completeMs - Number(t.clock_used_ms);
  return { clock_state: 'running' as const, clock_running_since: now, due_at: new Date(addWorkMs(now.getTime(), left, shift, holidays)) };
}

/** Fields to pause or stop the clock now, banking the time used. */
export function halt(t: Pick<Task, 'clock_used_ms' | 'clock_running_since'>, now: Date, state: 'paused' | 'stopped', shift: [number, number], holidays: ReadonlySet<string>) {
  return { clock_state: state, clock_used_ms: used(t, now.getTime(), shift, holidays), clock_running_since: null, due_at: NEVER };
}
