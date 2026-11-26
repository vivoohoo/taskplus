// Department details for the app: members (for @mention and the reassign sheet) and modules (for /module).
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { notFound } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { loadOrg, roleLabel } from '../org';

export async function departmentRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);

  app.get('/departments/:id', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const d = await app.db.selectFrom('departments').selectAll().where('id', '=', id).executeTakeFirst();
    if (!d) throw notFound('Department not found.');
    const org = await loadOrg(app.db);
    const members = await app.db.selectFrom('users').select(['id', 'name', 'role', 'avatar_url', 'team_id'])
      .where('department_id', '=', d.id).where('is_active', '=', true).orderBy('name').execute();
    return {
      id: d.id, name: d.name, headUserId: d.head_user_id,
      modules: JSON.parse(d.modules as unknown as string) as string[],
      teams: org.teams.filter((t) => t.department_id === d.id).map((t) => ({ id: t.id, name: t.name, leadId: t.lead_id })),
      members: members.map((m) => ({ id: m.id, name: m.name, role: m.role, roleLabel: roleLabel(org, m.id), teamId: m.team_id, avatarUrl: m.avatar_url })),
    };
  });
}
