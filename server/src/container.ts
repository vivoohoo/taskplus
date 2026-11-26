// Builds providers from settings. Missing keys: in development a stand-in with a warning; in production, refuse to start.
import type { Env } from './config/env';
import { requireKey } from './config/env';
import { createGateway, type LlmGateway } from './ai/llm/gateway';
import { GeminiProvider } from './ai/llm/gemini';
import { GroqProvider } from './ai/llm/groq';
import type { LlmProvider } from './ai/llm/LlmProvider';
import { OllamaProvider } from './ai/llm/ollama';
import { GroqWhisper, type SttProvider } from './ai/stt/SttProvider';
import type { Logger } from './lib/logger';
import type { Metrics } from './lib/metrics';
import { FcmPush, MemoryPush, type PushProvider } from './push/PushProvider';
import { R2Storage } from './storage/r2';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { DiskStorage } from './storage/disk';
import type { StorageProvider } from './storage/StorageProvider';

export interface Providers { storage: StorageProvider; llm: LlmGateway; stt: SttProvider; push: PushProvider }

/** A provider whose key is missing: every call fails with the reason, so tasks end up "Needs review" instead of crashing. */
const missing = (name: string, why: string): LlmProvider & SttProvider => ({
  name,
  extractTask: async () => { throw new Error(why); },
  transcribe: async () => { throw new Error(why); },
});

function llm(env: Env, which: 'gemini' | 'groq' | 'ollama'): LlmProvider {
  try {
    if (which === 'gemini') return new GeminiProvider(requireKey(env, 'GEMINI_API_KEY'), requireKey(env, 'GEMINI_MODEL'));
    if (which === 'groq') return new GroqProvider(requireKey(env, 'GROQ_API_KEY'), requireKey(env, 'GROQ_LLM_MODEL'));
    return new OllamaProvider(env.OLLAMA_URL, env.OLLAMA_MODEL);
  } catch (e) {
    if (env.NODE_ENV === 'production') throw e;
    return missing(which, (e as Error).message);
  }
}

export function createProviders(env: Env, log: Logger, metrics: Metrics): Providers {
  const prod = env.NODE_ENV === 'production';
  const warn = (what: string) => log.warn(`${what} (fine for development; required in production)`);

  let storage: StorageProvider;
  if (env.STORAGE === 'r2') {
    storage = new R2Storage(requireKey(env, 'R2_ACCOUNT_ID'), requireKey(env, 'R2_ACCESS_KEY_ID'), requireKey(env, 'R2_SECRET_ACCESS_KEY'), env.R2_BUCKET);
  } else {
    // Links are relative (/v1/files/raw/...): the phone adds whatever server address it is using (the tunnel address changes).
    storage = diskStorage(env);
  }

  let push: PushProvider;
  if (env.FIREBASE_SERVICE_ACCOUNT_JSON) push = new FcmPush(env.FIREBASE_SERVICE_ACCOUNT_JSON);
  else {
    if (prod) throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is required in production.');
    warn('No Firebase key: push notifications are logged, not sent');
    push = new MemoryPush();
  }

  let stt: SttProvider;
  try { stt = new GroqWhisper(requireKey(env, 'GROQ_API_KEY'), env.GROQ_STT_MODEL); } catch (e) {
    if (prod) throw e;
    warn('No GROQ_API_KEY: voice notes will be marked "Needs review"');
    stt = missing('groq-whisper', (e as Error).message);
  }

  const primary = llm(env, env.LLM_PRIMARY);
  const fallback = env.LLM_FALLBACK === 'none' ? null : llm(env, env.LLM_FALLBACK);
  const gateway = createGateway(primary, fallback, env.LLM_TIMEOUT_MS, log,
    (provider, ok, ms) => metrics.aiLatency.observe({ provider, ok: String(ok) }, ms));
  return { storage, llm: gateway, stt, push };
}

/** Signing key for file links, derived from JWT_SECRET so there is one less secret to manage. */
export const diskStorage = (env: Env) =>
  new DiskStorage(resolve(env.FILES_DIR), () => '', createHash('sha256').update(`files:${env.JWT_SECRET}`).digest('hex'));
