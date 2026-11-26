// Step 4: ticket numbers, away cover, shifts, muted alerts, holidays, suggestions, customers, history, search, Team screen.
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { startTestApp, type TestApp } from './helpers/app';

let t: TestApp;
const P = { riya: '9800000002', tushar: '9800000004', dhaval: '9800000005', vishwas: '9800000006', nisha: '9800000007', kunal: '9800000011' };
const tok: Record<string, string> = {};
let dev = '';
beforeAll(async () => {
  t = await startTestApp();
  for (const [k, phone] of Object.entries(P)) tok[k] = await t.token(phone);
  dev = (await t.db.selectFrom('departments').select('id').where('name', '=', 'Development').executeTakeFirstOrThrow()).id;
}, 240_000);
afterAll(async () => { await t?.stop(); });
const id = (k: keyof typeof P) => t.ids.get(P[k])!;
const send = async (from: keyof typeof P, text: string, extra: object = {}) => {
  const th = (await t.as(tok[from]!).post('/v1/threads/open', { targetType: 'department', targetId: dev })).body.thread;
  const r = await t.as(tok[from]!).post(`/v1/threads/${th.id}/messages`, { clientMsgId: randomUUID(), kind: 'text', bodyText: text, ...extra });
  await t.app.services.jobs.idle();
  return r.body.task;
};

describe('people and views', () => {
  it('numbers tasks ORN-SS-yyyy-00001 upward', async () => {
    const a = await send('riya', 'First'), b = await send('riya', 'Second');
    expect(a.ticketNo).toMatch(/^ORN-SS-\d{4}-\d{5}$/);
    expect(Number(b.ticketNo.slice(-5))).toBe(Number(a.ticketNo.slice(-5)) + 1);
  });

  it('away: a task tagged to someone away goes to their team instead', async () => {
    await t.as(tok.nisha!).put('/v1/me/away', { away: true });
    for (const k of ['nisha', 'vishwas'] as const) await t.as(tok[k]!).post('/v1/devices', { fcmToken: `${k}-away-token`.padEnd(40, 'a'), platform: 'android' });
    const before = t.fakes.push.sent.length;
    await send('riya', 'Check the PowerBI gateway', { taggedUserId: id('nisha') });
    const tokens = t.fakes.push.sent.slice(before).flatMap((x) => x.tokens);
    expect(tokens.some((x) => x.startsWith('vishwas'))).toBe(true);
    expect(tokens.some((x) => x.startsWith('nisha'))).toBe(false);
    await t.as(tok.nisha!).put('/v1/me/away', { away: false });
  });

  it('shifts: your own, and a lead sets their team\'s', async () => {
    expect((await t.as(tok.kunal!).put('/v1/me/shift', { shift: 1 })).body.shift).toBe(1);
    expect((await t.as(tok.dhaval!).put(`/v1/users/${id('kunal')}/shift`, { shift: 2 })).status).toBe(200);
    expect((await t.as(tok.vishwas!).put(`/v1/users/${id('kunal')}/shift`, { shift: 0 })).status).toBe(403);
  });

  it('muted alerts: optional kinds only', async () => {
    const r = await t.as(tok.kunal!).put('/v1/me/notifications', { muted: ['deadline', 'new'] });
    expect(r.body.muted).toEqual(['deadline']); // "new" is a must-have
  });

  it('holidays: heads edit; the clock reads them', async () => {
    expect((await t.as(tok.kunal!).post('/v1/holidays', { day: '2027-03-14', name: 'Holi' })).status).toBe(403);
    expect((await t.as(tok.tushar!).post('/v1/holidays', { day: '2027-03-14', name: 'Holi' })).status).toBe(200);
    expect((await t.as(tok.kunal!).get('/v1/holidays')).body.holidays.map((h: { day: string }) => h.day)).toContain('2027-03-14');
  });

  it('suggestions: everyone writes, heads review', async () => {
    const s = await t.as(tok.kunal!).post('/v1/suggestions', { text: 'Let me attach Excel files too' });
    expect((await t.as(tok.kunal!).put(`/v1/suggestions/${s.body.id}`, { status: 'Planned' })).status).toBe(403);
    expect((await t.as(tok.tushar!).put(`/v1/suggestions/${s.body.id}`, { status: 'Planned' })).body.status).toBe('Planned');
    expect((await t.as(tok.tushar!).get('/v1/suggestions')).body.canReview).toBe(true);
  });

  it('customers list, history and search', async () => {
    expect((await t.as(tok.riya!).get('/v1/customers')).body.customers.map((c: { name: string }) => c.name)).toContain('Mehta Traders');
    const task = await send('riya', 'Mehta Traders printer stuck');
    await t.as(tok.kunal!).post(`/v1/tasks/${task.id}/actions/accept`);
    const h = (await t.as(tok.riya!).get(`/v1/tasks/${task.id}/history`)).body;
    expect(h.events.map((e: { type: string }) => e.type)).toEqual(expect.arrayContaining(['created', 'structured', 'accepted']));
    expect(h.events.find((e: { type: string }) => e.type === 'accepted').by).toBe('Kunal Mehta');
    const found = (await t.as(tok.riya!).get(`/v1/tasks/search?q=${encodeURIComponent(task.ticketNo)}`)).body.items;
    expect(found.map((x: { task: { id: string } }) => x.task.id)).toContain(task.id);
  });

  it('Team screen: leads only, scoped to the teams they look after', async () => {
    expect((await t.as(tok.kunal!).get('/v1/analytics/team')).status).toBe(403);
    const v = (await t.as(tok.vishwas!).get('/v1/analytics/team')).body;
    expect(v.scope).toBe('PowerBI team');
    expect(v.people.map((p: { name: string }) => p.name).sort()).toEqual(['Nisha Patel', 'Vishwas']);
    const h = (await t.as(tok.tushar!).get('/v1/analytics/team')).body;
    expect(h.scope).toBe('Development department');
    expect(h.teams.map((x: { team: string }) => x.team).sort()).toEqual(['Ornate', 'PowerBI', 'ProfitNX']);
    expect(h.byPriority).toHaveLength(4);
  });
});
