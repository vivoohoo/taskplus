// Ornate look and basics (docs/ORNATE_UI.md): tab lists, chips, party grouping, timeline, private notes,
// /subtask, edit while Open, and the bell.
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { startTestApp, type TestApp } from './helpers/app';

let t: TestApp;
const P = { riya: '9800000002', karan: '9800000003', supLead: '9800000001', tushar: '9800000004', kunal: '9800000011', amit: '9800000012' };
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
const as = (k: keyof typeof P) => t.as(tok[k]!);
async function send(from: keyof typeof P, target: object, text: string, extra: object = {}) {
  const th = (await as(from).post('/v1/threads/open', target)).body.thread;
  const r = await as(from).post(`/v1/threads/${th.id}/messages`, { clientMsgId: randomUUID(), kind: 'text', bodyText: text, ...extra });
  await t.app.services.jobs.idle();
  return { threadId: th.id as string, taskId: r.body.task?.id as string, status: r.status, body: r.body };
}
const cases = async (k: keyof typeof P, q: string) => (await as(k).get(`/v1/cases?${q}`)).body;
const ticket = (body: { items: { task: { id: string }; party: { key: string; name: string } }[] }, taskId: string) => body.items.find((i) => i.task.id === taskId);

describe('tabs, chips and one chat per person', () => {
  it('My Tasks, Queue and All Cases follow Ornate rules; the chat moves under whoever holds it', async () => {
    const { taskId } = await send('riya', { targetType: 'department', targetId: dev }, 'Ornate report export is slow');
    // Sender: in My Tasks, grouped under "Development Team Leads" until accepted.
    const mine = await cases('riya', 'tab=my');
    expect(ticket(mine, taskId)?.party).toMatchObject({ key: `d:${dev}`, name: 'Development Team Leads' });
    // A Development member: waiting in the Queue, not in My Tasks.
    expect(ticket(await cases('amit', 'tab=queue'), taskId)).toBeTruthy();
    expect(ticket(await cases('amit', 'tab=my'), taskId)).toBeUndefined();
    // Support colleague: can't see it at all.
    expect(ticket(await cases('karan', 'tab=all'), taskId)).toBeUndefined();

    await as('amit').post(`/v1/tasks/${taskId}/actions/accept`);
    expect(ticket(await cases('riya', 'tab=my'), taskId)?.party).toMatchObject({ key: `u:${id('amit')}`, name: 'Amit Vora' });
    expect(ticket(await cases('amit', 'tab=my'), taskId)?.party).toMatchObject({ key: `u:${id('riya')}` });
    expect(ticket(await cases('amit', 'tab=queue'), taskId)).toBeUndefined();

    // Chips: Sent by me, Active; Verified / Closed empty for now.
    expect(ticket(await cases('riya', 'tab=my&chip=Sent%20by%20me'), taskId)).toBeTruthy();
    expect(ticket(await cases('amit', 'tab=my&chip=Sent%20by%20me'), taskId)).toBeUndefined();
    expect(ticket(await cases('riya', 'tab=all&chip=Verified%20%2F%20Closed'), taskId)).toBeUndefined();
    // Filters and search.
    expect(ticket(await cases('riya', `tab=all&owner=${id('amit')}`), taskId)).toBeTruthy();
    expect(ticket(await cases('riya', 'tab=all&q=export%20slow'), taskId)).toBeTruthy();
    expect(ticket(await cases('riya', 'tab=all&q=nothing-like-this'), taskId)).toBeUndefined();
    expect((await cases('riya', 'tab=all&q=export')).grouped).toBe(false);

    const counts = (await as('riya').get('/v1/cases/counts')).body;
    expect(counts.my).toBeGreaterThan(0);

    // Timeline: Riya's chat with Amit holds the task, then a reply.
    const threadId = (await as('riya').get(`/v1/tasks/${taskId}`)).body.message.threadId;
    await as('amit').post(`/v1/threads/${threadId}/messages`, { clientMsgId: randomUUID(), kind: 'text', bodyText: 'Looking now', replyToTaskId: taskId });
    const tl = (await as('riya').get(`/v1/timeline?party=u:${id('amit')}`)).body;
    expect(tl.party.name).toBe('Amit Vora');
    expect((await as('riya').get(`/v1/timeline?party=u:${id('amit')}&tab=queue`)).body.items).toHaveLength(0);
    expect(tl.items.map((i: { message: { bodyText: string } }) => i.message.bodyText)).toEqual(expect.arrayContaining(['Ornate report export is slow', 'Looking now']));
  });

  it('a lead sees department figures in the Queue', async () => {
    const q = await cases('tushar', 'tab=queue');
    expect(q.stats).toMatchObject({ waiting: expect.any(Number), inProgress: expect.any(Number), overdue: expect.any(Number) });
    expect((await cases('kunal', 'tab=queue')).stats).toBeNull();
  });
});

