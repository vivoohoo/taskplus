// Signed upload and download links. The file itself never passes through the API (except the dev-only memory store).
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { badRequest, forbidden, notFound } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { ALLOWED_MIME, KEY_PATTERN, MAX_UPLOAD_BYTES, MemoryStorage, storageKey } from '../../storage/StorageProvider';
import { canSeeThread, currentUser, threadFor } from '../access';

export async function uploadRoutes(app: FastifyInstance) {
  const { db } = app;

  app.post('/uploads/presign', { preHandler: app.authenticate }, async (req) => {
    const body = parse(z.object({
      threadId: Id,
      mime: z.string(),
      sizeBytes: z.number().int().min(1).max(MAX_UPLOAD_BYTES, 'Files can be up to 10 MB.'),
      purpose: z.enum(['audio', 'attachment']),
    }), req.body);
    const type = ALLOWED_MIME[body.mime];
    if (!type || type.purpose !== body.purpose) throw badRequest('This file type is not allowed. Use JPEG, PNG, PDF, or an OGG/Opus or M4A voice note.');
    const me = await currentUser(db, req.userId);
    const thread = await threadFor(db, me, body.threadId);
    const key = storageKey(thread.type === 'direct' ? 'direct' : thread.department_id!, type.ext);
    return app.services.storage.presignUpload(key, body.mime, body.sizeBytes, app.env.PRESIGN_TTL_SECONDS);
  });

  // Keys contain slashes, so the key is a query parameter: GET /files/url?key=...
  app.get('/files/url', { preHandler: app.authenticate }, async (req) => {
    const { key } = parse(z.object({ key: z.string().regex(KEY_PATTERN) }), req.query);
    const me = await currentUser(db, req.userId);
    const owner = await db.selectFrom('messages').leftJoin('attachments', 'attachments.message_id', 'messages.id')
      .select('messages.thread_id').where((eb) => eb.or([eb('messages.audio_key', '=', key), eb('attachments.r2_key', '=', key)])).executeTakeFirst();
    if (!owner) throw notFound('File not found.');
    const thread = await db.selectFrom('threads').selectAll().where('id', '=', owner.thread_id).executeTakeFirstOrThrow();
    if (!canSeeThread(me, thread)) throw forbidden();
    return app.services.storage.presignDownload(key, app.env.PRESIGN_TTL_SECONDS);
  });

  // Dev only, when no R2 keys are set: the memory store stands in for R2's signed URLs.
  const store = app.services.storage;
  if (store instanceof MemoryStorage && app.env.NODE_ENV !== 'production') {
    app.addContentTypeParser('*', { parseAs: 'buffer', bodyLimit: MAX_UPLOAD_BYTES }, (_req, body, done) => done(null, body));
    app.put('/dev-upload/*', async (req, reply) => {
      const key = (req.params as { '*': string })['*'];
      if (!KEY_PATTERN.test(key)) throw badRequest('Bad key.');
      store.put(key, req.body as Buffer, String(req.headers['content-type'] ?? 'application/octet-stream'));
      return reply.code(200).send();
    });
    app.get('/dev-upload/*', async (req, reply) => {
      const key = (req.params as { '*': string })['*'];
      const f = store.files.get(key);
      if (!f) throw notFound();
      return reply.type(f.mime).send(f.body);
    });
  }
}
