import { IntakeFields } from './intake.dto';

export const SYNTHETIC_INTAKE_VERSION = 'synthetic-cane-intake-v1';

export function syntheticIntake(lot: { id: string; supplierId: string; receivedAt: Date }): IntakeFields {
  return {
    lotId: lot.id, supplierId: lot.supplierId, occurredAt: lot.receivedAt.toISOString(),
    caneTypeCode: 'BL', netWeightKg: '1250', brix: '18.5',
  };
}
