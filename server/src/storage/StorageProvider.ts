// Files go straight between the phone and storage through short-lived signed links; nothing passes through the API.
export interface PresignedUpload { url: string; key: string; expiresAt: string; headers: Record<string, string> }

export interface StorageProvider {
  readonly name: string;
  presignUpload(key: string, mime: string, sizeBytes: number, ttlSeconds: number): Promise<PresignedUpload>;
  presignDownload(key: string, ttlSeconds: number): Promise<{ url: string; expiresAt: string }>;
  /** Size and type of an uploaded file, or null if it isn't there. */
  head(key: string): Promise<{ sizeBytes: number; mime: string } | null>;
  get(key: string): Promise<Buffer>;
}

export const ALLOWED_MIME: Record<string, { ext: string; purpose: 'audio' | 'attachment' }> = {
  'audio/ogg': { ext: 'ogg', purpose: 'audio' },
  'audio/opus': { ext: 'opus', purpose: 'audio' },
  'audio/mp4': { ext: 'm4a', purpose: 'audio' },
  'audio/x-m4a': { ext: 'm4a', purpose: 'audio' },
  'image/jpeg': { ext: 'jpg', purpose: 'attachment' },
  'image/png': { ext: 'png', purpose: 'attachment' },
  'application/pdf': { ext: 'pdf', purpose: 'attachment' },
};
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

/** {deptId|direct}/{yyyy}/{mm}/{uuid}.{ext} (spec §12). */
export function storageKey(scope: string, ext: string, now = new Date(), id = crypto.randomUUID()) {
  return `${scope.toLowerCase()}/${now.getUTCFullYear()}/${String(now.getUTCMonth() + 1).padStart(2, '0')}/${id}.${ext}`;
}
export const KEY_PATTERN = /^(direct|[0-9a-f-]{36})\/\d{4}\/\d{2}\/[0-9a-f-]{36}\.(ogg|opus|m4a|jpg|png|pdf)$/;

/** In memory: tests, and running before R2 keys exist. Upload URLs point at /dev-upload on this API. */
export class MemoryStorage implements StorageProvider {
  readonly name = 'memory';
  readonly files = new Map<string, { body: Buffer; mime: string }>();
  constructor(private baseUrl = 'http://localhost:8080') {}
  async presignUpload(key: string, mime: string, _size: number, ttl: number) {
    return { url: `${this.baseUrl}/v1/dev-upload/${key}`, key, expiresAt: new Date(Date.now() + ttl * 1000).toISOString(), headers: { 'content-type': mime } };
  }
  async presignDownload(key: string, ttl: number) {
    return { url: `${this.baseUrl}/v1/dev-upload/${key}`, expiresAt: new Date(Date.now() + ttl * 1000).toISOString() };
  }
  async head(key: string) { const f = this.files.get(key); return f ? { sizeBytes: f.body.length, mime: f.mime } : null; }
  async get(key: string) { const f = this.files.get(key); if (!f) throw new Error(`No file ${key}`); return f.body; }
  put(key: string, body: Buffer, mime: string) { this.files.set(key, { body, mime }); }
}
