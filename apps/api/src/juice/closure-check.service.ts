import { ConflictException, Inject, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { DatabaseSession } from '../database/database.service';
import { FactoryAccess } from '../auth/auth.types';
import { BACKEND_CONFIG, BackendConfig } from '../config/backend.config';

@Injectable()
export class ClosureCheckService {
  constructor(@Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  async requireClear(tx: DatabaseSession, access: FactoryAccess, lotId: string, synthetic: boolean, authorization: string) {
    const correction = await tx.query(`SELECT 1 FROM sobatnira.production_batch_corrections c
      JOIN sobatnira.production_batches b ON b.id=c.batch_id
      WHERE b.tenant_id=$1 AND b.factory_id=$2 AND b.lot_id=$3 AND b.is_synthetic=$4 AND c.status='draft' LIMIT 1`,
      [access.tenantId, access.factoryId, lotId, synthetic]);
    if (correction.rows.length) throw new ConflictException('Selesaikan koreksi batch sebelum menutup kloter.');
    const upstream = synthetic && this.config.environment !== 'production' ? this.config.batchClosure : undefined;
    if (!upstream) {
      const { rows: [result] } = await tx.query<{blocked:boolean}>(`SELECT
        EXISTS(SELECT 1 FROM sobatnira.production_batches WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4 AND status='draft')
        OR EXISTS(SELECT 1 FROM sobatnira.juice_reservations r WHERE r.tenant_id=$1 AND r.factory_id=$2 AND r.origin_lot_id=$3 AND r.is_synthetic=$4 AND r.state IN ('reserved','consumed')
          AND NOT EXISTS(SELECT 1 FROM sobatnira.production_batches b WHERE b.id=r.batch_id AND b.tenant_id=r.tenant_id AND b.factory_id=r.factory_id AND b.status='approved' AND b.is_synthetic=r.is_synthetic)) AS blocked`,
        [access.tenantId,access.factoryId,lotId,synthetic]);
      if(result.blocked) throw new ConflictException('Selesaikan pengesahan batch sebelum menutup kloter.');
      return;
    }
    const url = new URL('/batches/closure-check/' + lotId, upstream.baseUrl);
    url.searchParams.set('tenantId', access.tenantId);
    url.searchParams.set('factoryId', access.factoryId);
    url.searchParams.set('synthetic', String(synthetic));

    let canClose: boolean;
    try {
      const response = await fetch(url, {
        headers: { Authorization: authorization, Accept: 'application/json' },
        signal: AbortSignal.timeout(upstream.timeoutMs),
        redirect: 'error',
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new Error('Batch service rejected closure check');
      }
      const result = await response.json() as { canClose?: unknown } | null;
      if (typeof result?.canClose !== 'boolean') throw new Error('Invalid closure check response');
      canClose = result.canClose;
    } catch {
      throw new ServiceUnavailableException('Pemeriksaan batch belum tersedia.');
    }
    if (!canClose) throw new ConflictException('Backend batch belum mengizinkan penutupan kloter.');
  }
}
