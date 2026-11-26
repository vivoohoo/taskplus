// Phone + OTP sign-in. Prototype: the OTP is DEV_FIXED_OTP.
// TODO(D7): replace sendOtp/checkOtp with the existing Task Plus auth once its source is confirmed.
import { timingSafeEqual } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { AppError, unauthorized } from '../../lib/errors';
import { parse } from '../../lib/validate';

export const ACCESS_TTL = '15m';
export const REFRESH_TTL = '30d';

/** Indian mobile numbers: digits only, a leading 91 or 0 dropped. */
export const normalisePhone = (v: string) => {
  const d = v.replace(/\D/g, '');
  return d.length === 12 && d.startsWith('91') ? d.slice(2) : d.length === 11 && d.startsWith('0') ? d.slice(1) : d;
};
const Phone = z.string().transform(normalisePhone).pipe(z.string().regex(/^\d{10,15}$/, 'Enter a valid mobile number.'));

export async function authRoutes(app: FastifyInstance) {
  const { env, db } = app;

  const checkOtp = (code: string) => {
    if (!env.DEV_FIXED_OTP) throw new AppError(501, 'OTP_NOT_CONFIGURED', 'Sign-in is not connected yet.');
    const a = Buffer.from(code.padEnd(6)), b = Buffer.from(env.DEV_FIXED_OTP);
    return a.length === b.length && timingSafeEqual(a, b);
  };

  const tokens = (userId: string) => ({
    accessToken: app.jwt.sign({ sub: userId, typ: 'access' }, { expiresIn: ACCESS_TTL }),
    refreshToken: app.jwt.sign({ sub: userId, typ: 'refresh' }, { expiresIn: REFRESH_TTL }),
  });

  const activeUser = (where: { phone?: string; id?: string }) => {
    let q = db.selectFrom('users').selectAll().where('is_active', '=', true);
    if (where.phone) q = q.where('phone', '=', where.phone);
    if (where.id) q = q.where('id', '=', where.id);
    return q.executeTakeFirst();
  };

  app.post('/auth/otp/request', {
    config: { rateLimit: { max: 10, timeWindow: '1 hour', keyGenerator: (req) => `otp:${normalisePhone(String((req.body as { phone?: unknown })?.phone ?? ''))}` } },
  }, async (req) => {
    const { phone } = parse(z.object({ phone: Phone }), req.body);
    if (!env.DEV_FIXED_OTP) throw new AppError(501, 'OTP_NOT_CONFIGURED', 'Sign-in is not connected yet.');
    req.log.info({ phone }, 'otp requested');
    // Same answer whether or not the number belongs to someone, so numbers can't be probed.
    return { sent: true };
  });

  app.post('/auth/otp/verify', {
    config: { rateLimit: { max: 10, timeWindow: '15 minutes', keyGenerator: (req) => `verify:${normalisePhone(String((req.body as { phone?: unknown })?.phone ?? ''))}` } },
  }, async (req) => {
    const { phone, code } = parse(z.object({ phone: Phone, code: z.string().regex(/^\d{6}$/, 'Enter the 6-digit code.') }), req.body);
    const user = await activeUser({ phone });
    if (!checkOtp(code) || !user) throw unauthorized('Wrong number or code.');
    return { ...tokens(user.id), user: publicUser(user) };
  });

  app.post('/auth/refresh', async (req) => {
    const { refreshToken } = parse(z.object({ refreshToken: z.string().min(10) }), req.body);
    let sub: string;
    try {
      const p = app.jwt.verify<{ sub: string; typ: string }>(refreshToken);
      if (p.typ !== 'refresh') throw new Error('wrong token type');
      sub = p.sub;
    } catch { throw unauthorized(); }
    const user = await activeUser({ id: sub });
    if (!user) throw unauthorized();
    return { ...tokens(user.id), user: publicUser(user) };
  });

  app.get('/me', { preHandler: app.authenticate }, async (req) => publicUser((await activeUser({ id: req.userId }))!));
}

export const publicUser = (u: { id: string; name: string; role: string; department_id: string | null; avatar_url: string | null }) =>
  ({ id: u.id, name: u.name, role: u.role, departmentId: u.department_id, avatarUrl: u.avatar_url });