describe('private notes', () => {
  it('a chat with yourself: in progress at once, never routed, only you see it', async () => {
    const r = await send('riya', { targetType: 'self' }, 'Call Mehta Traders back on Monday');
    expect(r.body.task).toMatchObject({ status: 'InProgress', assigneeId: id('riya'), isNote: true, dueAt: null });
    expect((await as('riya').get(`/v1/tasks/${r.taskId}`)).body.task.actions).toEqual(['close', 'edit']);
    expect(ticket(await cases('riya', 'tab=my'), r.taskId)?.party.key).toBe('self');
    expect(ticket(await cases('supLead', 'tab=all'), r.taskId)).toBeUndefined();
    expect((await as('supLead').get(`/v1/tasks/${r.taskId}`)).status).toBe(403);
    expect((await as('riya').post(`/v1/tasks/${r.taskId}/actions/close`)).body.task).toMatchObject({ status: 'Closed', actions: ['reopen'] });
    expect((await as('riya').post(`/v1/tasks/${r.taskId}/actions/reopen`)).body.task.status).toBe('InProgress');
  });
});

describe('/subtask to another department', () => {
  it('parent waits until the sub-task is done; head can cancel open sub-tasks', async () => {
    const { taskId: parent } = await send('riya', { targetType: 'department', targetId: dev }, 'Customer wants Ornate on a new server');
    await as('kunal').post(`/v1/tasks/${parent}/actions/accept`);
    expect((await as('kunal').get(`/v1/tasks/${parent}`)).body.task.actions).toContain('hand_off');
    // Staff in another department can't hand off someone else's task.
    expect((await send('karan', { targetType: 'department', targetId: sup }, 'x', { parentTaskId: parent })).status).toBe(403);
    // Same department refused.
    expect((await send('kunal', { targetType: 'department', targetId: dev }, 'x', { parentTaskId: parent })).status).toBe(400);
    const sub = await send('kunal', { targetType: 'department', targetId: sup }, 'Install SQL Server on the new machine', { parentTaskId: parent });
    expect(sub.status).toBe(201);
    expect(sub.body.task.parentTaskId).toBe(parent);
    const p = (await as('kunal').get(`/v1/tasks/${parent}`)).body.task;
    expect(p.status).toBe('WaitingDept');
    expect(p.clock.state).toBe('running'); // no pauses (owner decision 27 Nov)
    expect(sub.body.task.ticketNo).toBe(`${p.ticketNo}/T2`);
    const hist = (await as('kunal').get(`/v1/tasks/${parent}/history`)).body;
    expect(hist.subTasks).toHaveLength(1);
    expect((await as('karan').get(`/v1/tasks/${sub.taskId}/history`)).body.parent.id).toBe(parent);

    await as('karan').post(`/v1/tasks/${sub.taskId}/actions/accept`);
    await as('karan').post(`/v1/tasks/${sub.taskId}/actions/complete`, { remarks: 'Installed' });
    const back = (await as('kunal').get(`/v1/tasks/${parent}`)).body.task;
    expect(back.status).toBe('InProgress');
    expect(back.clock.state).toBe('running');

    // Again, and this time the Development head finishes and drops the open sub-task.
    const sub2 = await send('kunal', { targetType: 'department', targetId: sup }, 'Back up the old server first', { parentTaskId: parent });
    expect((await as('tushar').get(`/v1/tasks/${parent}`)).body.task.actions).toContain('complete_cancel_subs');
    const done = await as('tushar').post(`/v1/tasks/${parent}/actions/complete_cancel_subs`, { remarks: 'Not needed after all' });
    expect(done.body.task?.status, JSON.stringify(done.body)).toBe('Completed');
    expect((await as('karan').get(`/v1/tasks/${sub2.taskId}`)).body.task.status).toBe('Cancelled');
  });
});

describe('edit while Open', () => {
  it.skip('(removed 27 Nov: senders get no buttons) the sender rewrites the message and the AI reads it again', async () => {
    const { taskId } = await send('riya', { targetType: 'department', targetId: dev }, 'Prnting broken');
    t.fakes.llm.answer = (i) => ({ subject: 'Edited subject', module: i.modules[0], customer_name: null, customer_phone: null, customer_location: null, license_no: null, priority: 'High', details: i.text });
    const r = await as('riya').post(`/v1/tasks/${taskId}/actions/edit`, { text: 'Printing broken at Mehta Traders, urgent' });
    expect(r.status).toBe(200);
    await t.app.services.jobs.idle();
    const after = (await as('riya').get(`/v1/tasks/${taskId}`)).body;
    expect(after.message.bodyText).toBe('Printing broken at Mehta Traders, urgent');
    expect(after.task).toMatchObject({ subject: 'Edited subject', aiStatus: 'done' });
    await as('kunal').post(`/v1/tasks/${taskId}/actions/accept`);
    expect((await as('riya').post(`/v1/tasks/${taskId}/actions/edit`, { text: 'too late' })).status).toBe(403);
  });
});

describe('the bell', () => {
  it('keeps each alert; tap marks it read; mark all read', async () => {
    const { taskId } = await send('karan', { targetType: 'user', targetId: id('riya') }, 'Please check the licence for Om Logistics');
    const n = (await as('riya').get('/v1/notifications')).body;
    const mine = n.items.find((x: { taskId: string }) => x.taskId === taskId);
    expect(mine).toMatchObject({ read: false });
    expect(n.unread).toBeGreaterThan(0);
    await as('riya').post(`/v1/notifications/${mine.id}/read`);
    expect((await as('riya').get('/v1/notifications')).body.items.find((x: { id: string }) => x.id === mine.id).read).toBe(true);
    await as('riya').post('/v1/notifications/read-all');
    expect((await as('riya').get('/v1/notifications')).body.unread).toBe(0);
    expect((await as('karan').post(`/v1/notifications/${mine.id}/read`)).status).toBe(404);
  });
});
