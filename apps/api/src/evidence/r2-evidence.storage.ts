import { Inject, Injectable, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { DeleteObjectCommand, GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { createHash, randomUUID } from 'node:crypto';
import { Readable } from 'node:stream';
import { BACKEND_CONFIG, BackendConfig } from '../config/backend.config';
import { EvidenceImage, MAX_EVIDENCE_BYTES, StoredEvidence } from './evidence.types';

@Injectable()
export class R2EvidenceStorage implements OnModuleDestroy {
  private client?: S3Client;
  constructor(@Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  private settings() {
    if (!this.config.r2) throw new ServiceUnavailableException('Penyimpanan bukti belum dikonfigurasi.');
    return this.config.r2;
  }
  private s3() {
    const settings = this.settings();
    this.client ??= new S3Client({
      endpoint: settings.endpoint, region: settings.region, forcePathStyle: true,
      credentials: { accessKeyId: settings.accessKeyId, secretAccessKey: settings.secretAccessKey },
      maxAttempts: 1, requestHandler: { connectionTimeout: this.config.timeoutMs, requestTimeout: this.config.timeoutMs },
    });
    return this.client;
  }

  async assertPrivate() {
    const publicBase = this.settings().publicProbeBaseUrl;
    if (!publicBase) return; // Operator must still disable every public domain on the bucket.
    const key = `privacy-checks/${randomUUID()}.txt`;
    let error: unknown;
    try {
      await this.s3().send(new PutObjectCommand({ Bucket: this.settings().bucket, Key: key,
        Body: 'SobatNira synthetic privacy probe', ContentType: 'text/plain', CacheControl: 'no-store' }),
      { abortSignal: AbortSignal.timeout(this.config.timeoutMs) });
      const response = await fetch(new URL(key, new URL(publicBase).origin + '/'), {
        signal: AbortSignal.timeout(this.config.timeoutMs), redirect: 'error',
      });
      await response.body?.cancel();
      if (![401, 403, 404].includes(response.status)) {
        throw new ServiceUnavailableException('Privasi bucket belum terverifikasi; nonaktifkan akses publik R2 sebelum mengunggah bukti.');
      }
    } catch (caught) { error = caught; }
    finally {
      try { await this.remove(key); }
      catch { error ??= new ServiceUnavailableException('Pemeriksaan privasi R2 belum selesai.'); }
    }
    if (error) {
      if (error instanceof ServiceUnavailableException) throw error;
      throw new ServiceUnavailableException('Privasi bucket R2 belum dapat diperiksa.');
    }
  }

  async put(key: string, image: EvidenceImage) {
    try {
      await this.s3().send(new PutObjectCommand({
        Bucket: this.settings().bucket, Key: key, Body: image.bytes, ContentLength: image.byteSize,
        ContentType: image.contentType, CacheControl: 'private, no-store', Metadata: { sha256: image.sha256 },
      }), { abortSignal: AbortSignal.timeout(this.config.timeoutMs) });
    } catch { throw new ServiceUnavailableException('Upload foto bukti ke R2 gagal.'); }
  }

  async read(evidence: StoredEvidence): Promise<Buffer> {
    let stream: Readable | undefined;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const object = await this.s3().send(new GetObjectCommand({ Bucket: this.settings().bucket, Key: evidence.objectKey }),
        { abortSignal: AbortSignal.timeout(this.config.timeoutMs) });
      stream = object.Body as Readable | undefined;
      if (!stream || object.ContentLength !== evidence.byteSize || object.ContentLength > MAX_EVIDENCE_BYTES || object.ContentType !== evidence.contentType) {
        throw new Error('Evidence metadata mismatch');
      }
      const body = stream;
      timer = setTimeout(() => body.destroy(new Error('Evidence read timeout')), this.config.timeoutMs);
      const chunks: Buffer[] = [];
      let size = 0;
      for await (const chunk of body) {
        const buffer = Buffer.from(chunk);
        size += buffer.length;
        if (size > evidence.byteSize) throw new Error('Evidence size mismatch');
        chunks.push(buffer);
      }
      const bytes = Buffer.concat(chunks);
      if (bytes.length !== evidence.byteSize || createHash('sha256').update(bytes).digest('hex') !== evidence.sha256) {
        throw new Error('Evidence content mismatch');
      }
      return bytes;
    } catch { throw new ServiceUnavailableException('Foto bukti tidak tersedia atau integritas berkas tidak sesuai.'); }
    finally { if (timer) clearTimeout(timer); stream?.destroy(); }
  }

  async remove(key: string) {
    try {
      await this.s3().send(new DeleteObjectCommand({ Bucket: this.settings().bucket, Key: key }),
        { abortSignal: AbortSignal.timeout(this.config.timeoutMs) });
    } catch { throw new ServiceUnavailableException('Objek R2 belum dapat dibersihkan.'); }
  }

  onModuleDestroy() { this.client?.destroy(); }
}
