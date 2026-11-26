// Spec §9.1: primary with a timeout; on timeout, 429, 5xx, bad JSON or any other failure, the fallback.
import type { Logger } from '../../lib/logger';
import { AiUnavailableError, type ExtractInput, type LlmProvider } from './LlmProvider';

export interface LlmGateway { extract(input: ExtractInput): Promise<{ data: unknown; provider: string; latencyMs: number }> }

export function createGateway(primary: LlmProvider, fallback: LlmProvider | null, timeoutMs: number, log: Logger,
  onResult?: (provider: string, ok: boolean, ms: number) => void): LlmGateway {
  const tryOne = async (p: LlmProvider, input: ExtractInput) => {
    const started = Date.now();
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(new Error(`timed out after ${timeoutMs} ms`)), timeoutMs);
    try {
      const data = await Promise.race([
        p.extractTask(input, ctl.signal),
        new Promise<never>((_, rej) => ctl.signal.addEventListener('abort', () => rej(ctl.signal.reason as Error))),
      ]);
      onResult?.(p.name, true, Date.now() - started);
      return { data, provider: p.name, latencyMs: Date.now() - started };
    } catch (e) {
      onResult?.(p.name, false, Date.now() - started);
      throw e;
    } finally {
      clearTimeout(timer);
    }
  };

  return {
    async extract(input) {
      const causes: string[] = [];
      for (const p of [primary, fallback]) {
        if (!p) continue;
        try {
          return await tryOne(p, input);
        } catch (e) {
          const msg = `${p.name}: ${(e as Error).message}`;
          causes.push(msg);
          log.warn({ provider: p.name, err: (e as Error).message }, 'LLM call failed');
        }
      }
      throw new AiUnavailableError(`No AI provider answered (${causes.join(' | ')})`, causes);
    },
  };
}
