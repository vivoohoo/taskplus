// Signed upload and download links. With STORAGE=disk the files live on this server's disk and pass through these routes;
// with R2 they go straight to R2.
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { badRequest, forbidden, notFound } from '../../lib/errors';
import { Id, parse } from '../../lib/validate';
import { DiskStorage } from '../../storage/disk';
import { ALLOWED_MIME, KEY_PATTERN, MAX_UPLOAD_BYTES, storageKey } from '../../storage/StorageProvider';
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
    const key = storageKey(thread.type === 'department' ? thread.department_id! : 'direct', type.ext);
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

  // Files on this server's disk: the signed link is the permission (no sign-in header on these two routes).
  const store = app.services.storage;
  if (store instanceof DiskStorage) {
    app.addContentTypeParser('*', { parseAs: 'buffer', bodyLimit: MAX_UPLOAD_BYTES }, (_req, body, done) => done(null, body));
    const signed = (req: { params: unknown; query: unknown }) => {
      const key = (req.params as { '*': string })['*'];
      const q = req.query as { exp?: string; sig?: string };
      if (!KEY_PATTERN.test(key) || !q.exp || !q.sig) throw forbidden('This link is not valid.');
      return { key, exp: q.exp, sig: q.sig };
    };
    app.put('/files/raw/*', async (req, reply) => {
      const { key, exp, sig } = signed(req);
      const body = req.body as Buffer;
      const mime = String(req.headers['content-type'] ?? '').split(';')[0]!.trim();
      if (!Buffer.isBuffer(body) || !store.verify('PUT', key, exp, sig, mime, body.length)) throw forbidden('This upload link has expired or does not match the file.');
      await store.put(key, body, mime);
      return reply.code(200).send();
    });
    app.get('/files/raw/*', async (req, reply) => {
      const { key, exp, sig } = signed(req);
      if (!store.verify('GET', key, exp, sig)) throw forbidden('This link has expired.');
      const h = await store.head(key);
      if (!h) throw notFound('This file is no longer kept (files are deleted after the retention period).');
      return reply.type(h.mime).header('cache-control', 'private, max-age=300').send(await store.get(key));
    });
  }
}
