// Sign-in, refresh, devices and /healthz against a real SQL Server.
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { startTestApp, type TestApp } from './helpers/app';

let t: TestApp;
let app: TestApp['app'];
let ctx: { db: TestApp['db'] };

beforeAll(async () => { t = await startTestApp(); app = t.app; ctx = t; }, 240_000);
afterAll(async () => { await t?.stop(); });

const signIn = async (phone = '9800000002') =>
  (await request(app.server).post('/v1/auth/otp/verify').send({ phone, code: '123456' })).body;

describe('auth', () => {
  it('reports health', async () => {
    expect((await request(app.server).get('/healthz')).body).toEqual({ ok: true });
  });

  it('signs in with the dev OTP and returns the person', async () => {
    expect((await request(app.server).post('/v1/auth/otp/request').send({ phone: '+91 98000 00002' })).body).toEqual({ sent: true });
    const body = await signIn('+91 98000 00002');
    expect(body.user).toMatchObject({ name: 'Riya Shah', role: 'staff' });
    expect(body.accessToken).toBeTruthy();
    const me = await request(app.server).get('/v1/me').set('authorization', `Bearer ${body.accessToken}`);
    expect(me.body.name).toBe('Riya Shah');
  });

  it('refuses a wrong code or an unknown number with the same message', async () => {
    const wrong = await request(app.server).post('/v1/auth/otp/verify').send({ phone: '9800000002', code: '000000' });
    const unknown = await request(app.server).post('/v1/auth/otp/verify').send({ phone: '9811111111', code: '123456' });
    expect(wrong.status).toBe(401);
    expect(unknown.body.error).toEqual(wrong.body.error);
  });

  it('rejects a bad body with the standard error shape', async () => {
    const r = await request(app.server).post('/v1/auth/otp/verify').send({ phone: 'abc' });
    expect(r.status).toBe(400);
    expect(r.body.error.code).toBe('BAD_REQUEST');
  });

  it('refreshes, and a refresh token cannot be used as an access token', async () => {
    const { refreshToken } = await signIn();
    const r = await request(app.server).post('/v1/auth/refresh').send({ refreshToken });
    expect(r.body.accessToken).toBeTruthy();
    expect((await request(app.server).get('/v1/me').set('authorization', `Bearer ${refreshToken}`)).status).toBe(401);
  });

  it('limits OTP requests to 10 an hour per phone', async () => {
    const phone = '9800000003';
    const codes: number[] = [];
    for (let i = 0; i < 11; i++) codes.push((await request(app.server).post('/v1/auth/otp/request').send({ phone })).status);
    expect(codes.slice(0, 10).every((c) => c === 200)).toBe(true);
    expect(codes[10]).toBe(429);
  });

  it('registers a device token once and moves it to the latest user', async () => {
    const a = await signIn('9800000002');
    const b = await signIn('9800000004');
    const token = 'fcm-token-'.padEnd(40, 'x');
    for (const who of [a, a, b])
      expect((await request(app.server).post('/v1/devices').set('authorization', `Bearer ${who.accessToken}`).send({ fcmToken: token, platform: 'android' })).status).toBe(204);
    const rows = await ctx.db.selectFrom('device_tokens').select('user_id').where('fcm_token', '=', token).execute();
    expect(rows).toEqual([{ user_id: b.user.id }]);
  });
});
