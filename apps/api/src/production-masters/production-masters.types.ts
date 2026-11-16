export type ProductionMaster = {
  id: string;
  tenantId: string;
  factoryId: string;
  code: string;
  name: string;
  createdAt: string;
  updatedAt: string;
};

export type ProductionConfig = ProductionMaster & { maxNiraMl: number };
export type PriceVersion = ProductionMaster & { effectiveAt: string; prices: Record<string, number> };
export type MasterKind = 'pans' | 'grades' | 'additives';
