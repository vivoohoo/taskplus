// Spec §11 flows end to end against SQL Server, with fake AI / speech / storage / push.
import { randomUUID } from 'node:crypto';
import { io as connect, type Socket } from 'socket.io-client';
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { startTestApp, type TestApp } from './helpers/app';

let t: TestApp;
let port: number;
const tok: Record<string, string> = {};
// Seeded people (db/seed.ts)
const P = { supLead: '9800000001', riya: '9800000002', karan: '9800000003', tushar: '9800000004', dhaval: '9800000005', vishwas: '9800000006', priya: '9800000009' };

beforeAll(async () => {
  t = await startTestApp();
  await t.app.listen({ port: 0, host: '127.0.0.1' });
  port = (t.app.server.address() as { port: number }).port;
  for (const [k, phone] of Object.entries(P)) tok[k] = await t.token(phone);
}, 240_000);
afterAll(async () => { await t?.stop(); });
beforeEach(() => { t.fakes.llm.failing = false; t.fakes.stt.failing = false; t.fakes.llm.answer = new (t.fakes.llm.constructor as never as new () => typeof t.fakes.llm)().answer; });

const id = (who: keyof typeof P) => t.ids.get(P[who])!;
const dept = async (name: string) => (await t.db.selectFrom('departments').select('id').where('name', '=', name).executeTakeFirstOrThrow()).id;
const openDept = async (who: keyof typeof P, name: string) => (await t.as(tok[who]!).post('/v1/threads/open', { targetType: 'department', targetId: await dept(name) })).body.thread;
const openUser = async (who: keyof typeof P, other: keyof typeof P) => (await t.as(tok[who]!).post('/v1/threads/open', { targetType: 'user', targetId: id(other) })).body.thread;
const send = (who: keyof typeof P, threadId: string, body: Record<string, unknown>) =>
  t.as(tok[who]!).post(`/v1/threads/${threadId}/messages`, { clientMsgId: randomUUID(), kind: 'text', ...body });
const socket = (who: keyof typeof P) => new Promise<Socket>((resolve, reject) => {
  const s = connect(`http://127.0.0.1:${port}`, { auth: { token: tok[who] }, transports: ['websocket'], forceNew: true });
  s.on('connect', () => resolve(s)); s.on('connect_error', reject);
});
const next = (s: Socket, event: string) => new Promise<any>((resolve) => s.once(event, resolve)); // eslint-disable-line @typescript-eslint/no-explicit-any

describe('search and threads', () => {
  it('finds people and departments, and opening twice gives one thread', async () => {
    const r = await t.as(tok.riya!).get('/v1/search?q=dha');
    expect(r.body.results.map((x: { name: string }) => x.name)).toContain('Dhaval Dalsania');
    const a = await openUser('riya', 'dhaval'), b = await openUser('dhaval', 'riya');
    expect(a.id).toBe(b.id);
    const [d1, d2] = await Promise.all([openDept('riya', 'Development'), openDept('riya', 'Development')]);
    expect(d1.id).toBe(d2.id);
    expect(d1.title).toBe('Development');
  });

  it('keeps chats private', async () => {
    const th = await openUser('riya', 'dhaval');
    expect((await t.as(tok.priya!).get(`/v1/threads/${th.id}/messages`)).status).toBe(403);
    expect((await send('priya', th.id, { bodyText: 'hi' })).status).toBe(403);
  });

  it('shows a department chat to the requester as the department, and to members as the requester', async () => {
    const th = await openDept('priya', 'Development');
    await send('priya', th.id, { bodyText: 'Please add a demo licence for Kaveri Steel' });
    const dev = (await t.as(tok.vishwas!).get('/v1/threads')).body.threads.find((x: { id: string }) => x.id === th.id);
    expect(dev).toMatchObject({ title: 'Priya Nair', subtitle: 'To Development' });
  });
});

