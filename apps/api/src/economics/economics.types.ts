export type SugarMovement = {
  id: string;
  tenantId: string;
  factoryId: string;
  gradeCode: string;
  deltaGrams: number;
  reason: string;
  batchId?: string;
  occurredAt: string;
  createdAt: string;
};

export type Allocation = {
  kloterId: string;
  proportion: number;
  costRupiah: number;
  revenueRupiah: number;
  marginRupiah: number;
};
