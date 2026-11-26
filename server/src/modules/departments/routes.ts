// Department details for the app: members (for @mention and the reassign sheet) and modules (for /module).
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { notFound } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';

export async function departmentRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);

  app.get('/departments/:id', async (req) => {
    const { id } = parse(z.object({ id: Id }), req.params);
    const d = await app.db.selectFrom('departments').selectAll().where('id', '=', id).executeTakeFirst();
    if (!d) throw notFound('Department not found.');
    const members = await app.db.selectFrom('users').select(['id', 'name', 'role', 'avatar_url'])
      .where('department_id', '=', d.id).where('is_active', '=', true).orderBy('name').execute();
    return {
      id: d.id, name: d.name, headUserId: d.head_user_id,
      modules: JSON.parse(d.modules as unknown as string) as string[],
      members: members.map((m) => ({ id: m.id, name: m.name, role: m.role, avatarUrl: m.avatar_url })),
    };
  });
}
