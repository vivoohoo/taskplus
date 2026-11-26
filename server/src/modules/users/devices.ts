// POST /devices: register or refresh this phone's FCM token. A token moves to whoever signed in last on that phone.
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { parse } from '../../lib/validate';

export async function deviceRoutes(app: FastifyInstance) {
  app.post('/devices', { preHandler: app.authenticate }, async (req, reply) => {
    const { fcmToken, platform } = parse(z.object({ fcmToken: z.string().min(20).max(400), platform: z.enum(['android', 'ios']) }), req.body);
    const now = new Date();
    await app.db.transaction().execute(async (tx) => {
      const r = await tx.updateTable('device_tokens').set({ user_id: req.userId, platform, last_seen_at: now })
        .where('fcm_token', '=', fcmToken).executeTakeFirst();
      if (!Number(r.numUpdatedRows)) await tx.insertInto('device_tokens').values({ user_id: req.userId, fcm_token: fcmToken, platform, last_seen_at: now }).execute();
    });
    return reply.code(204).send();
  });
}
