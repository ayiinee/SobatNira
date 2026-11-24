import { BadRequestException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { DeleteObjectCommand, GetObjectCommand, HeadBucketCommand, HeadObjectCommand, ListObjectsV2Command, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { mkdir, readFile, readdir, link, stat, unlink, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { Readable } from 'node:stream';
import { MAX_IMAGE_BYTES } from './contracts';
import { r2Settings } from './config';
import { loadConfiguration } from '../config/backend.config';
import { R2EvidenceStorage } from '../evidence/r2-evidence.storage';

export async function assertR2Privacy() {
  const config = loadConfiguration({ envFile: false });
  if (!config.r2?.publicProbeBaseUrl) throw new Error('R2: periksa R2_PUBLIC_BASE_URL');
  const storage = new R2EvidenceStorage(config);
  try { await storage.assertPrivate(); }
  catch { throw new Error('R2: pemeriksaan privasi gagal. Periksa R2_PUBLIC_BASE_URL, akses publik bucket, dan izin PutObject/DeleteObject.'); }
  finally { storage.onModuleDestroy(); }
}

export function imageMime(buffer: Buffer, declared: string) {
  const jpeg = buffer.length >= 4 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  const png = buffer.length >= 8 && buffer.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'));
  const mime = jpeg ? 'image/jpeg' : png ? 'image/png' : undefined;
  if (!mime || mime !== declared || buffer.length > MAX_IMAGE_BYTES) throw new BadRequestException('Foto JPEG atau PNG tidak valid');
  return mime;
}

@Injectable()
export class MediaStorage {
  private s3?: S3Client;

  private storage(key: string, namespace: 'originals' | 'reports' = 'originals') {
    if (!/^[a-f0-9]{64}$/.test(key)) throw new BadRequestException('Referensi media tidak valid');
    if (process.env.R2_ENDPOINT || process.env.R2_ACCOUNT_ID || process.env.R2_ACCESS_KEY_ID || process.env.R2_SECRET_ACCESS_KEY) {
      const { bucket, endpoint, region, accessKeyId, secretAccessKey } = r2Settings();
      this.s3 ??= new S3Client({ endpoint, region, forcePathStyle: true, credentials: { accessKeyId, secretAccessKey } });
      return { bucket, s3: this.s3, key: `${namespace}/${key}` };
    }
    if (process.env.NODE_ENV === 'production' || process.env.SOBATNIRA_MODE === 'connected' || !process.env.DOCUMENT_MEDIA_DIR) {
      throw new ServiceUnavailableException('Penyimpanan dokumen belum dikonfigurasi');
    }
    const directory = namespace === 'originals' ? resolve(process.env.DOCUMENT_MEDIA_DIR) :
      resolve(process.env.DOCUMENT_MEDIA_DIR, namespace);
    return { directory, key: resolve(directory, key) };
  }

  async check() {
    const storage = this.storage('0'.repeat(64));
    if (!storage.s3) {
      await mkdir(storage.directory, { recursive: true, mode: 0o700 });
      return;
    }
    await storage.s3.send(new HeadBucketCommand({ Bucket: storage.bucket }), { abortSignal: AbortSignal.timeout(5_000) });
  }

  async put(key: string, mime: string, bytes: Buffer, namespace?: 'reports') {
    if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) throw new BadRequestException('Ukuran media tidak valid');
    const storage = this.storage(key, namespace);
    if (storage.s3) {
      try {
        await storage.s3.send(new PutObjectCommand({ Bucket: storage.bucket, Key: storage.key,
          ContentType: mime, Body: bytes, IfNoneMatch: '*', CacheControl: 'private, no-store' }),
          { abortSignal: AbortSignal.timeout(12_000) });
      } catch (error) {
        if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode !== 412) throw error;
      }
      return;
    }
    await mkdir(storage.directory, { recursive: true, mode: 0o700 });
    const temporary = `${storage.key}.${randomUUID()}.tmp`;
    await writeFile(temporary, bytes, { flag: 'wx', mode: 0o600 });
    try {
      await link(temporary, storage.key);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error;
    } finally {
      await unlink(temporary);
    }
  }

  async verifiedRead(key: string, expected: { mime_type: string; size_bytes: string | number; sha256: string }) {
    try {
      const bytes = await this.read(key, undefined, expected);
      if (bytes.length !== Number(expected.size_bytes) || createHash('sha256').update(bytes).digest('hex') !== expected.sha256)
        throw invalidStoredMedia();
      imageMime(bytes, expected.mime_type);
      return bytes;
    } catch { throw invalidStoredMedia(); }
  }

  async *originals(): AsyncGenerator<{ key: string; modified: Date }> {
    const storage = this.storage('0'.repeat(64));
    if (!storage.s3) {
      for (const key of await readdir(storage.directory)) {
        if (/^[a-f0-9]{64}$/.test(key)) yield { key, modified: (await stat(resolve(storage.directory, key))).mtime };
      }
      return;
    }
    let continuation: string | undefined;
    do {
      const page = await storage.s3.send(new ListObjectsV2Command({ Bucket: storage.bucket, Prefix: 'originals/', ContinuationToken: continuation }),
        { abortSignal: AbortSignal.timeout(12_000) });
      for (const item of page.Contents ?? []) {
        const key = item.Key?.slice('originals/'.length);
        if (key && /^[a-f0-9]{64}$/.test(key) && item.LastModified) yield { key, modified: item.LastModified };
      }
      continuation = page.IsTruncated ? page.NextContinuationToken : undefined;
      if (page.IsTruncated && !continuation) throw new Error('Listing media tidak lengkap.');
    } while (continuation);
  }

  async removeOldOriginal(key: string, cutoff: Date) {
    const storage = this.storage(key);
    if (!storage.s3) {
      if ((await stat(storage.key)).mtime > cutoff) return false;
      await unlink(storage.key);
    } else {
      const head = await storage.s3.send(new HeadObjectCommand({ Bucket: storage.bucket, Key: storage.key }),
        { abortSignal: AbortSignal.timeout(12_000) });
      if (!head.LastModified || head.LastModified > cutoff) return false;
      await storage.s3.send(new DeleteObjectCommand({ Bucket: storage.bucket, Key: storage.key, IfMatch: head.ETag }),
        { abortSignal: AbortSignal.timeout(12_000) });
    }
    return true;
  }

  onModuleDestroy() { this.s3?.destroy(); }

  async read(key: string, namespace?: 'reports', expected?: { mime_type: string; size_bytes: string | number }) {
    const storage = this.storage(key, namespace);
    if (!storage.s3) {
      const info = await stat(storage.key);
      if (!info.isFile() || !info.size || info.size > MAX_IMAGE_BYTES) throw invalidStoredMedia();
      const bytes = await readFile(storage.key);
      if (bytes.length !== info.size) throw invalidStoredMedia();
      return bytes;
    }
    const { Body, ContentLength, ContentType } = await storage.s3.send(new GetObjectCommand({ Bucket: storage.bucket, Key: storage.key }),
      { abortSignal: AbortSignal.timeout(12_000) });
    if (!(Body instanceof Readable)) throw invalidStoredMedia();
    if (!ContentLength || ContentLength < 1 || ContentLength > MAX_IMAGE_BYTES ||
      (expected && (ContentType !== expected.mime_type || ContentLength !== Number(expected.size_bytes)))) {
      Body.destroy();
      throw invalidStoredMedia();
    }
    const chunks: Buffer[] = [];
    let size = 0;
    const timer = setTimeout(() => Body.destroy(new Error('Media read timeout')), 12_000);
    try {
      for await (const chunk of Body) {
        const bytes = Buffer.from(chunk);
        size += bytes.length;
        if (size > ContentLength) throw invalidStoredMedia();
        chunks.push(bytes);
      }
    } finally { clearTimeout(timer); Body.destroy(); }
    if (size !== ContentLength) throw invalidStoredMedia();
    return Buffer.concat(chunks, size);
  }
}

function invalidStoredMedia() {
  return new ServiceUnavailableException('Ukuran media tersimpan tidak valid');
}
