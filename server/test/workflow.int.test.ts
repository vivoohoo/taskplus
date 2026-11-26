// Ornate's core workflow and working-hours clock in Task Plus (docs/PARITY.md, step 3).
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { tick } from '../src/workflow/timers';
import { addWorkMs, HOUR, workMs } from '../src/workflow/time';
import { startTestApp, type TestApp } from './helpers/app';

let t: TestApp;
const P = { riya: '9800000002', karan: '9800000003', supLead: '9800000001', tushar: '9800000004', dhaval: '9800000005', vishwas: '9800000006', nisha: '9800000007', kunal: '9800000011', admin: '9800000010' };
const tok: Record<string, string> = {};
let dev = '', sup = '';

beforeAll(async () => {
  t = await startTestApp();
  for (const [k, phone] of Object.entries(P)) tok[k] = await t.token(phone);
  dev = (await t.db.selectFrom('departments').select('id').where('name', '=', 'Development').executeTakeFirstOrThrow()).id;
  sup = (await t.db.selectFrom('departments').select('id').where('name', '=', 'Support').executeTakeFirstOrThrow()).id;
}, 240_000);
afterAll(async () => { await t?.stop(); });

const id = (k: keyof typeof P) => t.ids.get(P[k])!;
async function newTask(from: keyof typeof P, to: { department?: string; user?: keyof typeof P }, text: string, extra: object = {}) {
  const target = to.user ? { targetType: 'user', targetId: id(to.user) } : { targetType: 'department', targetId: to.department };
  const th = (await t.as(tok[from]!).post('/v1/threads/open', target)).body.thread;
  const r = await t.as(tok[from]!).post(`/v1/threads/${th.id}/messages`, { clientMsgId: randomUUID(), kind: 'text', bodyText: text, ...extra });
  await t.app.services.jobs.idle();
  return { threadId: th.id as string, taskId: r.body.task.id as string };
}
const act = (who: keyof typeof P, taskId: string, a: string, body: object = {}) => t.as(tok[who]!).post(`/v1/tasks/${taskId}/actions/${a}`, body);
const view = async (who: keyof typeof P, taskId: string) => (await t.as(tok[who]!).get(`/v1/tasks/${taskId}`)).body.task;

describe('working-hours clock (India time, Mon–Sat, holidays skipped)', () => {
  const ist = (s: string) => Date.parse(`${s}+05:30`);
  it('counts only shift hours and skips Sundays and holidays', () => {
    expect(workMs(ist('2026-11-27T17:00:00'), ist('2026-11-28T10:00:00'), [9, 18])).toBe(2 * HOUR); // Fri 17-18 + Sat 9-10
    expect(workMs(ist('2026-11-28T17:00:00'), ist('2026-11-30T10:00:00'), [9, 18])).toBe(2 * HOUR); // Sunday skipped
    expect(workMs(ist('2026-12-24T17:00:00'), ist('2026-12-26T10:00:00'), [9, 18], new Set(['2026-12-25']))).toBe(2 * HOUR);
  });
  it('finds when working time runs out', () => {
    expect(new Date(addWorkMs(ist('2026-11-28T17:30:00'), HOUR, [9, 18])).toISOString()).toBe(new Date(ist('2026-11-30T09:30:00')).toISOString());
  });
});

describe('actions each person gets', () => {
  it('recipient accepts; requester may cancel; the server lists only allowed buttons', async () => {
    const { taskId } = await newTask('riya', { department: dev }, 'Profit NX invoice rounding');
    expect(await view('riya', taskId)).toMatchObject({ status: 'Open' });
    expect((await view('riya', taskId)).actions).toEqual(expect.arrayContaining(['cancel', 'change_priority', 'escalate']));
    expect((await view('kunal', taskId)).actions).toEqual(expect.arrayContaining(['accept', 'request_reject', 'request_transfer']));
    expect((await view('tushar', taskId)).actions).toEqual(expect.arrayContaining(['accept', 'reassign', 'reject', 'transfer']));
    const a = await act('kunal', taskId, 'accept');
    expect(a.body.task).toMatchObject({ status: 'Accepted', assigneeId: id('kunal') });
    expect(a.body.task.clock.state).toBe('running');
    expect(a.body.task.actions).toEqual(expect.arrayContaining(['in_progress', 'complete', 'ask_requester', 'block', 'ask_reassign']));
    expect((await act('riya', taskId, 'cancel')).status).toBe(403);
  });
});

