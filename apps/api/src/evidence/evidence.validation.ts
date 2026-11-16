import { BadRequestException, PayloadTooLargeException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import sharp = require('sharp');
import { expectedRevision } from '../documents/intake.dto';
import { object, text, uuid } from '../production/production.dto';
import { EvidenceFile, EvidenceImage, EvidenceUpload, MAX_EVIDENCE_BYTES, MAX_EVIDENCE_PIXELS } from './evidence.types';

export function parseEvidenceUpload(input: unknown): EvidenceUpload {
  const fields = object(input, ['requestId', 'expectedRevision', 'reason']);
  const raw = fields.expectedRevision;
  if (typeof raw !== 'string' || !/^\d+$/.test(raw)) throw new BadRequestException('expectedRevision multipart harus berupa bilangan bulat.');
  return { requestId: uuid(fields.requestId, 'requestId'), expectedRevision: expectedRevision(Number(raw)), reason: text(fields.reason, 'reason', 500) };
}

export async function validateEvidence(file?: EvidenceFile): Promise<EvidenceImage> {
  if (!file || !Buffer.isBuffer(file.buffer) || !file.buffer.length) throw new BadRequestException('Satu foto pada field file diperlukan.');
  if (file.buffer.length > MAX_EVIDENCE_BYTES) throw new PayloadTooLargeException('Ukuran foto maksimum 8 MiB.');
  const allowed: Record<string, { contentType: string; extension: string }> = {
    jpeg: { contentType: 'image/jpeg', extension: 'jpg' }, png: { contentType: 'image/png', extension: 'png' },
    webp: { contentType: 'image/webp', extension: 'webp' },
  };
  const bytes = file.buffer;
  const signature = bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ? 'png'
    : bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 ? 'jpeg'
      : bytes.length >= 12 && bytes.subarray(0, 4).toString() === 'RIFF' && bytes.subarray(8, 12).toString() === 'WEBP' ? 'webp' : undefined;
  if (!signature || allowed[signature].contentType !== file.mimetype) {
    throw new BadRequestException('Isi berkas dan MIME harus berupa JPEG, PNG, atau WebP.');
  }
  try {
    const image = sharp(file.buffer, { limitInputPixels: MAX_EVIDENCE_PIXELS, failOn: 'warning', animated: false });
    const metadata = await image.metadata();
    const format = metadata.format && Object.hasOwn(allowed, metadata.format) ? allowed[metadata.format] : undefined;
    if (!format || metadata.format !== signature || !metadata.width || !metadata.height || (metadata.pages ?? 1) !== 1) {
      throw new BadRequestException('Foto harus berupa JPEG, PNG, atau WebP statis dengan MIME yang sesuai.');
    }
    // Decode pixels as well: valid headers alone do not prove the file is intact.
    await image.stats();
    return {
      bytes: file.buffer, ...format, byteSize: file.buffer.length,
      sha256: createHash('sha256').update(file.buffer).digest('hex'), width: metadata.width, height: metadata.height,
    };
  } catch (error) {
    if (error instanceof BadRequestException) throw error;
    throw new BadRequestException('Foto rusak, tidak didukung, atau melebihi batas 20 megapiksel.');
  }
}
