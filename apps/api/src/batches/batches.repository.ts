import { randomUUID } from 'node:crypto';
import { Batch, BatchInput, BatchStatus, Contribution, CookingRecord, Grading, Rework, Weighing } from './batches.types';

export interface BatchesRepository {
  list(scope: { tenantId: string; factoryId: string }, query?: { status?: BatchStatus; from?: string; to?: string }): Promise<Batch[]>;
  get(scope: { tenantId: string; factoryId: string }, id: string): Promise<Batch | undefined>;
  findAny(id: string): Promise<Batch | undefined>;
  create(scope: { tenantId: string; factoryId: string }, input: BatchInput): Promise<Batch>;
  addContribution(batch: Batch, input: Contribution): Promise<Batch>;
  setCooking(batch: Batch, cooking: CookingRecord): Promise<Batch>;
  setWeighing(batch: Batch, weighing: Weighing): Promise<Batch>;
  setGrading(batch: Batch, grading: Grading): Promise<Batch>;
  addRework(batch: Batch, rework: Rework): Promise<Batch>;
}

const now = '2026-01-01T00:00:00.000Z';
const base = (id: string, status: BatchStatus, contributions: Contribution[], extras: Partial<Batch> = {}): Batch => ({
  id, tenantId: 'tenant-demo', factoryId: 'factory-demo', kloterId: `kloter-${id}`, panId: 'pan-01', status,
  occurredAt: now, createdAt: now, updatedAt: now,
  productionConfig: { id: 'config-default', maxNiraMl: 115000 }, priceVersion: { id: 'price-demo', effectiveAt: now },
  contributions, reworks: [], ...extras,
});

export const fixtureBatches: Batch[] = [
  base('batch-normal', 'COOKED', [{ id: 'contrib-normal', kloterId: 'kloter-101', volumeMl: 100000, occurredAt: now }], { cooking: { id: 'cook-normal', startedAt: now, additiveIds: ['kapur-01'] } }),
  base('batch-mixed', 'DRAFT', [{ id: 'contrib-mixed-20', kloterId: 'kloter-102', volumeMl: 20000, occurredAt: now }, { id: 'contrib-mixed-80', kloterId: 'kloter-103', volumeMl: 80000, occurredAt: now }]),
  base('batch-weighed', 'WEIGHED', [{ id: 'contrib-weighed', kloterId: 'kloter-104', volumeMl: 95000, occurredAt: now }], { weighing: { id: 'weigh-weighed', sugarWeightGrams: 1250000, caneWeightGrams: 6000000, occurredAt: now } }),
  base('batch-graded', 'GRADED', [{ id: 'contrib-graded', kloterId: 'kloter-105', volumeMl: 105000, occurredAt: now }], { weighing: { id: 'weigh-graded', sugarWeightGrams: 1200000, occurredAt: now }, grading: { id: 'grade-graded', gradeCode: 'A', sugarWeightGrams: 1200000, occurredAt: now } }),
  base('batch-rework', 'GRADED', [{ id: 'contrib-rework', kloterId: 'kloter-106', volumeMl: 90000, occurredAt: now }], { weighing: { id: 'weigh-rework', sugarWeightGrams: 900000, occurredAt: now }, grading: { id: 'grade-rework', gradeCode: 'B', sugarWeightGrams: 900000, occurredAt: now }, reworks: [{ id: 'rework-01', sourceBatchId: 'batch-rework', receivingBatchId: 'batch-graded', weightGrams: 10000, status: 'RECORDED', occurredAt: now }] }),
];

const clone = <T>(value: T): T => structuredClone(value);

