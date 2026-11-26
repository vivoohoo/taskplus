// Groq chat model in JSON mode. The schema goes in the prompt because JSON mode does not enforce one.
import Groq from 'groq-sdk';
import { type ExtractInput, type LlmProvider, parseJsonText } from './LlmProvider';

export class GroqProvider implements LlmProvider {
  readonly name = 'groq';
  private groq: Groq;
  constructor(apiKey: string, private model: string) { this.groq = new Groq({ apiKey }); }

  async extractTask(input: ExtractInput, signal: AbortSignal) {
    const r = await this.groq.chat.completions.create({
      model: this.model,
      temperature: 0,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: `Reply with one JSON object matching this JSON schema:\n${JSON.stringify(input.jsonSchema)}` },
        { role: 'user', content: input.prompt },
      ],
    }, { signal });
    return parseJsonText(r.choices[0]?.message?.content);
  }
}
