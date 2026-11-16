import { BadRequestException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { mkdir, readFile, link, unlink, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { MAX_IMAGE_BYTES } from './contracts';
import { s3Send } from '../connections/s3-client';

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

  private storage(key: string) {
    if (!/^[a-f0-9]{64}$/.test(key)) throw new BadRequestException('Referensi media tidak valid');
    const bucket = process.env.R2_BUCKET;
    const endpoint = process.env.R2_ENDPOINT;
    const accessKeyId = process.env.R2_ACCESS_KEY_ID;
    const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY;
    if (bucket || endpoint || accessKeyId || secretAccessKey) {
      if (!bucket || !endpoint || !accessKeyId || !secretAccessKey || new URL(endpoint).protocol !== 'https:') {
        throw new ServiceUnavailableException('Penyimpanan R2 belum dikonfigurasi lengkap');
      }
      this.s3 ??= new S3Client({ endpoint, region: 'auto', credentials: { accessKeyId, secretAccessKey } });
      return { bucket, s3: this.s3, key: `originals/${key}` };
    }
    if (process.env.NODE_ENV === 'production' || !process.env.DOCUMENT_MEDIA_DIR) {
      throw new ServiceUnavailableException('Penyimpanan dokumen belum dikonfigurasi');
    }
    const directory = resolve(process.env.DOCUMENT_MEDIA_DIR);
    return { directory, key: resolve(directory, key) };
  }

  async put(key: string, mime: string, bytes: Buffer) {
    const storage = this.storage(key);
    if (storage.s3) {
      try {
        await s3Send(storage.s3, new PutObjectCommand({ Bucket: storage.bucket, Key: storage.key, ContentType: mime, Body: bytes, IfNoneMatch: '*' }),
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

  async read(key: string) {
    const storage = this.storage(key);
    if (!storage.s3) return readFile(storage.key);
    const { Body, ContentLength } = await s3Send<{ Body?: { transformToByteArray(): Promise<Uint8Array> }; ContentLength?: number }>(storage.s3, new GetObjectCommand({ Bucket: storage.bucket, Key: storage.key }),
      { abortSignal: AbortSignal.timeout(12_000) });
    if (!Body || ContentLength === undefined || ContentLength > MAX_IMAGE_BYTES) {
      throw new ServiceUnavailableException('Ukuran media tersimpan tidak valid');
    }
    return Buffer.from(await Body.transformToByteArray());
  }
}
