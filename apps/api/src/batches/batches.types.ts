export type BatchStatus = 'DRAFT' | 'COOKED' | 'WEIGHED' | 'GRADED' | 'VALIDATED';

export type Batch = {
  id: string;
  tenantId: string;
  factoryId: string;
  kloterId: string;
  panId: string;
  status: BatchStatus;
  occurredAt: string;
  createdAt: string;
  updatedAt: string;
  productionConfig: { id: string; maxNiraMl: number };
  priceVersion: { id: string; effectiveAt: string };
  contributions: Contribution[];
  cooking?: CookingRecord;
  weighing?: Weighing;
  grading?: Grading;
  reworks: Rework[];
};

export type Contribution = { id: string; kloterId: string; volumeMl: number; occurredAt: string };
export type CookingRecord = { id: string; startedAt: string; endedAt?: string; additiveIds: string[] };
export type Weighing = { id: string; caneWeightGrams?: number; sugarWeightGrams: number; occurredAt: string };
export type Grading = { id: string; gradeCode: string; sugarWeightGrams: number; occurredAt: string };
export type Rework = { id: string; sourceBatchId: string; receivingBatchId: string; weightGrams: number; status: 'RECORDED'; occurredAt: string };

export type BatchInput = {
  factoryId: string;
  kloterId: string;
  panId: string;
  occurredAt: string;
  contributions?: Array<{ kloterId: string; volumeMl: number; occurredAt?: string }>;
};
