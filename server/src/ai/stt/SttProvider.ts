import Groq, { toFile } from 'groq-sdk';

export interface SttProvider {
  readonly name: string;
  transcribe(input: { audio: Buffer; mime: string; hintLangs?: string[] }): Promise<{ text: string; lang?: string }>;
}

const EXT: Record<string, string> = { 'audio/ogg': 'ogg', 'audio/opus': 'opus', 'audio/mp4': 'm4a', 'audio/x-m4a': 'm4a' };

/** Groq-hosted Whisper. The language is detected; Hindi/Gujarati/English mixes come back in the spoken script. */
export class GroqWhisper implements SttProvider {
  readonly name = 'groq-whisper';
  private groq: Groq;
  constructor(apiKey: string, private model: string) { this.groq = new Groq({ apiKey }); }

  async transcribe({ audio, mime }: { audio: Buffer; mime: string }) {
    const file = await toFile(audio, `voice.${EXT[mime] ?? 'ogg'}`, { type: mime });
    const r = (await this.groq.audio.transcriptions.create({ file, model: this.model, response_format: 'verbose_json', temperature: 0 })) as { text: string; language?: string };
    return { text: r.text.trim(), lang: r.language };
  }
}