export class FixtureBatchesRepository implements BatchesRepository {
  private readonly batches = fixtureBatches.map(clone);
  async list(scope: { tenantId: string; factoryId: string }, query: { status?: BatchStatus; from?: string; to?: string } = {}) {
    return this.batches.filter((b) => b.tenantId === scope.tenantId && b.factoryId === scope.factoryId && (!query.status || b.status === query.status) && (!query.from || b.occurredAt >= query.from) && (!query.to || b.occurredAt <= query.to)).map(clone);
  }
  async get(scope: { tenantId: string; factoryId: string }, id: string) { const b = this.batches.find((item) => item.id === id && item.tenantId === scope.tenantId && item.factoryId === scope.factoryId); return b && clone(b); }
  async findAny(id: string) { const b = this.batches.find((item) => item.id === id); return b && clone(b); }
  async create(scope: { tenantId: string; factoryId: string }, input: BatchInput) {
    const item: Batch = { id: randomUUID(), tenantId: scope.tenantId, factoryId: scope.factoryId, kloterId: input.kloterId, panId: input.panId, status: 'DRAFT', occurredAt: input.occurredAt, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), productionConfig: { id: 'config-default', maxNiraMl: 115000 }, priceVersion: { id: 'price-demo', effectiveAt: new Date().toISOString() }, contributions: [], reworks: [] };
    this.batches.push(item); return clone(item);
  }
  private save(batch: Batch) { const index = this.batches.findIndex((b) => b.id === batch.id); batch.updatedAt = new Date().toISOString(); this.batches[index] = batch; return clone(batch); }
  async addContribution(batch: Batch, input: Contribution) { batch.contributions.push(input); return this.save(batch); }
  async setCooking(batch: Batch, cooking: CookingRecord) { batch.cooking = cooking; batch.status = 'COOKED'; return this.save(batch); }
  async setWeighing(batch: Batch, weighing: Weighing) { batch.weighing = weighing; batch.status = 'WEIGHED'; return this.save(batch); }
  async setGrading(batch: Batch, grading: Grading) { batch.grading = grading; batch.status = 'GRADED'; return this.save(batch); }
  async addRework(batch: Batch, rework: Rework) { batch.reworks.push(rework); return this.save(batch); }
}

