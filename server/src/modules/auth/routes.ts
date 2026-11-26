// Own-password sign-in (D7): phone + password, scrypt hashes, 5 wrong tries lock the account for 15 minutes.
// Access tokens last 15 minutes, refresh tokens 30 days. A department head (or admin) resets a forgotten password.
import { randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Db } from '../../db/client';
import { AppError, badRequest, forbidden, unauthorized } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { currentUser } from '../access';
import { leadChain, loadOrg, roleLabel, teamsLedBy } from '../org';

export const ACCESS_TTL = '15m';
export const REFRESH_TTL = '30d';
const MAX_TRIES = 5;
const LOCK_MS = 15 * 60_000;
export const PASSWORD_RULE = /^(?=.*[A-Za-z])(?=.*\d).{8,64}$/;
const scrypt = promisify(scryptCb) as (pw: string, salt: Buffer, len: number) => Promise<Buffer>;

/** Indian mobile numbers: digits only, a leading 91 or 0 dropped. */
export const normalisePhone = (v: string) => {
  const d = v.replace(/\D/g, '');
  return d.length === 12 && d.startsWith('91') ? d.slice(2) : d.length === 11 && d.startsWith('0') ? d.slice(1) : d;
};
const Phone = z.string().transform(normalisePhone).pipe(z.string().regex(/^\d{10,15}$/, 'Enter a valid mobile number.'));
const NewPassword = z.string().regex(PASSWORD_RULE, 'Use at least 8 characters with a letter and a number.');

export async function hashPassword(pw: string) {
  const salt = randomBytes(16);
  return { password_hash: await scrypt(pw, salt, 64), password_salt: salt };
}

export async function setPassword(db: Db, userId: string, pw: string) {
  await db.updateTable('users').set({ ...(await hashPassword(pw)), failed_logins: 0, locked_until: null, updated_at: new Date() }).where('id', '=', userId).execute();
}

export async function authRoutes(app: FastifyInstance) {
  const { db } = app;

  const tokens = (userId: string) => ({
    accessToken: app.jwt.sign({ sub: userId, typ: 'access' }, { expiresIn: ACCESS_TTL }),
    refreshToken: app.jwt.sign({ sub: userId, typ: 'refresh' }, { expiresIn: REFRESH_TTL }),
  });

  /** Checks the password and counts wrong tries. Throws with a message for the sign-in screen. */
  async function check(phone: string, password: string) {
    const u = await db.selectFrom('users').selectAll().where('phone', '=', phone).where('is_active', '=', true).executeTakeFirst();
    const wrong = unauthorized('Wrong number or password.');
    if (!u?.password_hash || !u.password_salt) throw wrong;
    if (u.locked_until && new Date(u.locked_until).getTime() > Date.now()) {
      const at = new Date(u.locked_until).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Kolkata' });
      throw new AppError(423, 'LOCKED', `Too many wrong tries. Try again after ${at}.`);
    }
    if (!timingSafeEqual(await scrypt(password, u.password_salt, 64), u.password_hash)) {
      const tries = u.failed_logins + 1;
      await db.updateTable('users').set({ failed_logins: tries >= MAX_TRIES ? 0 : tries, locked_until: tries >= MAX_TRIES ? new Date(Date.now() + LOCK_MS) : null })
        .where('id', '=', u.id).execute();
      throw wrong;
    }
    if (u.failed_logins) await db.updateTable('users').set({ failed_logins: 0, locked_until: null }).where('id', '=', u.id).execute();
    return u;
  }

  app.post('/auth/login', {
    config: { rateLimit: { max: 20, timeWindow: '15 minutes', keyGenerator: (req) => `login:${normalisePhone(String((req.body as { phone?: unknown })?.phone ?? ''))}` } },
  }, async (req) => {
    const { phone, password } = parse(z.object({ phone: Phone, password: z.string().min(1, 'Enter your password.').max(64) }), req.body);
    const u = await check(phone, password);
    return { ...tokens(u.id), user: publicUser(u) };
  });

  app.post('/auth/refresh', async (req) => {
    const { refreshToken } = parse(z.object({ refreshToken: z.string().min(10) }), req.body);
    let sub: string;
    try {
      const p = app.jwt.verify<{ sub: string; typ: string }>(refreshToken);
      if (p.typ !== 'refresh') throw new Error('wrong token type');
      sub = p.sub;
    } catch { throw unauthorized(); }
    const u = await db.selectFrom('users').selectAll().where('id', '=', sub).where('is_active', '=', true).executeTakeFirst();
    if (!u) throw unauthorized();
    return { ...tokens(u.id), user: publicUser(u) };
  });

  // Profile: the short role label ("ProfitNX lead") and a separate reporting manager line, as in Ornate.
  app.get('/me', { preHandler: app.authenticate }, async (req) => {
    const me = await currentUser(db, req.userId);
    const org = await loadOrg(db);
    const manager = leadChain(org, me.id)[0];
    return {
      ...publicUser(me), teamId: me.team_id, roleLabel: roleLabel(org, me.id),
      teamName: org.teams.find((t) => t.id === me.team_id)?.name ?? null,
      departmentName: org.departments.find((d) => d.id === me.department_id)?.name ?? null,
      reportingManager: manager ? org.users.find((u) => u.id === manager)?.name ?? null : null,
      leadsTeams: teamsLedBy(org, me.id),
      away: me.away,
      shift: me.shift,
    };
  });

  /** Change your own password: needs the current one. */
  app.post('/auth/password', { preHandler: app.authenticate }, async (req, reply) => {
    const { current, password } = parse(z.object({ current: z.string().min(1), password: NewPassword }), req.body);
    const me = await currentUser(db, req.userId);
    await check(me.phone, current).catch(() => { throw badRequest('Your current password is wrong.'); });
    await setPassword(db, me.id, password);
    return reply.code(204).send();
  });

  /** A department head resets the password of someone in their department; an admin, anyone's. */
  app.post('/users/:id/password', { preHandler: app.authenticate }, async (req, reply) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const { password } = parse(z.object({ password: NewPassword }), req.body);
    const me = await currentUser(db, req.userId);
    const target = await db.selectFrom('users').select(['id', 'department_id']).where('id', '=', id).executeTakeFirst();
    if (!target) throw badRequest('Person not found.');
    const allowed = me.role === 'admin' || (me.role === 'dept_head' && !!me.department_id && me.department_id === target.department_id);
    if (!allowed || target.id === me.id) throw forbidden('Only the department head or an admin can reset this password.');
    await setPassword(db, target.id, password);
    return reply.code(204).send();
  });
}

export const publicUser = (u: { id: string; name: string; role: string; department_id: string | null; avatar_url: string | null }) =>
  ({ id: u.id, name: u.name, role: u.role, departmentId: u.department_id, avatarUrl: u.avatar_url });
