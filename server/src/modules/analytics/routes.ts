// Leads' Team screen (Ornate's Team performance, docs/PARITY.md step 4). Team leads see the teams they look after;
// department heads see the whole department, with the teams side by side.
import type { FastifyInstance } from 'fastify';
import { forbidden } from '../../lib/errors';
import { loadHolidays } from '../../workflow/clock';
import { LIMITS, workMs } from '../../workflow/time';
import { currentUser } from '../access';
import { loadOrg, roleLabel, teamsLedBy } from '../org';

const DAY = 86_400_000, WEEK = 7 * DAY;
const OPEN = ['Open', 'Accepted', 'InProgress', 'WaitingInfo', 'Blocked'];
const ACTIVE = ['Accepted', 'InProgress', 'WaitingInfo', 'Blocked'];
const DONE = ['Completed', 'Verified', 'Closed'];
const avg = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);
const norm = (s: string | null) => (s ?? '').toLowerCase().replace(/[^a-z0-9ऀ-૿]+/g, ' ').trim();

export async function analyticsRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);
  const { db } = app;

  app.get('/analytics/team', async (req) => {
    const me = await currentUser(db, req.userId);
    const org = await loadOrg(db);
    const teams = teamsLedBy(org, me.id);
    if (!teams.length) throw forbidden('The Team screen is for team leads and department heads.');
    const head = me.role === 'dept_head';
    const now = Date.now(), from = now - 2 * WEEK;
    const holidays = await loadHolidays(db);

    const deptUsers = org.users.filter((u) => u.department_id === me.department_id).map((u) => u.id);
    const tasks = (await db.selectFrom('tasks').innerJoin('messages', 'messages.id', 'tasks.message_id').innerJoin('threads', 'threads.id', 'tasks.thread_id')
      .selectAll('tasks').select(['messages.sender_id as senderId', 'threads.type as threadType'])
      // Department tasks, plus person-to-person tasks held by someone in the department (counted only, see `rows`).
      .where((eb) => eb.or([eb('tasks.department_id', '=', me.department_id), eb.and([eb('threads.type', '=', 'direct'),
        ...(deptUsers.length ? [eb('tasks.assignee_id', 'in', deptUsers)] : [eb.val(false)])])]))
      .execute())
      .filter((t) => head || (t.team_id && teams.includes(t.team_id)) || (t.assignee_id && teams.includes(org.users.find((u) => u.id === t.assignee_id)?.team_id ?? '')));
    // Owner decision 28 Nov: leads see person-to-person tasks only as numbers, never as a row with its subject.
    const rows = tasks.filter((t) => t.threadType !== 'direct');
    const people = org.users.filter((u) => u.is_active && u.department_id === me.department_id && u.team_id && teams.includes(u.team_id));
    const ids = tasks.map((t) => t.id);
    const events = ids.length ? await db.selectFrom('task_events').select(['task_id', 'type', 'payload', 'actor_id', 'created_at'])
      .where('task_id', 'in', ids).where('created_at', '>=', new Date(from)).execute() : [];
    const shifts = new Map((await db.selectFrom('users').select(['id', 'shift', 'away']).execute()).map((u) => [u.id, u]));

    const usedMs = (t: (typeof tasks)[number]) => Number(t.clock_used_ms) + Number(t.used_before_transfer ?? 0);
    const onTime = (ts: typeof tasks) => (ts.length ? ts.filter((t) => usedMs(t) <= LIMITS[t.priority].completeMs).length / ts.length : null);
    const doneIn = (a: number, b: number) => tasks.filter((t) => DONE.includes(t.status) && t.completed_at && +new Date(t.completed_at) >= a && +new Date(t.completed_at) < b);
    const overdue = (t: (typeof tasks)[number]) => OPEN.includes(t.status) && +new Date(t.due_at) < now;
    const done2w = doneIn(from, now + 1);
    const monthStart = (() => { const d = new Date(now + 5.5 * 3600_000); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) - 5.5 * 3600_000; })();
    const prevStart = (() => { const d = new Date(monthStart + 5.5 * 3600_000); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - 1, 1) - 5.5 * 3600_000; })();
    const summary = (ts: typeof tasks) => ({ done: ts.length, onTime: onTime(ts), avgMs: avg(ts.map(usedMs)) });
    const nameOf = (id: string | null | undefined) => org.users.find((u) => u.id === id)?.name ?? '';
    const teamName = (id: string | null | undefined) => org.teams.find((x) => x.id === id)?.name ?? '';
    const card = (t: (typeof tasks)[number]) => ({ id: t.id, threadId: t.thread_id, ticketNo: t.ticket_no, subject: t.subject, status: t.status, priority: t.priority,
      assignee: nameOf(t.assignee_id) || null, dueAt: +new Date(t.due_at) > 9e12 ? null : new Date(t.due_at).toISOString() });

    const count = (type: string) => events.filter((e) => e.type === type).length;
    const movedOff = new Map<string, number>();
    for (const e of events) {
      const p = JSON.parse(e.payload as unknown as string);
      const who = e.type === 'reassigned' ? p.from : e.type === 'declined' ? e.actor_id : e.type === 'reopened' ? tasks.find((t) => t.id === e.task_id)?.assignee_id : null;
      if (who) movedOff.set(who, (movedOff.get(who) ?? 0) + 1);
    }
    const levels = new Map<string, number>(), attended = new Map<string, number>();
    for (const e of events) {
      if (e.type === 'escalated') { const l = JSON.parse(e.payload as unknown as string).level; levels.set(l, (levels.get(l) ?? 0) + 1); }
      if (e.type === 'attended' && e.actor_id) attended.set(nameOf(e.actor_id), (attended.get(nameOf(e.actor_id)) ?? 0) + 1);
    }

    const raised = rows.filter((t) => +new Date(t.created_at) >= from);
    const requesters = [...new Set(raised.map((t) => t.senderId))].map((id) => {
      const mine = raised.filter((t) => t.senderId === id);
      const u = org.users.find((x) => x.id === id);
      return { name: u?.name ?? '', department: org.departments.find((d) => d.id === u?.department_id)?.name ?? '', count: mine.length,
        sentBack: mine.filter((t) => t.status === 'Rejected' || t.status === 'Transferred').length };
    }).sort((a, b) => b.count - a.count).slice(0, 5);
    const customers = [...new Set(rows.map((t) => t.customer_name).filter((x): x is string => !!x))].map((name) => {
      const cs = rows.filter((t) => t.customer_name === name);
      return { name, total: cs.length, open: cs.filter((t) => OPEN.includes(t.status)).length, overdue: cs.filter(overdue).length, recent: cs.filter((t) => +new Date(t.created_at) >= from).length };
    }).sort((a, b) => b.total - a.total).slice(0, 10);
    const repeats = raised.filter((t) => events.some((e) => e.task_id === t.id && e.type === 'reopened')
      || rows.some((o) => o.id !== t.id && +new Date(o.created_at) < +new Date(t.created_at) && +new Date(t.created_at) - +new Date(o.created_at) <= 30 * DAY
        && !!norm(t.subject) && norm(o.subject) === norm(t.subject)))
      .map((t) => ({ ...card(t), why: events.some((e) => e.task_id === t.id && e.type === 'reopened') ? 'Reopened' : 'Raised before' }));

    return {
      scope: head ? `${org.departments.find((d) => d.id === me.department_id)?.name ?? ''} department` : teams.map(teamName).map((n) => `${n} team`).join(' + '),
      kpis: { completed: done2w.length, onTime: onTime(done2w), overdueNow: tasks.filter(overdue).length, reopened: count('reopened') },
      attention: {
        dueSoon: rows.filter((t) => OPEN.includes(t.status) && !overdue(t) && +new Date(t.due_at) - now <= 2 * 3600_000).map(card),
        waiting: rows.filter((t) => t.status === 'WaitingInfo' || t.status === 'Blocked').map((t) => ({ ...card(t),
          stuckMs: workMs(+new Date(t.updated_at), now, [9, 18], holidays) })).sort((a, b) => b.stuckMs - a.stuckMs),
        queues: (head ? org.teams.filter((x) => x.department_id === me.department_id).map((x) => x.id) : teams).map((id) => {
          const q = rows.filter((t) => t.status === 'Open' && (t.team_id === id || (!t.team_id && head)));
          const oldest = q.length ? Math.min(...q.map((t) => +new Date(t.queued_at ?? t.created_at))) : null;
          return { team: teamName(id), count: q.length, oldestMs: oldest ? workMs(oldest, now, [9, 20], holidays) : 0 };
        }).filter((q) => q.count),
      },
      thisMonth: summary(doneIn(monthStart, now + 1)),
      lastMonth: summary(doneIn(prevStart, monthStart)),
      byPriority: (['Critical', 'High', 'Medium', 'Low'] as const).map((p) => { const ds = done2w.filter((t) => t.priority === p); return { priority: p, done: ds.length, onTime: onTime(ds) }; }),
      moved: { reassigned: count('reassigned'), declined: count('declined'), reopened: count('reopened'), transferred: count('transferred'),
        escalations: [...levels].map(([level, n]) => ({ level, count: n })), stillEscalated: tasks.filter((t) => t.escalation_level && OPEN.includes(t.status)).length,
        attendedBy: [...attended].map(([name, n]) => ({ name, count: n })) },
      people: people.map((u) => {
        const mine = done2w.filter((t) => t.assignee_id === u.id);
        const active = tasks.filter((t) => t.assignee_id === u.id && ACTIVE.includes(t.status)).length;
        return { id: u.id, name: u.name, roleLabel: roleLabel(org, u.id), active, full: active >= 5, away: !!shifts.get(u.id)?.away, shift: shifts.get(u.id)?.shift ?? 0,
          done: mine.length, onTime: onTime(mine), avgMs: avg(mine.map(usedMs)), movedOff: movedOff.get(u.id) ?? 0 };
      }).sort((a, b) => b.active - a.active),
      teams: head ? org.teams.filter((x) => x.department_id === me.department_id).map((x) => {
        const tt = tasks.filter((t) => t.team_id === x.id || org.users.find((u) => u.id === t.assignee_id)?.team_id === x.id);
        const d = tt.filter((t) => done2w.includes(t));
        return { team: x.name, open: tt.filter((t) => OPEN.includes(t.status)).length, overdue: tt.filter(overdue).length, done: d.length, onTime: onTime(d) };
      }) : [],
      sources: requesters,
      customers,
      repeats,
      oldest: rows.filter((t) => OPEN.includes(t.status)).sort((a, b) => +new Date(a.created_at) - +new Date(b.created_at)).slice(0, 5)
        .map((t) => ({ ...card(t), ageMs: now - +new Date(t.created_at) })),
    };
  });
}