describe('ask the requester, block, complete, verify, reopen', () => {
  it('pauses for a question until the requester answers in the chat', async () => {
    const { threadId, taskId } = await newTask('riya', { user: 'dhaval' }, 'SQL backup failing at Om Logistics');
    await act('dhaval', taskId, 'accept');
    const q = await act('dhaval', taskId, 'ask_requester', { question: 'Which server name?' });
    expect(q.body.task).toMatchObject({ status: 'WaitingInfo', dueAt: null });
    expect(q.body.task.clock.state).toBe('paused');
    const r = await t.as(tok.riya!).post(`/v1/threads/${threadId}/messages`, { clientMsgId: randomUUID(), kind: 'text', bodyText: 'OML-SRV-02', replyToTaskId: taskId });
    expect(r.status).toBe(201);
    expect(r.body.task).toBeNull(); // a reply, not a new task
    expect(await view('dhaval', taskId)).toMatchObject({ status: 'InProgress' });
  });

  it('block stops the clock; complete -> verify -> close; reopen within 7 days', async () => {
    const { taskId } = await newTask('karan', { user: 'nisha' }, 'Power BI refresh stuck');
    await act('nisha', taskId, 'accept');
    expect((await act('nisha', taskId, 'block', { reason: 'Waiting for gateway access' })).body.task.status).toBe('Blocked');
    expect((await act('nisha', taskId, 'unblock')).body.task.clock.state).toBe('running');
    expect((await act('nisha', taskId, 'complete', {})).status).toBe(400); // remarks needed
    await act('nisha', taskId, 'complete', { remarks: 'Gateway restarted' });
    expect((await view('karan', taskId)).actions).toEqual(['verify', 'reopen']);
    await act('karan', taskId, 'verify');
    await act('karan', taskId, 'close', { resolution: 'Refreshing again', customerInformed: 'n/a' });
    const re = await act('karan', taskId, 'reopen', { reason: 'Stuck again this morning' });
    expect(re.body.task).toMatchObject({ status: 'InProgress', closedAt: null });
    expect(re.body.task.clock.state).toBe('running');
  });
});

describe('staff requests and reassignment', () => {
  it('staff ask to reject; the lead sees only Approve / Refuse; approval rejects it', async () => {
    const { taskId } = await newTask('riya', { department: dev }, 'Please change our logo colour');
    await act('kunal', taskId, 'request_reject', { reason: 'Marketing, not development' });
    expect((await view('tushar', taskId)).actions).toEqual(['approve_request', 'refuse_request']);
    const ok = await act('tushar', taskId, 'approve_request');
    expect(ok.body.task.status).toBe('Rejected');
  });

  it('staff ask to be reassigned once a day; the lead gets only Reassign / Keep it with me', async () => {
    const { taskId } = await newTask('riya', { department: dev }, 'Ornate GST export blank');
    await act('nisha', taskId, 'accept');
    await act('nisha', taskId, 'ask_reassign', { reason: 'On leave tomorrow' });
    expect((await view('vishwas', taskId)).actions).toEqual(['reassign', 'keep']);
    expect((await view('nisha', taskId)).actions).not.toContain('ask_reassign');
    await act('vishwas', taskId, 'keep');
    expect((await view('nisha', taskId)).actions).not.toContain('ask_reassign'); // once a day
  });

  it('transfer: ends here, continues in the other department with the time used kept', async () => {
    const { taskId } = await newTask('riya', { department: dev }, 'Printer driver for Kaveri Steel');
    await act('kunal', taskId, 'accept');
    const r = await act('tushar', taskId, 'transfer', { reason: 'Support handles printers', departmentId: sup });
    expect(r.body.task.status).toBe('Transferred');
    const moved = await t.db.selectFrom('tasks').selectAll().where('transferred_from_id', '=', taskId).executeTakeFirstOrThrow();
    expect(moved).toMatchObject({ status: 'Open', department_id: sup });
    expect((await t.as(tok.karan!).get('/v1/tasks?filter=my_pending')).body.items.map((x: { task: { id: string } }) => x.task.id)).toContain(moved.id);
  });
});

