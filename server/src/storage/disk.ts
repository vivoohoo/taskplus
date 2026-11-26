// Files on the office server's own disk (owner's decision), behind the same signed-link interface as R2.
// The API serves PUT/GET /v1/files/raw/<key>?exp=..&sig=.. ; the signature ties the link to one key, method, type and size.
import { createHmac, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { dirname, join, relative, sep } from 'node:path';
import type { StorageProvider } from './StorageProvider';

export class DiskStorage implements StorageProvider {
  readonly name = 'disk';
  constructor(private root: string, private publicBaseUrl: () => string, private secret: string) {}

  private path(key: string) { return join(this.root, ...key.split('/')); }
  private sign(method: string, key: string, exp: number, mime = '', size = 0) {
    return createHmac('sha256', this.secret).update(`${method}\n${key}\n${exp}\n${mime}\n${size}`).digest('base64url');
  }
  private url(method: string, key: string, ttl: number, mime?: string, size?: number) {
    const exp = Math.floor(Date.now() / 1000) + ttl;
    const q = new URLSearchParams({ exp: String(exp), sig: this.sign(method, key, exp, mime, size) });
    return { url: `${this.publicBaseUrl()}/v1/files/raw/${key}?${q}`, expiresAt: new Date(exp * 1000).toISOString() };
  }

  /** Checks a signed link from a request. */
  verify(method: 'PUT' | 'GET', key: string, exp: string, sig: string, mime = '', size = 0) {
    const e = Number(exp);
    if (!Number.isFinite(e) || e * 1000 < Date.now()) return false;
    const want = Buffer.from(this.sign(method, key, e, mime, size)), got = Buffer.from(sig);
    return want.length === got.length && timingSafeEqual(want, got);
  }

  async presignUpload(key: string, mime: string, sizeBytes: number, ttl: number) {
    const u = this.url('PUT', key, ttl, mime, sizeBytes);
    return { url: u.url, key, expiresAt: u.expiresAt, headers: { 'content-type': mime } };
  }
  async presignDownload(key: string, ttl: number) { return this.url('GET', key, ttl); }

  async put(key: string, body: Buffer, mime: string) {
    const p = this.path(key);
    await mkdir(dirname(p), { recursive: true });
    await writeFile(p, body);
    await writeFile(`${p}.type`, mime);
  }
  async head(key: string) {
    try {
      const s = await stat(this.path(key));
      return { sizeBytes: s.size, mime: (await readFile(`${this.path(key)}.type`, 'utf8')).trim() };
    } catch { return null; }
  }
  async get(key: string) { return readFile(this.path(key)); }

  /** D6: delete files older than `days`; the task, its text and transcript stay. Returns how many were removed. */
  async deleteOlderThan(days: number) {
    const cutoff = Date.now() - days * 86_400_000;
    let removed = 0;
    const walk = async (dir: string): Promise<void> => {
      let entries;
      try { entries = await readdir(dir, { withFileTypes: true }); } catch { return; }
      for (const e of entries) {
        const p = join(dir, e.name);
        if (e.isDirectory()) { await walk(p); continue; }
        if (e.name.endsWith('.type')) continue;
        if ((await stat(p)).mtimeMs < cutoff) { await rm(p, { force: true }); await rm(`${p}.type`, { force: true }); removed++; }
      }
    };
    await walk(this.root);
    return removed;
  }

  /** The key for a path under the root (for logs). */
  keyOf(p: string) { return relative(this.root, p).split(sep).join('/'); }
}