describe('departments', () => {
  it('lists members and modules', async () => {
    const d = (await t.as(tok.riya!).get(`/v1/departments/${await dept('Support')}`)).body;
    expect(d.modules).toContain('Printing');
    expect(d.members.map((m: { name: string }) => m.name)).toEqual(['Karan Patel', 'Riya Shah', 'Support Lead']);
    expect(d.headUserId).toBe(id('supLead'));
  });
});

describe('Flow A: text task', () => {
  it('saves at once, is idempotent, and structures in the background', async () => {
    const th = await openDept('riya', 'Development');
    const clientMsgId = randomUUID();
    const body = { clientMsgId, kind: 'text', bodyText: 'Urgent: Profit NX login failing for Mehta Traders, call 98250 12345' };
    const first = await t.as(tok.riya!).post(`/v1/threads/${th.id}/messages`, body);
    expect(first.status).toBe(201);
    expect(first.body.task.aiStatus).toBe('pending');
    const again = await t.as(tok.riya!).post(`/v1/threads/${th.id}/messages`, body);
    expect(again.status).toBe(200);
    expect(again.body.message.id).toBe(first.body.message.id);
    expect(again.body.task.id).toBe(first.body.task.id);

    await t.app.services.jobs.idle();
    const page = await t.as(tok.vishwas!).get(`/v1/threads/${th.id}/messages`);
    const task = page.body.items.find((x: { message: { id: string } }) => x.message.id === first.body.message.id).task;
    expect(task).toMatchObject({ aiStatus: 'done', subject: 'Test Task', module: 'Profit NX' });
    expect(t.fakes.llm.calls.at(-1)!.text).toContain('Mehta Traders');
  });

  it('lets slash-command values win over the AI, and checks phones and licences', async () => {
    t.fakes.llm.answer = () => ({ subject: 'Licence Renewal', module: 'Ornate', customer_name: 'Kaveri Steel', customer_phone: '+91 98765-43210',
      customer_location: null, license_no: ' lic-77 ', priority: 'Low', details: 'Renew it.' });
    const th = await openDept('riya', 'Development');
    const r = await send('riya', th.id, { bodyText: 'renew licence', overrides: { priority: 'High', module: 'Power BI' } });
    await t.app.services.jobs.idle();
    const task = (await t.as(tok.riya!).get(`/v1/threads/${th.id}/messages`)).body.items.find((x: { task: { id: string } }) => x.task.id === r.body.task.id).task;
    expect(task).toMatchObject({ priority: 'High', module: 'Power BI', customerPhone: '9876543210', licenseNo: 'LIC-77', customerName: 'Kaveri Steel' });
    // High priority: due 4 hours after it was sent
    expect(Math.abs(new Date(task.dueAt).getTime() - new Date(task.createdAt).getTime() - 4 * 3600_000)).toBeLessThan(5); // SQL Server rounds to ~1 ms
  });

  it('marks the task "needs review" when AI is down, and still notifies', async () => {
    t.fakes.llm.failing = true;
    const before = t.fakes.push.sent.length;
    await t.as(tok.dhaval!).post('/v1/devices', { fcmToken: 'dhaval-phone-token-'.padEnd(40, 'x'), platform: 'android' });
    const th = await openUser('riya', 'dhaval');
    const r = await send('riya', th.id, { bodyText: 'printer not working' });
    await t.app.services.jobs.idle();
    const task = await t.db.selectFrom('tasks').selectAll().where('id', '=', r.body.task.id).executeTakeFirstOrThrow();
    expect(task.ai_status).toBe('needs_review');
    expect(task.ai_error).toMatch(/AI unavailable/);
    expect(t.fakes.push.sent.length).toBeGreaterThan(before);
    expect(t.fakes.push.sent.at(-1)!.msg.body).toContain('printer not working');
  });

  it('sends live events to the other side', async () => {
    const th = await openUser('riya', 'dhaval');
    const s = await socket('dhaval');
    try {
      const created = next(s, 'message.created'), structured = next(s, 'task.structured');
      await send('riya', th.id, { bodyText: 'SQL install needed at the Surat office' });
      expect((await created).message.bodyText).toBe('SQL install needed at the Surat office');
      expect((await structured).task.aiStatus).toBe('done');
    } finally { s.disconnect(); }
  });

  it('pages history oldest-first with a cursor', async () => {
    const th = await openUser('karan', 'priya');
    for (let i = 1; i <= 5; i++) await send('karan', th.id, { bodyText: `message ${i}` });
    const p1 = await t.as(tok.priya!).get(`/v1/threads/${th.id}/messages?limit=3`);
    expect(p1.body.items.map((x: { message: { bodyText: string } }) => x.message.bodyText)).toEqual(['message 3', 'message 4', 'message 5']);
    const p2 = await t.as(tok.priya!).get(`/v1/threads/${th.id}/messages?limit=3&before=${p1.body.nextCursor}`);
    expect(p2.body.items.map((x: { message: { bodyText: string } }) => x.message.bodyText)).toEqual(['message 1', 'message 2']);
    expect(p2.body.nextCursor).toBeNull();
  });
});

