import { describe, expect, it, vi } from 'vitest';
import { createGateway } from '../src/ai/llm/gateway';
import { AiUnavailableError, parseJsonText, type LlmProvider } from '../src/ai/llm/LlmProvider';
import { PROMPT_VERSION, structurePrompt } from '../src/ai/prompts/structure.v1';
import { providerSchema, taskExtraction } from '../src/ai/schema/taskExtraction';
import { cleanLicense, cleanPhone, validateExtraction } from '../src/ai/validate';
import { backoffMs, inlineQueue } from '../src/jobs/queue';
import { createLogger } from '../src/lib/logger';

const modules = ['Profit NX', 'SQL Installation', 'Licensing', 'Printing', 'Other'];
const good = { subject: 'Profit NX Login Failure', module: 'Profit NX', customer_name: 'Mehta Traders', customer_phone: '+91 98250 12345',
  customer_location: 'Surat', license_no: 'pnx-2024-881', priority: 'High', details: 'Login fails for all users.' };
const log = createLogger('error');

describe('validation (spec §9.4)', () => {
  it('cleans phone and licence and keeps the rest', () => {
    const r = validateExtraction(good, { modules, overrides: {} });
    expect(r.ok && r.value).toMatchObject({ customer_phone: '9825012345', license_no: 'PNX-2024-881', module: 'Profit NX', priority: 'High' });
    expect(r.ok && r.warnings).toEqual([]);
  });
  it('phones: 10 digits, 11–15 international, otherwise removed with a warning', () => {
    expect(cleanPhone('098250 12345').value).toBe('09825012345');
    expect(cleanPhone('+44 20 7946 0958').value).toBe('442079460958');
    expect(cleanPhone('12345')).toEqual({ value: null, warning: expect.stringMatching(/customer_phone/) });
    expect(cleanPhone('  ').value).toBeNull();
  });
  it('licence: upper case, and removed with a warning if it misses LICENSE_REGEX', () => {
    expect(cleanLicense(' ab-12 ').value).toBe('AB-12');
    expect(cleanLicense('ab-12', '^[A-Z]{3}-\\d{4}-\\d{3}$')).toEqual({ value: null, warning: expect.stringMatching(/license_no/) });
  });
  it('turns an unknown module into "Other" instead of failing', () => {
    const r = validateExtraction({ ...good, module: 'Payroll' }, { modules, overrides: {} });
    expect(r.ok && r.value.module).toBe('Other');
  });
  it('overrides always beat the AI', () => {
    const r = validateExtraction(good, { modules, overrides: { priority: 'Low', module: 'Licensing', license: 'x-9', customer: 'Kaveri Steel' } });
    expect(r.ok && r.value).toMatchObject({ priority: 'Low', module: 'Licensing', license_no: 'X-9', customer_name: 'Kaveri Steel' });
  });
  it('a customer override that is only digits is the phone number', () => {
    const r = validateExtraction(good, { modules, overrides: { customer: '+91 99999 00000' } });
    expect(r.ok && r.value).toMatchObject({ customer_phone: '9999900000', customer_name: 'Mehta Traders' });
  });
  it('wrong shape is a hard failure (needs review)', () => {
    expect(validateExtraction({ subject: 'x' }, { modules, overrides: {} }).ok).toBe(false);
    expect(validateExtraction({ ...good, priority: 'Urgent' }, { modules, overrides: {} }).ok).toBe(false);
    expect(validateExtraction({ ...good, subject: 'x'.repeat(61) }, { modules, overrides: {} }).ok).toBe(false);
  });
});

