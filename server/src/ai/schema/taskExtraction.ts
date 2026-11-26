// The one definition of what the LLM must return (spec §9.2). Zod checks it; the provider JSON schema is generated from it.
import { z } from 'zod';

export const PRIORITIES = ['High', 'Medium', 'Low'] as const;

/** Per department, because `module` must be one of that department's modules (or "Other"). */
export function taskExtraction(modules: string[]) {
  const allowed = [...new Set([...modules, 'Other'])] as [string, ...string[]];
  return z.object({
    subject: z.string().min(1).max(60).describe('Short, specific, Title Case, no customer names or numbers'),
    module: z.enum(allowed).describe('Closest module; "Other" if none fit'),
    customer_name: z.string().nullable(),
    customer_phone: z.string().nullable().describe('Digits only, keep country code if spoken'),
    customer_location: z.string().nullable(),
    license_no: z.string().nullable(),
    priority: z.enum(PRIORITIES),
    details: z.string().min(1).describe('1-5 short sentences or bullets; every technical fact kept'),
  });
}
export type TaskExtraction = z.infer<ReturnType<typeof taskExtraction>>;

/** JSON schema for providers (Gemini responseSchema uses the OpenAPI 3.0 flavour: `nullable: true`). */
export const providerSchema = (modules: string[], target: 'openapi-3.0' | 'draft-2020-12' = 'openapi-3.0') =>
  z.toJSONSchema(taskExtraction(modules), { target }) as Record<string, unknown>;