describe('escalation and priority', () => {
  it('escalates to the next level that someone holds, and only they attend it', async () => {
    const { taskId } = await newTask('riya', { department: dev }, 'Mobile app crash on login');
    await act('nisha', taskId, 'accept');
    const e = await act('riya', taskId, 'escalate', { level: 'team_lead', reason: 'Customer waiting since morning' });
    expect(e.body.task).toMatchObject({ escalationLevel: 'team_lead', escalatedTo: [id('vishwas')] });
    expect((await view('vishwas', taskId)).actions).toContain('attend');
    expect((await view('dhaval', taskId)).actions).not.toContain('attend');
    expect((await act('vishwas', taskId, 'attend')).body.task.escalationLevel).toBeNull();
  });

  it('staff may raise priority but not lower it; leads may lower', async () => {
    const { taskId } = await newTask('riya', { department: dev }, 'Report font too small', { overrides: { priority: 'Medium' } });
    await act('kunal', taskId, 'accept');
    expect((await act('kunal', taskId, 'change_priority', { priority: 'High', reason: 'Customer escalated' })).body.task.priority).toBe('High');
    expect((await act('kunal', taskId, 'change_priority', { priority: 'Low', reason: 'x' })).status).toBe(403);
    expect((await act('dhaval', taskId, 'change_priority', { priority: 'Low', reason: 'Cosmetic' })).body.task.priority).toBe('Low');
  });
});

describe('timers', () => {
  const deps = () => ({ db: t.db, realtime: t.app.services.realtime, jobs: () => t.app.services.jobs, log: t.app.log as never });
  it('escalates an unaccepted task, then alerts the head an hour later', async () => {
    const { taskId } = await newTask('riya', { department: dev }, 'Server down at Kaveri Steel', { overrides: { priority: 'Critical' } });
    const later = new Date(Date.now() + 3 * 86_400_000); // well past 15 working minutes
    await tick(deps(), later);
    const a = await t.db.selectFrom('tasks').selectAll().where('id', '=', taskId).executeTakeFirstOrThrow();
    expect(a.escalation_level).toBeTruthy();
    expect(a.auto_escalated_at).toBeTruthy();
    await tick(deps(), new Date(later.getTime() + 3 * 86_400_000));
    expect((await t.db.selectFrom('tasks').select('head_alerted').where('id', '=', taskId).executeTakeFirstOrThrow()).head_alerted).toBe(true);
  });

  it('warns the assignee at 75% and when overdue, once each', async () => {
    const { taskId } = await newTask('riya', { user: 'dhaval' }, 'Profit NX slow', { overrides: { priority: 'Critical' } });
    await act('dhaval', taskId, 'accept');
    await tick(deps(), new Date(Date.now() + 14 * 86_400_000));
    await tick(deps(), new Date(Date.now() + 14 * 86_400_000));
    const warned = JSON.parse((await t.db.selectFrom('tasks').select('warned').where('id', '=', taskId).executeTakeFirstOrThrow()).warned);
    expect(warned).toEqual(['over']);
  });

  it('verifies itself after 2 working days and closes 3 working days later', async () => {
    const { taskId } = await newTask('riya', { user: 'dhaval' }, 'Update licence count');
    await act('dhaval', taskId, 'accept');
    await act('dhaval', taskId, 'complete', { remarks: 'Done' });
    await tick(deps(), new Date(Date.now() + 5 * 86_400_000));
    expect((await view('riya', taskId)).status).toBe('Verified');
    await tick(deps(), new Date(Date.now() + 12 * 86_400_000));
    expect((await view('riya', taskId)).status).toBe('Closed');
  });
});
