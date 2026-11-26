// Working-hours clock from Ornate Samanvay. India time (UTC+5:30, no daylight saving), whatever the server's time zone.
import type { Priority } from '../db/schema';

const IST = 5.5 * 3600_000;
const DAY = 86_400_000;
export const HOUR = 3_600_000;
export const WORKING_DAY = 9 * HOUR;

/** Shifts, Monday to Saturday: index stored on users.shift. */
export const SHIFTS: [number, number][] = [[9, 18], [10, 19], [11, 20]];
export const SHIFT_LABELS = ['9 am – 6 pm', '10 am – 7 pm', '11 am – 8 pm'];
/** The accept clock runs 9 am – 8 pm, whoever is on shift. */
export const ACCEPT_HOURS: [number, number] = [9, 20];

/** Time to accept, and working time to complete, per priority (Ornate's table). */
export const LIMITS: Record<Priority, { acceptMs: number; completeMs: number; accept: string; complete: string }> = {
  Critical: { acceptMs: 15 * 60_000, completeMs: 4 * HOUR, accept: '15 min', complete: '4 working hours' },
  High: { acceptMs: 30 * 60_000, completeMs: WORKING_DAY, accept: '30 min', complete: '1 working day' },
  Medium: { acceptMs: 2 * HOUR, completeMs: 3 * WORKING_DAY, accept: '2 hours', complete: '3 working days' },
  Low: { acceptMs: 4 * HOUR, completeMs: 7 * WORKING_DAY, accept: '4 hours', complete: '7 working days' },
};

/** "2026-01-26" in India time. */
export const istDate = (t: number) => new Date(t + IST).toISOString().slice(0, 10);
const istDayStart = (t: number) => Math.floor((t + IST) / DAY) * DAY - IST;
const isDayOff = (dayStart: number, holidays: ReadonlySet<string>) => new Date(dayStart + IST).getUTCDay() === 0 || holidays.has(istDate(dayStart));

/** Working milliseconds between two times, counting only [h1, h2) on working days. */
export function workMs(from: number, to: number, hours: [number, number], holidays: ReadonlySet<string> = new Set()): number {
  if (to <= from) return 0;
  let total = 0;
  for (let d = istDayStart(from); d < to; d += DAY) {
    if (isDayOff(d, holidays)) continue;
    const s = Math.max(from, d + hours[0] * HOUR), e = Math.min(to, d + hours[1] * HOUR);
    if (e > s) total += e - s;
  }
  return total;
}

/** The moment `ms` of working time has passed after `from`. */
export function addWorkMs(from: number, ms: number, hours: [number, number], holidays: ReadonlySet<string> = new Set()): number {
  let left = Math.max(0, ms);
  for (let d = istDayStart(from); ; d += DAY) {
    if (isDayOff(d, holidays)) continue;
    const s = Math.max(from, d + hours[0] * HOUR), e = d + hours[1] * HOUR;
    if (e <= s) continue;
    if (e - s >= left) return s + left;
    left -= e - s;
  }
}

/** "1 h 20 min", "2 d 3 h" (working days of 9 h). */
export function duration(ms: number): string {
  const m = Math.round(Math.abs(ms) / 60_000);
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60), r = m % 60;
  if (h < 9) return r ? `${h} h ${r} min` : `${h} h`;
  const d = Math.floor(h / 9), hh = h % 9;
  return hh ? `${d} d ${hh} h` : `${d} d`;
}
