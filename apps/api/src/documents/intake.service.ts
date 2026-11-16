import { ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { FactoryAccess } from '../auth/auth.types';
import { BACKEND_CONFIG, BackendConfig } from '../config/backend.config';
import { found } from '../production/production.dto';
import { completeFields, DraftUpdate, IntakeFields, SyntheticRequest } from './intake.dto';
import { IntakeDocument, IntakeRepository } from './intake.repository';
import { syntheticIntake, SYNTHETIC_INTAKE_VERSION } from './synthetic-intake.fixture';

function revisionMatches(document: IntakeDocument, expected: number) {
  if (document.currentRevision !== expected) throw new ConflictException('Revisi sudah berubah; muat ulang dokumen.');
}
function sameFields(a: IntakeFields, b: IntakeFields): boolean {
  return (Object.keys(a) as (keyof IntakeFields)[]).every((key) => a[key] === b[key]);
}

@Injectable()
export class IntakeService {
  constructor(private readonly repository: IntakeRepository, @Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  createSynthetic(access: FactoryAccess, input: SyntheticRequest) {
    if (this.config.environment === 'production') throw new NotFoundException();
    const hash = createHash('sha256').update(JSON.stringify({ version: SYNTHETIC_INTAKE_VERSION, lotId: input.lotId })).digest('hex');
    return this.repository.mutate(access, async (tx) => {
      const existing = await this.repository.sourceId(tx, access, input.requestId);
      if (existing) {
        const document = found(await this.repository.get(tx, access, existing));
        if (document.sourcePayloadHash !== hash) throw new ConflictException('requestId sudah digunakan untuk masukan yang berbeda.');
        return document;
      }
      const lot = found(await this.repository.lot(tx, access, input.lotId));
      const fields = syntheticIntake(lot);
      const id = await this.repository.insert(tx, access, lot.id, input.requestId, hash,
        { version: SYNTHETIC_INTAKE_VERSION, evidence: { kind: 'synthetic_fixture' }, fields });
      if (!id) {
        // A conflicting insert can become visible only on the following READ COMMITTED query.
        const conflictId = found(await this.repository.sourceId(tx, access, input.requestId));
        const document = found(await this.repository.get(tx, access, conflictId));
        if (document.sourcePayloadHash !== hash) throw new ConflictException('requestId sudah digunakan untuk masukan yang berbeda.');
        return document;
      }
      await this.repository.revision(tx, access, id, 1, fields);
      const document = found(await this.repository.get(tx, access, id));
      await this.repository.event(tx, access, id, 'created', null, document);
      return document;
    });
  }

  update(access: FactoryAccess, id: string, input: DraftUpdate) {
    return this.repository.mutate(access, async (tx) => {
      const before = found(await this.repository.get(tx, access, id, true));
      revisionMatches(before, input.expectedRevision);
      if (before.status === 'approved') throw new ConflictException('Dokumen sah memerlukan alur koreksi resmi; draf tidak dapat diubah.');
      const fields = { ...before.fields, ...input.changes };
      const lot = found(await this.repository.lot(tx, access, fields.lotId));
      fields.supplierId = lot.supplierId;
      if (sameFields(before.fields, fields)) return before;
      const next = before.currentRevision + 1;
      await this.repository.revision(tx, access, id, next, fields, input.reason, before.evidence?.id ?? null);
      await this.repository.advance(tx, access, id, next, lot.id);
      const after = found(await this.repository.get(tx, access, id));
      await this.repository.event(tx, access, id, 'draft_updated', before, after);
      return after;
    });
  }

  confirmSynthetic(access: FactoryAccess, id: string, expected: number) {
    if (this.config.environment === 'production') throw new NotFoundException();
    return this.repository.mutate(access, async (tx) => {
      const before = found(await this.repository.get(tx, access, id, true));
      if (before.confirmedRevision === expected && before.status !== 'draft') return before;
      revisionMatches(before, expected);
      if (before.status !== 'draft') throw new ConflictException('Konfirmasi sudah tercatat pada revisi yang berbeda.');
      const fields = completeFields(before.fields);
      const lot = found(await this.repository.lot(tx, access, before.lotId));
      if (lot.supplierId !== fields.supplierId) throw new ConflictException('Pemasok kloter berubah; periksa dan perbarui draf.');
      await this.repository.confirm(tx, access, id, expected);
      const after = found(await this.repository.get(tx, access, id));
      await this.repository.event(tx, access, id, 'confirmed', before, after);
      return after;
    });
  }

  approve(access: FactoryAccess, id: string, expected: number) {
    return this.repository.mutate(access, async (tx) => {
      const before = found(await this.repository.get(tx, access, id, true));
      revisionMatches(before, expected);
      if (before.status === 'approved') {
        if (!before.intake) throw new ConflictException('Referensi penerimaan sah tidak lengkap.');
        return before;
      }
      if (before.status !== 'awaiting_validation') throw new ConflictException('Dokumen harus dikonfirmasi sebelum disahkan.');
      const fields = completeFields(before.fields);
      const lot = found(await this.repository.lot(tx, access, before.lotId));
      if (fields.lotId !== lot.id || fields.supplierId !== lot.supplierId) {
        throw new ConflictException('Relasi kloter/pemasok berubah; periksa dan perbarui draf.');
      }
      if (await this.repository.existingIntake(tx, access, lot.id)) {
        throw new ConflictException('Kloter sudah memiliki penerimaan sah; gunakan alur koreksi resmi.');
      }
      await this.repository.approve(tx, access, before, lot, fields);
      const after = found(await this.repository.get(tx, access, id));
      await this.repository.event(tx, access, id, 'approved', before, after);
      return after;
    });
  }
}
