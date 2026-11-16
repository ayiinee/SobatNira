import { MillingFields } from './milling.dto';

export const SYNTHETIC_MILLING_VERSION = 'synthetic-production-result-milling-v2';
export function syntheticMilling(lot: { id: string; receivedAt: Date }): MillingFields {
  return {
    lotId: lot.id, occurredAt: new Date(lot.receivedAt.getTime() + 3600000).toISOString(),
    juiceProducedLiters: '250', reportedBatches: [
      { batchReference: 'DEMO-BATCH-1', wokNumber: 1, totalJuiceLiters: '115', sourceJuiceLiters: '115' },
      { batchReference: 'DEMO-BATCH-2', wokNumber: 2, totalJuiceLiters: '115', sourceJuiceLiters: '115' },
    ],
  };
}
