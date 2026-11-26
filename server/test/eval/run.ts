// npm run eval: sends every golden message to the real AI provider (LLM_PRIMARY, with fallback) and prints accuracy per field.
// Uses made-up customer data only (free tiers may train on it). Needs GEMINI_API_KEY / GROQ_API_KEY in server/.env.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadEnv } from '../../src/config/env';
import { createProviders } from '../../src/container';
import { structurePrompt } from '../../src/ai/prompts/structure.v1';
import { providerSchema } from '../../src/ai/schema/taskExtraction';
import { validateExtraction } from '../../src/ai/validate';
import { SEED } from '../../src/db/seed';
import { createLogger } from '../../src/lib/logger';
import { createMetrics } from '../../src/lib/metrics';

const FIELDS = ['module', 'priority', 'customer_name', 'customer_phone', 'customer_location', 'license_no'] as const;
type Case = { id: number; lang: string; dept: string; text: string; expect: Record<(typeof FIELDS)[number], string | null> };

/** Names may come back in another script or spelling: compare loosely (case, spaces, punctuation). */
const norm = (v: unknown) => (v == null ? null : String(v).toLowerCase().replace(/[\s.,'-]/g, ''));
export const fieldMatches = (field: string, got: unknown, want: unknown) => {
  if (field === 'customer_name' || field === 'customer_location') {
    const g = norm(got), w = norm(want);
    return g === w || (!!g && !!w && (g.includes(w) || w.includes(g)));
  }
  return norm(got) === norm(want);
};

async function main() {
  const env = loadEnv();
  const providers = createProviders(env, createLogger('warn'), createMetrics());
  const cases = readFileSync(fileURLToPath(new URL('../fixtures/messages.jsonl', import.meta.url)), 'utf8')
    .split('\n').filter(Boolean).map((l) => JSON.parse(l) as Case);
  const score = Object.fromEntries(FIELDS.map((f) => [f, 0])) as Record<string, number>;
  let failed = 0, ms = 0;

  for (const c of cases) {
    const modules = SEED.departments.find((d) => d.name === c.dept)!.modules;
    const input = { departmentName: c.dept, modules, senderName: 'Riya Shah', recipientLabel: `${c.dept} team`, text: c.text };
    const started = Date.now();
    try {
      const { data, provider } = await providers.llm.extract({ ...input, prompt: structurePrompt(input), jsonSchema: providerSchema(modules) });
      ms += Date.now() - started;
      const v = validateExtraction(data, { modules, overrides: {}, licenseRegex: env.LICENSE_REGEX });
      if (!v.ok) { failed++; console.log(`#${c.id} ${c.lang}: needs_review (${v.error})`); continue; }
      const misses = FIELDS.filter((f) => { const ok = fieldMatches(f, v.value[f], c.expect[f]); if (ok) score[f]!++; return !ok; });
      console.log(`#${c.id} ${c.lang.padEnd(5)} ${provider.padEnd(6)} ${misses.length ? `missed ${misses.map((f) => `${f}=${JSON.stringify(v.value[f])}`).join(', ')}` : 'all fields right'}`);
    } catch (e) {
      failed++;
      console.log(`#${c.id} ${c.lang}: error ${(e as Error).message}`);
    }
  }
  console.log(`\nAccuracy over ${cases.length} messages (${failed} failed, avg ${Math.round(ms / Math.max(1, cases.length - failed))} ms):`);
  for (const f of FIELDS) console.log(`  ${f.padEnd(18)} ${((score[f]! / cases.length) * 100).toFixed(0).padStart(3)}%`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
