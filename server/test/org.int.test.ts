// Teams, team leads and the reporting line (docs/PARITY.md, step 2).
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { leadChain, loadOrg, roleLabel, teamsLedBy, type OrgSnapshot } from '../src/modules/org';
import { startTestApp, type TestApp } from './helpers/app';

let t: TestApp;
let org: OrgSnapshot;
const P = { riya: '9800000002', tushar: '9800000004', dhaval: '9800000005', vishwas: '9800000006', nisha: '9800000007', kunal: '9800000011', amit: '9800000012' };
const tok: Record<string, string> = {};
const idOf = (name: string) => org.users.find((u) => u.name === name)!.id;
const teamOf = (name: string) => org.teams.find((x) => x.name === name)!.id;

beforeAll(async () => {
  t = await startTestApp();
  for (const [k, phone] of Object.entries(P)) tok[k] = await t.token(phone);
  org = await loadOrg(t.db);
}, 240_000);
afterAll(async () => { await t?.stop(); });

describe('organisation rules', () => {
  it('follows the reporting line Vishwas -> Dhaval -> Tushar', () => {
    expect(leadChain(org, idOf('Nisha Patel')).map((id) => org.users.find((u) => u.id === id)!.name)).toEqual(['Vishwas', 'Dhaval Dalsania', 'Tushar Parmar']);
    expect(leadChain(org, idOf('Kunal Mehta')).map((id) => org.users.find((u) => u.id === id)!.name)).toEqual(['Dhaval Dalsania', 'Tushar Parmar']);
  });
  it('a lead looks after their team and the teams of leads reporting to them', () => {
    expect(teamsLedBy(org, idOf('Vishwas'))).toEqual([teamOf('PowerBI')]);
    expect(new Set(teamsLedBy(org, idOf('Dhaval Dalsania')))).toEqual(new Set([teamOf('ProfitNX'), teamOf('PowerBI')]));
    expect(teamsLedBy(org, idOf('Tushar Parmar'))).toHaveLength(3); // department head: every Development team
    expect(teamsLedBy(org, idOf('Kunal Mehta'))).toEqual([]);
  });
  it('labels roles shortly, with the reporting manager on the profile', async () => {
    expect(roleLabel(org, idOf('Dhaval Dalsania'))).toBe('ProfitNX lead');
    expect(roleLabel(org, idOf('Tushar Parmar'))).toBe('Development head');
    expect(roleLabel(org, idOf('Amit Vora'))).toBe('Ornate team');
    const me = (await t.as(tok.vishwas!).get('/v1/me')).body;
    expect(me).toMatchObject({ roleLabel: 'PowerBI lead', reportingManager: 'Dhaval Dalsania', teamName: 'PowerBI', departmentName: 'Development' });
  });
});

describe('team chats', () => {
  it('finds a team, opens one chat for it, and notifies only that team', async () => {
    const found = (await t.as(tok.riya!).get('/v1/search?q=PowerBI')).body.results;
    const team = found.find((r: { type: string }) => r.type === 'team');
    expect(team).toMatchObject({ name: 'PowerBI team', subtitle: 'Development' });
    const th = (await t.as(tok.riya!).post('/v1/threads/open', { targetType: 'team', targetId: team.id })).body.thread;
    expect(th).toMatchObject({ title: 'PowerBI team', subtitle: 'Development' });
    expect((await t.as(tok.riya!).post('/v1/threads/open', { targetType: 'team', targetId: team.id })).body.thread.id).toBe(th.id);

    for (const k of ['vishwas', 'nisha', 'kunal'] as const) await t.as(tok[k]!).post('/v1/devices', { fcmToken: `${k}-org-token`.padEnd(40, 'z'), platform: 'android' });
    const before = t.fakes.push.sent.length;
    const r = await t.as(tok.riya!).post(`/v1/threads/${th.id}/messages`, { clientMsgId: randomUUID(), kind: 'text', bodyText: 'Power BI sales report blank' });
    expect(r.body.task.departmentId).toBe(org.departments.find((d) => d.name === 'Development')!.id);
    await t.app.services.jobs.idle();
    const pushed = t.fakes.push.sent.slice(before).flatMap((x) => x.tokens);
    expect(pushed.some((x) => x.startsWith('nisha'))).toBe(true);
    expect(pushed.some((x) => x.startsWith('kunal'))).toBe(false); // ProfitNX, not PowerBI

    const pending = async (k: keyof typeof P) => (await t.as(tok[k]!).get('/v1/tasks?filter=my_pending')).body.items.map((x: { task: { id: string } }) => x.task.id);
    expect(await pending('nisha')).toContain(r.body.task.id);
    expect(await pending('dhaval')).toContain(r.body.task.id); // PowerBI's lead reports to him
    expect(await pending('kunal')).not.toContain(r.body.task.id);
  });
});

describe('reassigning along the reporting line', () => {
  it('Dhaval can move PowerBI work; Vishwas cannot move ProfitNX work', async () => {
    const dev = org.departments.find((d) => d.name === 'Development')!.id;
    const th = (await t.as(tok.riya!).post('/v1/threads/open', { targetType: 'department', targetId: dev })).body.thread;
    const send = async (text: string) => (await t.as(tok.riya!).post(`/v1/threads/${th.id}/messages`, { clientMsgId: randomUUID(), kind: 'text', bodyText: text })).body.task.id as string;

    const a = await send('ERP sync lag');
    await t.as(tok.nisha!).post(`/v1/tasks/${a}/accept`);
    const moved = await t.as(tok.dhaval!).post(`/v1/tasks/${a}/reassign`, { assigneeId: idOf('Vishwas') });
    expect(moved.status).toBe(200);
    expect(moved.body.task.assigneeId).toBe(idOf('Vishwas'));

    const b = await send('Licence screen typo');
    await t.as(tok.kunal!).post(`/v1/tasks/${b}/accept`);
    expect((await t.as(tok.vishwas!).post(`/v1/tasks/${b}/reassign`, { assigneeId: idOf('Nisha Patel') })).status).toBe(403);
    expect((await t.as(tok.dhaval!).post(`/v1/tasks/${b}/reassign`, { assigneeId: idOf('Amit Vora') })).status).toBe(400); // Amit is in Ornate, not his
    expect((await t.as(tok.tushar!).post(`/v1/tasks/${b}/reassign`, { assigneeId: idOf('Amit Vora') })).status).toBe(200); // the head can
  });
});
