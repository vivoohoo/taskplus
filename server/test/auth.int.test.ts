// Password sign-in, lock-out, refresh, change and reset, devices and /healthz against a real SQL Server.
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { startTestApp, type TestApp } from './helpers/app';
import { TEST_PASSWORD } from './helpers/db';

let t: TestApp;
let app: TestApp['app'];
beforeAll(async () => { t = await startTestApp(); app = t.app; }, 240_000);
afterAll(async () => { await t?.stop(); });

const login = (phone: string, password = TEST_PASSWORD) => request(app.server).post('/v1/auth/login').send({ phone, password });

describe('auth', () => {
  it('reports health', async () => {
    expect((await request(app.server).get('/healthz')).body).toEqual({ ok: true });
  });

  it('signs in with phone and password and returns the person', async () => {
    const r = await login('+91 98000 00002');
    expect(r.status).toBe(200);
    expect(r.body.user).toMatchObject({ name: 'Riya Shah', role: 'staff' });
    const me = await request(app.server).get('/v1/me').set('authorization', `Bearer ${r.body.accessToken}`);
    expect(me.body.name).toBe('Riya Shah');
  });

  it('gives the same answer for a wrong password and an unknown number', async () => {
    const wrong = await login('9800000002', 'nope12345');
    const unknown = await login('9811111111');
    expect(wrong.status).toBe(401);
    expect(unknown.body.error).toEqual(wrong.body.error);
  });

  it('locks the account for 15 minutes after 5 wrong tries, even for the right password', async () => {
    for (let i = 0; i < 5; i++) expect((await login('9800000009', 'wrong1234')).status).toBe(401);
    const locked = await login('9800000009');
    expect(locked.status).toBe(423);
    expect(locked.body.error.message).toMatch(/Try again after/);
    await t.db.updateTable('users').set({ locked_until: null, failed_logins: 0 }).where('phone', '=', '9800000009').execute();
  });

  it('rejects a bad body with the standard error shape', async () => {
    const r = await request(app.server).post('/v1/auth/login').send({ phone: 'abc' });
    expect(r.status).toBe(400);
    expect(r.body.error.code).toBe('BAD_REQUEST');
  });

  it('refreshes, and a refresh token cannot be used as an access token', async () => {
    const { refreshToken } = (await login('9800000002')).body;
    expect((await request(app.server).post('/v1/auth/refresh').send({ refreshToken })).body.accessToken).toBeTruthy();
    expect((await request(app.server).get('/v1/me').set('authorization', `Bearer ${refreshToken}`)).status).toBe(401);
  });

  it('changes your own password (current one needed) and lets the head reset it', async () => {
    const karan = (await login('9800000003')).body.accessToken;
    const as = (tok: string) => (url: string, body: object) => request(app.server).post(url).set('authorization', `Bearer ${tok}`).send(body);
    expect((await as(karan)('/v1/auth/password', { current: 'wrong', password: 'NewPass123' })).status).toBe(400);
    expect((await as(karan)('/v1/auth/password', { current: TEST_PASSWORD, password: 'short' })).status).toBe(400);
    expect((await as(karan)('/v1/auth/password', { current: TEST_PASSWORD, password: 'NewPass123' })).status).toBe(204);
    expect((await login('9800000003', 'NewPass123')).status).toBe(200);

    const karanId = t.ids.get('9800000003') ?? (await login('9800000003', 'NewPass123')).body.user.id;
    const supportHead = (await login('9800000001')).body.accessToken;
    const devHead = (await login('9800000004')).body.accessToken;
    expect((await as(devHead)(`/v1/users/${karanId}/password`, { password: 'Reset1234' })).status).toBe(403); // other department
    expect((await as(karan)(`/v1/users/${karanId}/password`, { password: 'Reset1234' })).status).toBe(403); // not a head
    expect((await as(supportHead)(`/v1/users/${karanId}/password`, { password: 'Reset1234' })).status).toBe(204);
    expect((await login('9800000003', 'Reset1234')).status).toBe(200);
  });

  it('registers a device token once and moves it to the latest user', async () => {
    const a = (await login('9800000002')).body;
    const b = (await login('9800000004')).body;
    const token = 'fcm-token-'.padEnd(40, 'x');
    for (const who of [a, a, b])
      expect((await request(app.server).post('/v1/devices').set('authorization', `Bearer ${who.accessToken}`).send({ fcmToken: token, platform: 'android' })).status).toBe(204);
    const rows = await t.db.selectFrom('device_tokens').select('user_id').where('fcm_token', '=', token).execute();
    expect(rows).toEqual([{ user_id: b.user.id }]);
  });
});