describe('Flow B: voice note', () => {
  it('uploads straight to storage, transcribes, then structures', async () => {
    const th = await openUser('riya', 'dhaval');
    const audio = Buffer.from('OggS fake opus bytes');
    const pre = await t.as(tok.riya!).post('/v1/uploads/presign', { threadId: th.id, mime: 'audio/ogg', sizeBytes: audio.length, purpose: 'audio' });
    expect(pre.status).toBe(200);
    expect(pre.body.key).toMatch(/^direct\/\d{4}\/\d{2}\/.+\.ogg$/);
    expect((await request(t.app.server).put(new URL(pre.body.url).pathname).set('content-type', 'audio/ogg').send(audio)).status).toBe(200);

    const r = await send('riya', th.id, { kind: 'voice', audioKey: pre.body.key, audioDurationS: 12 });
    expect(r.status).toBe(201);
    await t.app.services.jobs.idle();
    const m = await t.db.selectFrom('messages').select('transcript').where('id', '=', r.body.message.id).executeTakeFirstOrThrow();
    expect(m.transcript).toContain('Profit NX');
    expect(t.fakes.llm.calls.at(-1)!.text).toBe(m.transcript);
    const url = await t.as(tok.dhaval!).get(`/v1/files/url?key=${encodeURIComponent(pre.body.key)}`);
    expect(url.status).toBe(200);
    expect((await t.as(tok.priya!).get(`/v1/files/url?key=${encodeURIComponent(pre.body.key)}`)).status).toBe(403);
  });

  it('refuses disallowed types, big files and files from another chat', async () => {
    const th = await openUser('riya', 'dhaval');
    expect((await t.as(tok.riya!).post('/v1/uploads/presign', { threadId: th.id, mime: 'application/x-msdownload', sizeBytes: 10, purpose: 'attachment' })).status).toBe(400);
    expect((await t.as(tok.riya!).post('/v1/uploads/presign', { threadId: th.id, mime: 'image/png', sizeBytes: 11 * 1024 * 1024, purpose: 'attachment' })).status).toBe(400);
    const deptTh = await openDept('riya', 'Sales');
    const pre = await t.as(tok.riya!).post('/v1/uploads/presign', { threadId: deptTh.id, mime: 'image/png', sizeBytes: 3, purpose: 'attachment' });
    await request(t.app.server).put(new URL(pre.body.url).pathname).set('content-type', 'image/png').send(Buffer.from('png'));
    expect((await send('riya', th.id, { kind: 'attachment', attachmentKeys: [pre.body.key] })).status).toBe(400);
  });

  it('marks the task "needs review" when transcription keeps failing', async () => {
    t.fakes.stt.failing = true;
    const th = await openUser('riya', 'dhaval');
    const pre = await t.as(tok.riya!).post('/v1/uploads/presign', { threadId: th.id, mime: 'audio/ogg', sizeBytes: 4, purpose: 'audio' });
    await request(t.app.server).put(new URL(pre.body.url).pathname).set('content-type', 'audio/ogg').send(Buffer.from('OggS'));
    const r = await send('riya', th.id, { kind: 'voice', audioKey: pre.body.key, audioDurationS: 3 });
    await t.app.services.jobs.idle();
    const task = await t.db.selectFrom('tasks').select(['ai_status', 'ai_error']).where('id', '=', r.body.task.id).executeTakeFirstOrThrow();
    expect(task).toMatchObject({ ai_status: 'needs_review' });
    expect(task.ai_error).toMatch(/Could not transcribe/);
  });
});

