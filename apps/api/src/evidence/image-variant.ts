import { BadRequestException, ServiceUnavailableException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import sharp = require('sharp');
import { MAX_EVIDENCE_BYTES, MAX_EVIDENCE_PIXELS } from './evidence.types';
import { imageWork } from './image-work';
import { pngHasAnimation } from './png-animation';

export const IMAGE_TRANSFORM_VERSION = 'raw-axes-webp-lossless-v1';
export type ImageVariant = 'original' | 'preview' | 'thumbnail';
export function imageVariant(query: unknown): ImageVariant {
  if (!query || typeof query !== 'object' || Array.isArray(query) || Object.keys(query).some(key => key !== 'variant')) {
    throw new BadRequestException('Parameter varian foto tidak valid.');
  }
  const variant = (query as { variant?: unknown }).variant ?? 'original';
  if (!['original', 'preview', 'thumbnail'].includes(String(variant)) || typeof variant !== 'string') {
    throw new BadRequestException('Varian foto tidak dikenal.');
  }
  return variant as ImageVariant;
}

export async function renderImageVariant(load: () => Promise<Buffer>, source: { sha256: string; bytes: number; mime: string }, variant: ImageVariant) {
  return imageWork.run(async () => {
    const bytes = await load();
    if (!bytes.length || bytes.length > MAX_EVIDENCE_BYTES || bytes.length !== source.bytes ||
        createHash('sha256').update(bytes).digest('hex') !== source.sha256) {
      throw new ServiceUnavailableException('Integritas foto tidak sesuai.');
    }
    if (variant === 'original') return { bytes, mime: source.mime, version: 'original' };
    try {
      if (pngHasAnimation(bytes)) throw new Error('Animated PNG');
      const image = sharp(bytes, { limitInputPixels: MAX_EVIDENCE_PIXELS, failOn: 'warning', animated: false }).timeout({ seconds: 10 });
      const metadata = await image.metadata();
      if ((metadata.pages ?? 1) !== 1) throw new Error('Animated source');
      const max = variant === 'preview' ? 2048 : 320;
      // Do not autoOrient/rotate: OCR coordinates refer to raw encoded pixel axes.
      // Sharp strips EXIF/GPS by default; normalized evidence coordinates stay valid.
      const result = await image.resize({ width: max, height: max, fit: 'inside', withoutEnlargement: true })
        .webp({ lossless: true, effort: 2 }).toBuffer({ resolveWithObject: true });
      if (result.data.length > MAX_EVIDENCE_BYTES) throw new Error('Variant exceeds response budget');
      return { bytes: result.data, mime: 'image/webp', version: IMAGE_TRANSFORM_VERSION,
        width: result.info.width, height: result.info.height,
        sha256: createHash('sha256').update(result.data).digest('hex') };
    } catch { throw new ServiceUnavailableException('Varian foto belum dapat dibuat; gunakan foto asli.'); }
  });
}