describe('schema and prompt', () => {
  it('generates the provider schema from the Zod schema, with nullable fields and the module list', () => {
    const s = providerSchema(modules) as { properties: Record<string, Record<string, unknown>>; required: string[] };
    expect(s.properties.module!.enum).toEqual(modules);
    expect(s.properties.customer_phone!.nullable).toBe(true);
    expect(s.properties.priority!.enum).toEqual(['High', 'Medium', 'Low']);
    expect(s.required).toEqual(expect.arrayContaining(['subject', 'priority', 'details']));
    expect(taskExtraction(['A']).shape.module.options).toEqual(['A', 'Other']);
  });
  it('fills the prompt and keeps the version', () => {
    const p = structurePrompt({ departmentName: 'Support', modules, senderName: 'Riya', recipientLabel: 'Support team', text: 'printer """ jam' });
    expect(p).toContain('Allowed modules: Profit NX, SQL Installation');
    expect(p).not.toContain('printer """ jam'); // a """ in the message can't end the quoted block
    expect(PROMPT_VERSION).toBe('structure.v1');
  });
  it('reads JSON with or without a code fence', () => {
    expect(parseJsonText('```json\n{"a":1}\n```')).toEqual({ a: 1 });
    expect(() => parseJsonText('not json')).toThrow();
  });
});

describe('LLM gateway', () => {
  const input = { departmentName: 'S', modules, senderName: 'a', recipientLabel: 'b', text: 't', prompt: 'p', jsonSchema: {} };
  const provider = (name: string, fn: () => Promise<unknown>): LlmProvider => ({ name, extractTask: fn });

  it('uses the primary when it answers', async () => {
    const g = createGateway(provider('gemini', async () => good), provider('groq', async () => ({})), 1000, log);
    expect(await g.extract(input)).toMatchObject({ provider: 'gemini', data: good });
  });
  it('falls back on error, bad JSON or timeout', async () => {
    const fb = provider('groq', async () => good);
    for (const bad of [async () => { throw Object.assign(new Error('429'), { status: 429 }); }, async () => parseJsonText('<html>'), () => new Promise(() => {})]) {
      const g = createGateway(provider('gemini', bad), fb, 50, log);
      expect((await g.extract(input)).provider).toBe('groq');
    }
  });
  it('throws AiUnavailableError when both fail', async () => {
    const g = createGateway(provider('gemini', async () => { throw new Error('down'); }), provider('groq', async () => { throw new Error('down too'); }), 100, log);
    await expect(g.extract(input)).rejects.toBeInstanceOf(AiUnavailableError);
  });
});

describe('inline queue', () => {
  it('waits 1 s, 4 s, 16 s between tries', () => {
    expect([1, 2, 3].map((n) => backoffMs(n))).toEqual([1000, 4000, 16000]);
  });
  it('retries, then calls the failure handler once', async () => {
    const run = vi.fn().mockRejectedValue(new Error('boom'));
    const failed = vi.fn().mockResolvedValue(undefined);
    const q = inlineQueue({ run, failed }, { maxAttempts: 3, log, unitMs: 1 });
    await q.enqueue('structure', { taskId: 'x' }, { jobId: 'structure:x' });
    await q.idle();
    expect(run).toHaveBeenCalledTimes(3);
    expect(failed).toHaveBeenCalledTimes(1);
  });
  it('ignores the same job id while it is queued', async () => {
    const run = vi.fn().mockResolvedValue(undefined);
    const q = inlineQueue({ run, failed: vi.fn() }, { maxAttempts: 1, log });
    await q.enqueue('notify', {}, { jobId: 'n:1' });
    await q.enqueue('notify', {}, { jobId: 'n:1' });
    await q.idle();
    expect(run).toHaveBeenCalledTimes(1);
  });
});

describe('golden set', () => {
  it('has at least 25 messages in all four languages, with modules from their department', async () => {
    const { readFileSync } = await import('node:fs');
    const { SEED } = await import('../src/db/seed');
    const { fieldMatches } = await import('./eval/run');
    const lines = readFileSync(new URL('./fixtures/messages.jsonl', import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
    expect(lines.length).toBeGreaterThanOrEqual(25);
    expect(new Set(lines.map((l) => l.lang))).toEqual(new Set(['en', 'hi', 'gu', 'mixed']));
    for (const l of lines) expect(SEED.departments.find((d) => d.name === l.dept)!.modules).toContain(l.expect.module);
    expect(fieldMatches('customer_name', 'Mehta Traders Pvt.', 'Mehta Traders')).toBe(true);
    expect(fieldMatches('customer_phone', '9825012345', '9825012346')).toBe(false);
  });
});
