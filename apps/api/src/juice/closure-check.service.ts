import { ConflictException, Inject, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { FactoryAccess } from '../auth/auth.types';
import { BACKEND_CONFIG, BackendConfig } from '../config/backend.config';

@Injectable()
export class ClosureCheckService {
  constructor(@Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  async requireClear(access: FactoryAccess, lotId: string, synthetic: boolean, authorization: string) {
    const upstream = this.config.batchClosure;
    if (!upstream) throw new ServiceUnavailableException('Backend pemeriksaan batch belum dikonfigurasi.');
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
