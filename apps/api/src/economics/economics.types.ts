export type SugarMovement = {
  id: string;
  tenantId: string;
  factoryId: string;
  gradeCode: string;
  deltaGrams: number;
  reason: string;
  batchId?: string;
  correctionOfMovementId?: string;
  occurredAt: string;
  createdAt: string;
};

export type AuditEvent = {
  id: string;
  tenantId: string;
  factoryId: string;
  entityType: string;
  entityId: string;
  action: string;
  reason: string;
  occurredAt: string;
};

export type Allocation = {
  kloterId: string;
  proportion: number;
  costRupiah: number;
  revenueRupiah: number;
  marginRupiah: number;
};
