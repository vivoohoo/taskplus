import type { z } from 'zod';
import { badRequest } from './errors';

/** Parse a request body with Zod; a failure becomes a 400 with the field messages. */
export function parse<T extends z.ZodType>(schema: T, value: unknown): z.infer<T> {
  const r = schema.safeParse(value ?? {});
  if (r.success) return r.data;
  const fields = r.error.issues.map((i) => ({ field: i.path.join('.'), message: i.message }));
  throw badRequest(fields[0]?.message ?? 'Invalid request.', fields);
}
