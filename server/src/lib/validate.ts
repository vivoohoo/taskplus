import { z } from 'zod';
import { badRequest } from './errors';

/** Parse a request body with Zod; a failure becomes a 400 with the field messages. */
export function parse<T extends z.ZodType>(schema: T, value: unknown): z.infer<T> {
  const r = schema.safeParse(value ?? {});
  if (r.success) return r.data;
  const fields = r.error.issues.map((i) => ({ field: i.path.join('.'), message: i.message }));
  throw badRequest(fields[0]?.message ?? 'Invalid request.', fields);
}

/** A UUID from a client, in the upper case SQL Server returns, so it compares equal to ids read from the database. */
export const Id = z.uuid().transform((v) => v.toUpperCase());
