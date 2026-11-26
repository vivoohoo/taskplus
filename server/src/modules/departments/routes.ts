// Department details for the app: members (for @mention and the reassign sheet) and modules (for /module).
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { notFound } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { loadOrg, roleLabel } from '../org';

export async function departmentRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);

  /** All departments (for Transfer and Ask to transfer). */
  app.get('/departments', async () => ({
    departments: (await app.db.selectFrom('departments').select(['id', 'name']).orderBy('name').execute()),
  }));

  app.get('/departments/:id', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const d = await app.db.selectFrom('departments').selectAll().where('id', '=', id).executeTakeFirst();
    if (!d) throw notFound('Department not found.');
    const org = await loadOrg(app.db);
    const members = await app.db.selectFrom('users').select(['id', 'name', 'role', 'avatar_url', 'team_id', 'away'])
      .where('department_id', '=', d.id).where('is_active', '=', true).orderBy('name').execute();
    // Ornate's workload limit: 5 active tasks makes someone "full" in the assign/reassign pickers.
    const load = await app.db.selectFrom('tasks').select(['assignee_id', app.db.fn.countAll<number>().as('n')])
      .where('status', 'in', ['Accepted', 'InProgress', 'WaitingInfo', 'Blocked']).where('assignee_id', 'is not', null).groupBy('assignee_id').execute();
    const active = new Map(load.map((l) => [l.assignee_id, Number(l.n)]));
    return {
      id: d.id, name: d.name, headUserId: d.head_user_id,
      modules: JSON.parse(d.modules as unknown as string) as string[],
      teams: org.teams.filter((t) => t.department_id === d.id).map((t) => ({ id: t.id, name: t.name, leadId: t.lead_id })),
      members: members.map((m) => ({ id: m.id, name: m.name, role: m.role, roleLabel: roleLabel(org, m.id), teamId: m.team_id, avatarUrl: m.avatar_url,
        active: active.get(m.id) ?? 0, full: (active.get(m.id) ?? 0) >= 5, away: m.away })),
    };
  });
}
