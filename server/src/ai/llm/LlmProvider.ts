import type { PromptInput } from '../prompts/structure.v1';

export interface ExtractInput extends PromptInput { prompt: string; jsonSchema: Record<string, unknown> }

/** One LLM vendor. Returns the raw JSON it produced; checking it is validate.ts's job. */
export interface LlmProvider { readonly name: string; extractTask(input: ExtractInput, signal: AbortSignal): Promise<unknown> }

export class AiUnavailableError extends Error {
  constructor(message: string, public causes: string[] = []) { super(message); }
}

/** Parse model text as JSON, tolerating a ```json fence around it. */
export function parseJsonText(text: string | undefined | null): unknown {
  if (!text) throw new Error('empty response');
  const s = text.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  return JSON.parse(s);
}