describe('Flow C: accept, reassign, status', () => {
  it('lets only one of two people accept at the same time', async () => {
    const th = await openDept('riya', 'Development');
    const r = await send('riya', th.id, { bodyText: 'Mobile app crashes on login' });
    const [a, b] = await Promise.all([t.as(tok.dhaval!).post(`/v1/tasks/${r.body.task.id}/accept`), t.as(tok.vishwas!).post(`/v1/tasks/${r.body.task.id}/accept`)]);
    expect([a.status, b.status].sort()).toEqual([200, 409]);
    const loser = a.status === 409 ? a : b;
    expect(loser.body.error.code).toBe('ALREADY_ACCEPTED');
    expect(loser.body.error.details.acceptedBy.name).toMatch(/Dhaval|Vishwas/);
  });

  it('refuses accept by the sender or someone outside the department', async () => {
    const th = await openDept('riya', 'Development');
    const r = await send('riya', th.id, { bodyText: 'Report export broken' });
    expect((await t.as(tok.riya!).post(`/v1/tasks/${r.body.task.id}/accept`)).status).toBe(403);
    expect((await t.as(tok.priya!).post(`/v1/tasks/${r.body.task.id}/accept`)).status).toBe(403);
  });

  it('head reassigns inside the department; assignee moves it to In progress and Closed', async () => {
    const th = await openDept('riya', 'Development');
    const r = await send('riya', th.id, { bodyText: 'Power BI dashboard totals wrong' });
    const taskId = r.body.task.id;
    await t.as(tok.dhaval!).post(`/v1/tasks/${taskId}/accept`);
    expect((await t.as(tok.vishwas!).post(`/v1/tasks/${taskId}/reassign`, { assigneeId: id('vishwas') })).status).toBe(403); // not head, not assignee
    expect((await t.as(tok.tushar!).post(`/v1/tasks/${taskId}/reassign`, { assigneeId: id('priya') })).status).toBe(400); // other department
    const re = await t.as(tok.tushar!).post(`/v1/tasks/${taskId}/reassign`, { assigneeId: id('vishwas') });
    expect(re.body.task).toMatchObject({ assigneeId: id('vishwas'), status: 'Accepted' });
    expect((await t.as(tok.dhaval!).post(`/v1/tasks/${taskId}/status`, { status: 'InProgress' })).status).toBe(403);
    expect((await t.as(tok.vishwas!).post(`/v1/tasks/${taskId}/status`, { status: 'InProgress' })).body.task.status).toBe('InProgress');
    const closed = await t.as(tok.vishwas!).post(`/v1/tasks/${taskId}/status`, { status: 'Closed' });
    expect(closed.body.task.closedAt).toBeTruthy();
    expect((await t.as(tok.vishwas!).post(`/v1/tasks/${taskId}/status`, { status: 'InProgress' })).status).toBe(400);
    const events = await t.db.selectFrom('task_events').select('type').where('task_id', '=', taskId).orderBy('created_at').execute();
    expect(events.map((e) => e.type)).toEqual(expect.arrayContaining(['created', 'structured', 'accepted', 'reassigned', 'status_changed', 'closed']));
  });

  it('pushes a tagged department task to the tagged person and the head only (D3)', async () => {
    await t.as(tok.vishwas!).post('/v1/devices', { fcmToken: 'vishwas-token-'.padEnd(40, 'v'), platform: 'android' });
    await t.as(tok.tushar!).post('/v1/devices', { fcmToken: 'tushar-token-'.padEnd(40, 't'), platform: 'android' });
    await t.as(tok.dhaval!).post('/v1/devices', { fcmToken: 'dhaval-token2-'.padEnd(40, 'd'), platform: 'android' });
    const th = await openDept('riya', 'Development');
    const before = t.fakes.push.sent.length;
    await send('riya', th.id, { bodyText: 'Check the ERP sync', taggedUserId: id('vishwas') });
    await t.app.services.jobs.idle();
    const tokens = t.fakes.push.sent.slice(before).flatMap((x) => x.tokens);
    expect(tokens.some((x) => x.startsWith('vishwas'))).toBe(true);
    expect(tokens.some((x) => x.startsWith('tushar'))).toBe(true);
    expect(tokens.some((x) => x.startsWith('dhaval'))).toBe(false);
  });
});

