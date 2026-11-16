import { ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { FactoryAccess } from '../auth/auth.types';
import { BACKEND_CONFIG, BackendConfig } from '../config/backend.config';
import { SyntheticRequest } from '../documents/intake.dto';
import { found } from '../production/production.dto';
import { completeMillingFields, MillingUpdate } from './milling.dto';
import { MillingDocument, MillingRepository } from './milling.repository';
import { syntheticMilling, SYNTHETIC_MILLING_VERSION } from './synthetic-milling.fixture';

function revisionMatches(document: MillingDocument, expected: number) {
  if (document.currentRevision !== expected) throw new ConflictException('Revisi sudah berubah; muat ulang dokumen.');
}

@Injectable()
export class MillingService {
  constructor(private readonly repository: MillingRepository, @Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  createSynthetic(access: FactoryAccess, input: SyntheticRequest) {
    if (this.config.environment === 'production') throw new NotFoundException();
    const hash = createHash('sha256').update(JSON.stringify({ version: SYNTHETIC_MILLING_VERSION, lotId: input.lotId })).digest('hex');
    return this.repository.mutate(access, async (tx) => {
      const existing = await this.repository.sourceId(tx, access, input.requestId);
      if (existing) {
        const doc = found(await this.repository.get(tx, access, existing));
        if (doc.sourcePayloadHash !== hash) throw new ConflictException('requestId sudah digunakan untuk masukan yang berbeda.');
        return doc;
      }
      const lot = found(await this.repository.lot(tx, access, input.lotId));
      const fields = syntheticMilling(lot);
      const id = await this.repository.insert(tx, access, lot.id, input.requestId, hash,
        { version: SYNTHETIC_MILLING_VERSION, noteKind: 'combined_production_result', evidence: { kind: 'synthetic_fixture' }, fields });
      if (!id) {
        const conflict = found(await this.repository.sourceId(tx, access, input.requestId));
        const doc = found(await this.repository.get(tx, access, conflict));
        if (doc.sourcePayloadHash !== hash) throw new ConflictException('requestId sudah digunakan untuk masukan yang berbeda.');
        return doc;
      }
      await this.repository.revision(tx, access, id, 1, fields);
      const doc = found(await this.repository.get(tx, access, id));
      await this.repository.event(tx, access, id, 'created', null, doc);
      return doc;
    });
  }

  update(access: FactoryAccess, id: string, input: MillingUpdate) {
    return this.repository.mutate(access, async (tx) => {
      const before = found(await this.repository.get(tx, access, id, true));
      revisionMatches(before, input.expectedRevision);
      if (before.status === 'approved') throw new ConflictException('Dokumen sah memerlukan alur koreksi resmi; draf tidak dapat diubah.');
      const fields = { ...before.fields, ...input.changes };
      const lot = found(await this.repository.lot(tx, access, fields.lotId));
      if (JSON.stringify(fields) === JSON.stringify(before.fields)) return before;
      const next = before.currentRevision + 1;
      await this.repository.revision(tx, access, id, next, fields, input.reason);
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
      completeMillingFields(before.fields);
      found(await this.repository.lot(tx, access, before.lotId));
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
        if (!before.milling) throw new ConflictException('Referensi penggilingan sah tidak lengkap.');
        return before;
      }
      if (before.status !== 'awaiting_validation') throw new ConflictException('Nota hasil harus dikonfirmasi sebelum disahkan.');
      const fields = completeMillingFields(before.fields);
      // Serialize every stock-changing operation on this lot, including intake approval.
      const lot = found(await this.repository.lot(tx, access, before.lotId));
      if (fields.lotId !== lot.id) throw new ConflictException('Relasi kloter berubah; periksa draf.');
      const intake = await this.repository.intakeAndBalance(tx, access, lot.id);
      if (!intake) throw new ConflictException('Sahkan penerimaan tebu kloter ini terlebih dahulu.');
      if (intake.alreadyMilled) throw new ConflictException('Penggilingan kloter sudah dibukukan; gunakan alur koreksi resmi.');
      if (!intake.stockMatches) throw new ConflictException('Saldo tebu tidak sesuai penerimaan sah; rekonsiliasi stok terlebih dahulu.');
      if (new Date(fields.occurredAt).getTime() < intake.occurredAt.getTime()) {
        throw new ConflictException('Waktu penggilingan tidak boleh mendahului penerimaan tebu.');
      }
      await this.repository.approve(tx, access, before, fields, intake);
      const after = found(await this.repository.get(tx, access, id));
      await this.repository.event(tx, access, id, 'approved', before, after);
      return after;
    });
  }
}
