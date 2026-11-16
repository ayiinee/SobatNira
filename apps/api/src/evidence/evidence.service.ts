import { ConflictException, Injectable, Logger } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { FactoryAccess } from '../auth/auth.types';
import { IntakeRepository } from '../documents/intake.repository';
import { found } from '../production/production.dto';
import { EvidenceRepository, publicEvidence } from './evidence.repository';
import { EvidenceFile, EvidenceUpload } from './evidence.types';
import { validateEvidence } from './evidence.validation';
import { R2EvidenceStorage } from './r2-evidence.storage';

@Injectable()
export class EvidenceService {
  private readonly logger = new Logger(EvidenceService.name);
  constructor(private readonly evidence: EvidenceRepository, private readonly documents: IntakeRepository,
    private readonly storage: R2EvidenceStorage) {}

  private editable(document: { status: string; currentRevision: number }, expected: number) {
    if (document.status !== 'draft') throw new ConflictException('Foto bukti hanya dapat diubah sebelum konfirmasi.');
    if (document.currentRevision !== expected) throw new ConflictException('Revisi dokumen berubah; muat ulang sebelum upload.');
  }

  private async cleanup(key: string) {
    try {
      // A COMMIT error may mean it actually committed. Never delete a referenced object.
      if (!await this.evidence.referenced(key)) await this.storage.remove(key);
    } catch {
      this.logger.warn('Pembersihan upload bukti yang belum tertaut perlu diperiksa setelah layanan pulih.');
    }
  }

  async upload(access: FactoryAccess, documentId: string, input: EvidenceUpload, file?: EvidenceFile) {
    const before = found(await this.documents.find(access, documentId));
    const image = await validateEvidence(file);
    const hash = createHash('sha256').update(JSON.stringify({
      expectedRevision: input.expectedRevision, reason: input.reason, sha256: image.sha256, contentType: image.contentType,
    })).digest('hex');
    const existing = await this.evidence.request(access, documentId, input.requestId);
    if (existing) {
      if (existing.requestHash !== hash) throw new ConflictException('requestId foto sudah digunakan untuk masukan berbeda.');
      return { document: found(await this.documents.find(access, documentId)), evidence: publicEvidence(existing) };
    }
    this.editable(before, input.expectedRevision);
    await this.storage.assertPrivate();
    const id = randomUUID();
    const key = `tenants/${access.tenantId}/factories/${access.factoryId}/intake-documents/${documentId}/evidence/${id}.${image.extension}`;
    let result;
    try {
      await this.storage.put(key, image);
      result = await this.documents.mutate(access, async (tx) => {
        const document = found(await this.documents.get(tx, access, documentId, true));
        const repeated = await this.evidence.byRequest(tx, access, documentId, input.requestId);
        if (repeated) {
          if (repeated.requestHash !== hash) throw new ConflictException('requestId foto sudah digunakan untuk masukan berbeda.');
          return { document, evidence: publicEvidence(repeated), storedKey: repeated.objectKey };
        }
        this.editable(document, input.expectedRevision);
        const revision = document.currentRevision + 1;
        await this.evidence.holdUpload(tx, key);
        await this.evidence.insert(tx, access, documentId, id, key, input, hash, image);
        await this.documents.revision(tx, access, documentId, revision, document.fields, input.reason, id, 'evidence_attachment');
        await this.evidence.attach(tx, access, documentId, id, revision);
        const after = found(await this.documents.get(tx, access, documentId));
        await this.documents.event(tx, access, documentId, 'evidence_attached', document, after);
        return { document: after, evidence: found(after.evidence), storedKey: key };
      });
    } catch (error) {
      await this.cleanup(key);
      throw error;
    }
    if (result.storedKey !== key) await this.cleanup(key);
    return { document: result.document, evidence: result.evidence };
  }

  async content(access: FactoryAccess, documentId: string, id: string) {
    const evidence = found(await this.evidence.stored(access, documentId, id));
    return { bytes: await this.storage.read(evidence), evidence: publicEvidence(evidence) };
  }
}
