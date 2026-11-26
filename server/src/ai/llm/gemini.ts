// Gemini with structured output: the response must match the schema generated from the Zod definition.
import { GoogleGenAI } from '@google/genai';
import { type ExtractInput, type LlmProvider, parseJsonText } from './LlmProvider';

export class GeminiProvider implements LlmProvider {
  readonly name = 'gemini';
  private ai: GoogleGenAI;
  constructor(apiKey: string, private model: string) { this.ai = new GoogleGenAI({ apiKey }); }

  async extractTask(input: ExtractInput, signal: AbortSignal) {
    const r = await this.ai.models.generateContent({
      model: this.model,
      contents: input.prompt,
      config: { responseMimeType: 'application/json', responseSchema: input.jsonSchema, temperature: 0, abortSignal: signal },
    });
    return parseJsonText(r.text);
  }
}
