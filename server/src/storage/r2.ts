// Cloudflare R2 through its S3-compatible API. Uploads are signed for one key, one type and one size.
import { GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { StorageProvider } from './StorageProvider';

export class R2Storage implements StorageProvider {
  readonly name = 'r2';
  private s3: S3Client;
  constructor(accountId: string, accessKeyId: string, secretAccessKey: string, private bucket: string) {
    this.s3 = new S3Client({ region: 'auto', endpoint: `https://${accountId}.r2.cloudflarestorage.com`, credentials: { accessKeyId, secretAccessKey } });
  }

  async presignUpload(key: string, mime: string, sizeBytes: number, ttl: number) {
    const cmd = new PutObjectCommand({ Bucket: this.bucket, Key: key, ContentType: mime, ContentLength: sizeBytes });
    const url = await getSignedUrl(this.s3, cmd, { expiresIn: ttl, signableHeaders: new Set(['content-type', 'content-length']) });
    return { url, key, expiresAt: new Date(Date.now() + ttl * 1000).toISOString(), headers: { 'content-type': mime, 'content-length': String(sizeBytes) } };
  }

  async presignDownload(key: string, ttl: number) {
    const url = await getSignedUrl(this.s3, new GetObjectCommand({ Bucket: this.bucket, Key: key }), { expiresIn: ttl });
    return { url, expiresAt: new Date(Date.now() + ttl * 1000).toISOString() };
  }

  async head(key: string) {
    try {
      const r = await this.s3.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return { sizeBytes: r.ContentLength ?? 0, mime: r.ContentType ?? 'application/octet-stream' };
    } catch (e) {
      if ((e as { name?: string }).name === 'NotFound') return null;
      throw e;
    }
  }

  async get(key: string) {
    const r = await this.s3.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    return Buffer.from(await r.Body!.transformToByteArray());
  }
}
