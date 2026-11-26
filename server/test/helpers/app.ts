// The app on a real SQL Server with fake providers: memory storage and push, scriptable AI and speech-to-text.
import request from 'supertest';
import { buildApp } from '../../src/app';
import { loadEnv } from '../../src/config/env';
import type { Providers } from '../../src/container';
import type { LlmGateway } from '../../src/ai/llm/gateway';
import { AiUnavailableError, type ExtractInput } from '../../src/ai/llm/LlmProvider';
import type { SttProvider } from '../../src/ai/stt/SttProvider';
import { createLogger } from '../../src/lib/logger';
import { MemoryPush } from '../../src/push/PushProvider';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { diskStorage } from '../../src/container';
import { startTestDb, TEST_PASSWORD } from './db';

export class FakeLlm implements LlmGateway {
  calls: ExtractInput[] = [];
  /** Next answers; a function decides per call. Default: a plain Medium task built from the text. */
  answer: (i: ExtractInput) => unknown = (i) => ({
    subject: 'Test Task', module: i.modules[0], customer_name: null, customer_phone: null, customer_location: null,
    license_no: null, priority: 'Medium', details: i.text,
  });
  failing = false;
  async extract(i: ExtractInput) {
    this.calls.push(i);
    if (this.failing) throw new AiUnavailableError('No AI provider answered (fake: down)');
    return { data: this.answer(i), provider: 'fake', latencyMs: 1 };
  }
}
export class FakeStt implements SttProvider {
  readonly name = 'fake-stt';
  text = 'Profit NX login not working for Mehta Traders';
  failing = false;
  async transcribe() { if (this.failing) throw new Error('fake stt down'); return { text: this.text, lang: 'en' }; }
}

export async function startTestApp(extraEnv: Record<string, string> = {}) {
  const ctx = await startTestDb();
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: ctx.url, JWT_SECRET: 't'.repeat(40), JOB_MAX_ATTEMPTS: '2', ...extraEnv });
  const fakes = { storage: diskStorage({ ...env, FILES_DIR: mkdtempSync(join(tmpdir(), 'taskplus-files-')) }), llm: new FakeLlm(), stt: new FakeStt(), push: new MemoryPush() };
  const app = await buildApp({ env, db: ctx.db, logger: createLogger('error'), providers: fakes as Providers, backoffUnitMs: 5 });
  await app.ready();

  const ids = new Map<string, string>();
  const token = async (phone: string) => {
    const r = await request(app.server).post('/v1/auth/login').send({ phone, password: TEST_PASSWORD });
    ids.set(phone, r.body.user.id);
    return r.body.accessToken as string;
  };
  const as = (tok: string) => ({
    get: (url: string) => request(app.server).get(url).set('authorization', `Bearer ${tok}`),
    post: (url: string, body?: object) => request(app.server).post(url).set('authorization', `Bearer ${tok}`).send(body ?? {}),
  });
  return { app, db: ctx.db, env, fakes, token, as, ids, stop: async () => { await app.close(); await ctx.stop(); } };
}
export type TestApp = Awaited<ReturnType<typeof startTestApp>>;