/** Supabase adapter uses PostgREST and keeps domain mapping in service. */
export class SupabaseBatchesRepository extends FixtureBatchesRepository {
  private readonly baseUrl = `${process.env.SUPABASE_URL ?? ''}/rest/v1`;
  private readonly key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_SECRET_KEY ?? process.env.SUPABASE_ANON_KEY ?? process.env.SUPABASE_PUBLISHABLE_KEY ?? '';
  private async request(path: string, init: RequestInit = {}) {
    if (!this.baseUrl || !this.key) throw new Error('SUPABASE_URL and Supabase key are required for DATA_MODE=supabase');
    const response = await fetch(`${this.baseUrl}${path}`, { ...init, headers: { apikey: this.key, Authorization: `Bearer ${this.key}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
    if (!response.ok) throw new Error(`Supabase request failed: ${response.status}`);
    return response;
  }
  private mapRow(row: Record<string, any>): Batch {
    const contributions = (row.batch_nira_contributions ?? []).map((item: any) => ({ id: item.id, kloterId: item.kloter_id, volumeMl: item.volume_ml, occurredAt: item.occurred_at }));
    const cooking = row.cooking_records?.[0];
    const weighing = row.weighings?.[0];
    const grading = row.batch_grades?.[0];
    return { id: row.id, tenantId: row.tenant_id, factoryId: row.factory_id, kloterId: row.kloter_id, panId: row.pan_id, status: row.status, occurredAt: row.occurred_at, createdAt: row.created_at, updatedAt: row.updated_at, productionConfig: { id: row.production_config_id, maxNiraMl: 115000 }, priceVersion: { id: row.price_version_id, effectiveAt: row.created_at }, contributions, cooking: cooking && { id: cooking.id, startedAt: cooking.started_at, endedAt: cooking.ended_at, additiveIds: cooking.additive_ids ?? [] }, weighing: weighing && { id: weighing.id, caneWeightGrams: weighing.cane_weight_grams, sugarWeightGrams: weighing.sugar_weight_grams, occurredAt: weighing.occurred_at }, grading: grading && { id: grading.id, gradeCode: grading.grades?.code ?? grading.grade_id, sugarWeightGrams: grading.sugar_weight_grams, occurredAt: grading.occurred_at }, reworks: (row.reworks ?? []).map((item: any) => ({ id: item.id, sourceBatchId: item.source_batch_id, receivingBatchId: item.receiving_batch_id, weightGrams: item.weight_grams, status: item.status, occurredAt: item.occurred_at })) };
  }
  override async list(scope: { tenantId: string; factoryId: string }, query: { status?: BatchStatus; from?: string; to?: string } = {}) {
    const params = new URLSearchParams({ tenant_id: `eq.${scope.tenantId}`, factory_id: `eq.${scope.factoryId}`, select: '*,batch_nira_contributions(*),cooking_records(*),weighings(*),batch_grades(*,grades(code)),reworks(*)' });
    if (query.status) params.set('status', `eq.${query.status}`);
    const response = await this.request(`/batches?${params}`); return ((await response.json()) as Record<string, any>[]).map((row) => this.mapRow(row));
  }
  override async get(scope: { tenantId: string; factoryId: string }, id: string) { const rows = await this.list(scope); return rows.find((row) => row.id === id); }
  override async findAny(id: string) { const response = await this.request(`/batches?id=eq.${encodeURIComponent(id)}&select=*`); const row = ((await response.json()) as Record<string, any>[])[0]; return row && this.mapRow(row); }
  private async mutate(path: string, body: Record<string, unknown>, method = 'POST') { await this.request(path, { method, headers: { Prefer: 'return=minimal' }, body: JSON.stringify(body) }); }
  override async create(scope: { tenantId: string; factoryId: string }, input: BatchInput) {
    const productionConfigId = process.env.DEFAULT_PRODUCTION_CONFIG_ID;
    const priceVersionId = process.env.DEFAULT_PRICE_VERSION_ID;
    if (!productionConfigId || !priceVersionId) throw new Error('DEFAULT_PRODUCTION_CONFIG_ID and DEFAULT_PRICE_VERSION_ID are required for Supabase batch writes');
    await this.mutate('/batches', { tenant_id: scope.tenantId, factory_id: scope.factoryId, kloter_id: input.kloterId, pan_id: input.panId, status: 'DRAFT', occurred_at: input.occurredAt, production_config_id: productionConfigId, price_version_id: priceVersionId });
    const rows = await this.list(scope); const created = rows.sort((a, b) => b.createdAt.localeCompare(a.createdAt))[0]; if (!created) throw new Error('Supabase batch insert returned no row'); return created;
  }
  override async addContribution(batch: Batch, input: Contribution) { await this.mutate('/batch_nira_contributions', { tenant_id: batch.tenantId, factory_id: batch.factoryId, batch_id: batch.id, kloter_id: input.kloterId, volume_ml: input.volumeMl, occurred_at: input.occurredAt }); return (await this.get({ tenantId: batch.tenantId, factoryId: batch.factoryId }, batch.id))!; }
  override async setCooking(batch: Batch, cooking: CookingRecord) { await this.mutate('/cooking_records', { tenant_id: batch.tenantId, factory_id: batch.factoryId, batch_id: batch.id, started_at: cooking.startedAt, ended_at: cooking.endedAt, additive_ids: cooking.additiveIds }); await this.mutate(`/batches?id=eq.${batch.id}`, { status: 'COOKED' }, 'PATCH'); return (await this.get({ tenantId: batch.tenantId, factoryId: batch.factoryId }, batch.id))!; }
  override async setWeighing(batch: Batch, weighing: Weighing) { await this.mutate('/weighings', { tenant_id: batch.tenantId, factory_id: batch.factoryId, batch_id: batch.id, cane_weight_grams: weighing.caneWeightGrams, sugar_weight_grams: weighing.sugarWeightGrams, occurred_at: weighing.occurredAt }); await this.mutate(`/batches?id=eq.${batch.id}`, { status: 'WEIGHED' }, 'PATCH'); return (await this.get({ tenantId: batch.tenantId, factoryId: batch.factoryId }, batch.id))!; }
  override async setGrading(batch: Batch, grading: Grading) { const gradeResponse = await this.request(`/grades?code=eq.${encodeURIComponent(grading.gradeCode)}&factory_id=eq.${encodeURIComponent(batch.factoryId)}&select=id`); const grade = ((await gradeResponse.json()) as Array<{ id: string }>)[0]; if (!grade) throw new Error(`Grade ${grading.gradeCode} tidak ditemukan`); await this.mutate('/batch_grades', { tenant_id: batch.tenantId, factory_id: batch.factoryId, batch_id: batch.id, grade_id: grade.id, sugar_weight_grams: grading.sugarWeightGrams, occurred_at: grading.occurredAt }); await this.mutate(`/batches?id=eq.${batch.id}`, { status: 'GRADED' }, 'PATCH'); return (await this.get({ tenantId: batch.tenantId, factoryId: batch.factoryId }, batch.id))!; }
  override async addRework(batch: Batch, rework: Rework) { await this.mutate('/reworks', { tenant_id: batch.tenantId, factory_id: batch.factoryId, source_batch_id: rework.sourceBatchId, receiving_batch_id: rework.receivingBatchId, weight_grams: rework.weightGrams, status: rework.status, occurred_at: rework.occurredAt }); return (await this.get({ tenantId: batch.tenantId, factoryId: batch.factoryId }, batch.id))!; }
}
