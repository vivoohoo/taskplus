// Ollama on our own machine: no data leaves the office. `format` constrains the output to the schema.
import { type ExtractInput, type LlmProvider, parseJsonText } from './LlmProvider';

export class OllamaProvider implements LlmProvider {
  readonly name = 'ollama';
  constructor(private url: string, private model: string) {}

  async extractTask(input: ExtractInput, signal: AbortSignal) {
    const r = await fetch(`${this.url.replace(/\/$/, '')}/api/chat`, {
      method: 'POST',
      signal,
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ model: this.model, stream: false, format: input.jsonSchema, options: { temperature: 0 }, messages: [{ role: 'user', content: input.prompt }] }),
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const body = (await r.json()) as { message?: { content?: string } };
    return parseJsonText(body.message?.content);
  }
}