describe('Flow D: filters', () => {
  it('my pending, overdue and closed', async () => {
    const th = await openUser('karan', 'supLead');
    const r = await send('karan', th.id, { bodyText: 'Licence key not activating' });
    await t.app.services.jobs.idle();
    const pend = await t.as(tok.supLead!).get('/v1/tasks?filter=my_pending');
    expect(pend.body.items.map((x: { task: { id: string } }) => x.task.id)).toContain(r.body.task.id);
    // Make it overdue
    await t.db.updateTable('tasks').set({ due_at: new Date(Date.now() - 60_000) }).where('id', '=', r.body.task.id).execute();
    expect((await t.as(tok.supLead!).get('/v1/tasks?filter=overdue')).body.items.map((x: { task: { id: string } }) => x.task.id)).toContain(r.body.task.id);
    const counts = (await t.as(tok.supLead!).get('/v1/tasks/counts')).body;
    expect(counts.overdue).toBeGreaterThan(0);
    await t.as(tok.supLead!).post(`/v1/tasks/${r.body.task.id}/accept`);
    await t.as(tok.supLead!).post(`/v1/tasks/${r.body.task.id}/status`, { status: 'Closed' });
    expect((await t.as(tok.karan!).get('/v1/tasks?filter=closed')).body.items[0].task.id).toBe(r.body.task.id);
    expect((await t.as(tok.supLead!).get('/v1/tasks?filter=my_pending')).body.items.map((x: { task: { id: string } }) => x.task.id)).not.toContain(r.body.task.id);
  });
});

describe('limits', () => {
  it('caps messages at 30 a minute per person', async () => {
    const th = await openUser('tushar', 'karan'); // Tushar has sent nothing earlier in this file
    const codes: number[] = [];
    for (let i = 0; i < 31; i++) codes.push((await send('tushar', th.id, { bodyText: `spam ${i}` })).status);
    expect(codes.filter((c) => c === 201)).toHaveLength(30);
    expect(codes.at(-1)).toBe(429);
  });

  it('refuses text over 4,000 characters and voice over 180 s', async () => {
    const th = await openUser('karan', 'riya');
    expect((await send('karan', th.id, { bodyText: 'x'.repeat(4001) })).status).toBe(400);
    expect((await send('karan', th.id, { kind: 'voice', audioKey: 'direct/2026/11/00000000-0000-0000-0000-000000000000.ogg', audioDurationS: 181 })).status).toBe(400);
  });

  it('serves readiness and metrics', async () => {
    expect((await request(t.app.server).get('/readyz')).body).toEqual({ ok: true, checks: { database: true } });
    expect((await request(t.app.server).get('/metrics')).text).toContain('ai_jobs_total');
  });
});
