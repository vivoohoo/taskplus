// Every setting the server reads, checked once at startup. Nothing else reads process.env.
import { existsSync } from 'node:fs';
import { z } from 'zod';

const bool = z.enum(['true', 'false']).transform((v) => v === 'true');

const Env = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(8080),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),

  // SQL Server, e.g. mssql://taskplus:secret@localhost:1433/taskplus?encrypt=true&trustServerCertificate=true
  DATABASE_URL: z.string().startsWith('mssql://'),
  REDIS_URL: z.string().default('redis://localhost:6379'),

  // Prototype vs production switches (spec §12)
  QUEUE_MODE: z.enum(['inline', 'bullmq']).default('inline'),
  REALTIME_MODE: z.enum(['memory', 'redis']).default('memory'),
  LLM_PRIMARY: z.enum(['gemini', 'groq', 'ollama']).default('gemini'),
  LLM_FALLBACK: z.enum(['groq', 'ollama', 'none']).default('groq'),
  LLM_TIMEOUT_MS: z.coerce.number().int().positive().default(12_000),
  JOB_MAX_ATTEMPTS: z.coerce.number().int().min(1).default(3),

  // Providers: checked when the provider is first used, so the server can run before keys exist (see DECISIONS.md)
  GEMINI_API_KEY: z.string().optional(),
  GEMINI_MODEL: z.string().optional(),
  GROQ_API_KEY: z.string().optional(),
  GROQ_LLM_MODEL: z.string().optional(),
  GROQ_STT_MODEL: z.string().default('whisper-large-v3-turbo'),
  OLLAMA_URL: z.string().default('http://localhost:11434'),
  OLLAMA_MODEL: z.string().default('qwen2.5:7b-instruct'),
  R2_ACCOUNT_ID: z.string().optional(),
  R2_ACCESS_KEY_ID: z.string().optional(),
  R2_SECRET_ACCESS_KEY: z.string().optional(),
  R2_BUCKET: z.string().default('taskplus'),
  PRESIGN_TTL_SECONDS: z.coerce.number().int().positive().default(300),
  FIREBASE_SERVICE_ACCOUNT_JSON: z.string().optional(),

  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  DEV_FIXED_OTP: z.string().regex(/^\d{6}$/).optional(),

  // Business rules
  DEFAULT_PRIORITY: z.enum(['High', 'Medium', 'Low']).default('Medium'),
  SLA_HOURS_HIGH: z.coerce.number().positive().default(4),
  SLA_HOURS_MEDIUM: z.coerce.number().positive().default(24),
  SLA_HOURS_LOW: z.coerce.number().positive().default(72),
  LICENSE_REGEX: z.string().optional(),
  TRUST_PROXY: bool.default(false),
}).superRefine((e, ctx) => {
  if (e.NODE_ENV === 'production' && e.DEV_FIXED_OTP)
    ctx.addIssue({ code: 'custom', path: ['DEV_FIXED_OTP'], message: 'must not be set in production' });
});

export type Env = z.infer<typeof Env>;

/** Parse settings; throws one readable error listing every problem. */
export function loadEnv(source?: Record<string, string | undefined>): Env {
  if (!source) {
    // server/.env, if present; real environment variables win over it (Node >= 20.12).
    if (existsSync('.env')) process.loadEnvFile('.env');
    source = process.env;
  }
  const r = Env.safeParse(source);
  if (r.success) return r.data;
  const lines = r.error.issues.map((i) => `  ${i.path.join('.') || '(env)'}: ${i.message}`);
  throw new Error(`Invalid settings (see server/.env.example):\n${lines.join('\n')}`);
}

/** A provider key that is only needed once that provider is used. */
export function requireKey(env: Env, name: keyof Env): string {
  const v = env[name];
  if (typeof v !== 'string' || !v) throw new Error(`${String(name)} is not set. Add it to server/.env (see .env.example).`);
  return v;
}
