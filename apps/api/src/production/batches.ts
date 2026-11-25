import { SugarInventory } from './sugar-inventory';
import { assertBatchSource, batchSourceRows, parseBatchSource } from './batch-sources';
import { BadRequestException, Body, ConflictException, Controller, Get, HttpCode, Injectable, Param, Patch, Post, Query } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { JuiceRepository } from '../juice/juice.repository';
import { reopenActiveClosure } from '../juice/lot-closure.service';
import { object, uuid, text, timestamp, scopeValues, found, parsePage } from './production.dto';
import { decimal, sumDecimals, compareDecimals } from './decimal';
import { calculateProductionPreview } from './calculation';
import { rebuildSnapshots } from './snapshots';
import { batchGradeTotals, type Grade, productionReport, ProductionReportLot, reportProductionSelection, reportSelection, type ReportSelection } from './production-report';
import { REPORT_MAX_LOTS, boundedReport, reportPeriod } from './report-limits';

type ReportPeriod = { from: string; before: string; synthetic: string };

function checkReportSize(items: ProductionReportLot[], maxLots?: number) {
    if (items.some(lot => lot.batches.length > 1000)) {
        throw new BadRequestException('Laporan melebihi 1000 batch per kloter. Hubungi admin untuk pembagian laporan.');
    }
    if (maxLots !== undefined && items.length > maxLots) {
        throw new BadRequestException('Persempit periode laporan atau gunakan ekspor asinkron agar semua kloter dapat dihitung.');
    }
}
export function assertGradeWeight(physicalWeightKg: string, grades: Grade[]) {
    if (compareDecimals(sumDecimals(grades.map(g => g.weightKg)), physicalWeightKg) !== 0)
        throw new BadRequestException('Total berat grade harus sama dengan berat fisik batch.');
}

export function parseBatch(input: unknown) {
    const b = object(input, ['id', 'lotId', 'code', 'wokNumber', 'occurredAt', 'quantityMl', 'physicalWeightKg', 'grades', 'synthetic', 'source']);
    if (!Number.isSafeInteger(b.wokNumber) || Number(b.wokNumber) < 1 || Number(b.wokNumber) > 10000)
        throw new BadRequestException('Nomor wajan tidak valid.');
    if (b.synthetic !== undefined && typeof b.synthetic !== 'boolean')
        throw new BadRequestException('synthetic harus boolean.');
    // Reuse exact calculator validation for weights, prices and duplicate grade codes.
    const calculation = calculateProductionPreview({ caneNetKg: '1', caneCostRupiah: '0', operationalCostRupiah: '0', ingredientCostRupiah: '0', otherCostRupiah: '0', rounding: 'HALF_UP', grades: b.grades });
    return { source: parseBatchSource(b.source), id: uuid(b.id), lotId: uuid(b.lotId), code: text(b.code, 'code', 100), wokNumber: Number(b.wokNumber), occurredAt: timestamp(b.occurredAt, 'occurredAt'), quantityMl: decimal(b.quantityMl, 'quantityMl'), physicalWeightKg: decimal(b.physicalWeightKg, 'physicalWeightKg'), grades: calculation.grades.map(g => ({ code: g.code, weightKg: g.weightKg, pricePerKgRupiah: g.pricePerKgRupiah })), synthetic: b.synthetic === true };
}

function correctionData(physicalWeight: unknown, grades: unknown) {
    const preview = calculateProductionPreview({ caneNetKg: '1', caneCostRupiah: '0',
        operationalCostRupiah: '0', ingredientCostRupiah: '0', otherCostRupiah: '0',
        rounding: 'HALF_UP', grades });
    return { physicalWeightKg: decimal(physicalWeight, 'physicalWeightKg'),
        grades: preview.grades.map(({code, weightKg, pricePerKgRupiah}) => ({code, weightKg, pricePerKgRupiah})) };
}
@Injectable()
export class Batches {
    constructor(private readonly db: DatabaseService, private readonly juice: JuiceRepository, private readonly inventory: SugarInventory) { }
    async create(access: FactoryAccess, input: unknown) {
        const b = parseBatch(input);
        const hash = createHash('sha256').update(JSON.stringify(b)).digest('hex');
        return this.juice.mutate(access, async (tx) => {
            await this.juice.lockLots(tx, access, [b.lotId]);
            const old = (await tx.query('SELECT * FROM sobatnira.production_batches WHERE id=$1', [b.id])).rows[0];
            if (old) {
                if (old.tenant_id !== access.tenantId || old.factory_id !== access.factoryId || old.input_hash !== hash)
                    throw new ConflictException('ID batch sudah dipakai.');
                return old;
            }
            await assertBatchSource(tx, access, b.lotId, b.source, b.id);
            const scope = [access.tenantId, access.factoryId, b.lotId, b.synthetic];
            const source = await tx.query('SELECT occurred_at FROM sobatnira.milling_records WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4', scope);
            if (!source.rows.length || new Date(source.rows[0].occurred_at).getTime() > Date.parse(b.occurredAt))
                throw new ConflictException('Batch memerlukan penggilingan sah sebelum waktu memasak.');
            const closed = await tx.query('SELECT 1 FROM sobatnira.lot_closures WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4 AND reopened_at IS NULL', scope);
            if (closed.rows.length)
                throw new ConflictException('Kloter sudah ditutup.');
            const result = await tx.query(`INSERT INTO sobatnira.production_batches(id,tenant_id,factory_id,lot_id,code,wok_number,occurred_at,quantity_ml,physical_weight_kg,is_synthetic,input_hash,created_by,source_document_id,source_revision_id,source_block,source_row)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16) RETURNING *`, [b.id, access.tenantId, access.factoryId, b.lotId, b.code, b.wokNumber, b.occurredAt, b.quantityMl, b.physicalWeightKg, b.synthetic, hash, access.userId, b.source?.documentId ?? null,b.source?.revisionId ?? null,b.source?.block ?? null,b.source?.rowReference ?? null]);
            for (const g of b.grades)
                await tx.query('INSERT INTO sobatnira.batch_grade_results(batch_id,code,weight_kg,price_per_kg_rupiah) VALUES($1,$2,$3,$4)', [b.id, g.code, g.weightKg, g.pricePerKgRupiah]);
            await tx.query("INSERT INTO sobatnira.production_batch_events(batch_id,action,actor_id) VALUES($1,'created',$2)", [b.id, access.userId]);
            return result.rows[0];
        });
    }
    async sources(access: FactoryAccess, lotId: string) {
        await this.db.query(`WITH ${FACTORY_SCOPE_CTE} SELECT l.id FROM sobatnira.lots l JOIN authorized_scope s ON (s."tenantId",s."factoryId")=(l.tenant_id,l.factory_id) WHERE l.id=$4`, [...scopeValues(access),lotId]).then(r => found(r.rows[0]));
        return {items: await batchSourceRows(this.db, access, lotId)};
    }
    async costs(access: FactoryAccess, lotId: string, input: unknown) {
        const { version, ...b } = object(input, ['version', 'caneCostRupiah', 'operationalCostRupiah', 'ingredientCostRupiah', 'otherCostRupiah']);
        if (version !== undefined && (!Number.isSafeInteger(version) || Number(version) < 0))
            throw new BadRequestException('Versi biaya tidak valid.');
        const c = calculateProductionPreview({ ...b, caneNetKg: '1', rounding: 'HALF_UP', grades: [{ code: 'CHECK', weightKg: '1', pricePerKgRupiah: '0' }] }).costs;
        return this.juice.mutate(access, async (tx) => {
            await this.juice.lockLots(tx, access, [lotId]);
            const approved = await tx.query('SELECT 1 FROM sobatnira.production_calculation_snapshots WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3', [access.tenantId, access.factoryId, lotId]);
            if (approved.rows.length)
                throw new ConflictException({ code: 'LOT_COST_FROZEN', message: 'Biaya historis sudah dibekukan. Ajukan koreksi biaya.' });
            const old = (await tx.query('SELECT version FROM sobatnira.lot_production_costs WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 FOR UPDATE', [access.tenantId, access.factoryId, lotId])).rows[0];
            if ((version !== undefined && (old?.version ?? 0) !== version) ||
                (old && version === undefined && process.env.LOT_COST_REQUIRE_VERSION === 'true'))
                throw new ConflictException({ code: 'LOT_COST_VERSION_CONFLICT', message: 'Biaya sudah berubah atau aplikasi belum mendukung versi. Muat ulang atau perbarui aplikasi.' });
            return (await tx.query(`INSERT INTO sobatnira.lot_production_costs(tenant_id,factory_id,lot_id,cane_rupiah,operational_rupiah,ingredient_rupiah,other_rupiah,created_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(tenant_id,factory_id,lot_id) DO UPDATE SET cane_rupiah=$4,operational_rupiah=$5,ingredient_rupiah=$6,other_rupiah=$7,version=sobatnira.lot_production_costs.version+1,updated_by=$8,updated_at=clock_timestamp() RETURNING *`, [access.tenantId, access.factoryId, lotId, c.caneRupiah, c.operationalRupiah, c.ingredientRupiah, c.otherRupiah, access.userId])).rows[0];
        });
    }
    async approve(access: FactoryAccess, id: string) {
        return this.juice.mutate(access, async (tx) => {
            const b = await this.lockBatch(tx, access, id);
            if (b.status === 'approved')
                return found((await tx.query('SELECT * FROM sobatnira.production_calculation_snapshots WHERE batch_id=$1 AND lot_id=$2 AND correction_id IS NULL AND cost_correction_id IS NULL', [id, b.lot_id])).rows[0]);
            await assertBatchSource(tx, access, b.lot_id, b.source_document_id ? {documentId:b.source_document_id, revisionId:b.source_revision_id,block:b.source_block,rowReference:b.source_row} : null, id);
            if (b.status !== 'draft')
                throw new ConflictException('Batch tidak dapat disahkan.');
            const scope = [access.tenantId, access.factoryId, b.lot_id, b.is_synthetic];
            if ((await tx.query('SELECT 1 FROM sobatnira.lot_closures WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4 AND reopened_at IS NULL', scope)).rows.length)
                throw new ConflictException('Kloter sudah ditutup.');
            // Holder must match the cooking lot; each origin remains traceable.
            const reservations = (await tx.query(`SELECT * FROM sobatnira.juice_reservations WHERE tenant_id=$1 AND factory_id=$2 AND batch_id=$3 AND state<>'released' ORDER BY request_id FOR UPDATE`, [access.tenantId, access.factoryId, id])).rows;
            if (!reservations.length || reservations.some(r => r.lot_id !== b.lot_id || r.is_synthetic !== b.is_synthetic || !['reserved', 'consumed'].includes(r.state)) || compareDecimals(sumDecimals(reservations.map(r => String(r.quantity_ml))), String(b.quantity_ml)) !== 0)
                throw new ConflictException('Reservasi harus sesuai volume, pabrik, dan kategori batch.');
            const grades = (await tx.query<Grade>('SELECT code,weight_kg::text AS "weightKg",price_per_kg_rupiah::text AS "pricePerKgRupiah" FROM sobatnira.batch_grade_results WHERE batch_id=$1', [id])).rows;
            assertGradeWeight(String(b.physical_weight_kg), grades);
            await tx.query("UPDATE sobatnira.juice_reservations SET state='consumed',finalized_by=$4,finalized_at=clock_timestamp() WHERE tenant_id=$1 AND factory_id=$2 AND batch_id=$3 AND state='reserved'", [access.tenantId, access.factoryId, id, access.userId]);
            const approved = (await tx.query("UPDATE sobatnira.production_batches SET status='approved',approved_by=$2,approved_at=clock_timestamp() WHERE id=$1 RETURNING *", [id, access.userId])).rows[0];
            await this.inventory.postBatch(tx, access, approved, id);
            const snapshot = await this.snapshot(tx, access, {id, lot_id: b.lot_id, is_synthetic: b.is_synthetic}, null);
            await tx.query("INSERT INTO sobatnira.production_batch_events(batch_id,action,actor_id) VALUES($1,'approved',$2)", [id, access.userId]);
            return snapshot;
        });
    }
    private async snapshot(tx: DatabaseSession, access: FactoryAccess,
        batch: {id: string; lot_id: string; is_synthetic: boolean}, correctionId: string | null) {
        return rebuildSnapshots(tx, access, batch, correctionId);
    }

    async detail(access: FactoryAccess, id: string) {
        const { rows: [row] } = await this.db.query<{ id: string; code: string; lot_id: string; wok_number: number;
          occurred_at: string; status: string; is_synthetic: boolean; lotClosureId: string | null; grades: Grade[] | null }>(`WITH ${FACTORY_SCOPE_CTE}
          SELECT b.*,
            (SELECT to_jsonb(c) - ARRAY['before_data','created_by','updated_by']
             FROM sobatnira.production_batch_corrections c WHERE c.batch_id=b.id AND c.status='draft') AS correction,
            (SELECT c.id FROM sobatnira.lot_closures c
              WHERE (c.tenant_id,c.factory_id,c.lot_id,c.is_synthetic)=(b.tenant_id,b.factory_id,b.lot_id,b.is_synthetic)
              AND c.reopened_at IS NULL) AS "lotClosureId",
            (SELECT jsonb_agg(jsonb_build_object('code',g.code,'weightKg',g.weight_kg::text,
              'pricePerKgRupiah',g.price_per_kg_rupiah::text) ORDER BY g.code)
             FROM sobatnira.batch_grade_results g WHERE g.batch_id=b.id) AS grades,
            EXISTS(SELECT 1 FROM sobatnira.lot_production_costs c
              WHERE (c.tenant_id,c.factory_id,c.lot_id)=(b.tenant_id,b.factory_id,b.lot_id)) AS "costSaved",
            COALESCE((SELECT jsonb_agg(jsonb_build_object('requestId',r.request_id,
              'originLotId',r.origin_lot_id,'lotCode',COALESCE(l.display_code,l.id::text),
              'quantityMl',trim_scale(r.quantity_ml)::text,'state',r.state) ORDER BY r.created_at,r.request_id)
              FROM sobatnira.juice_reservations r JOIN sobatnira.lots l
                ON (l.tenant_id,l.factory_id,l.id)=(r.tenant_id,r.factory_id,r.origin_lot_id)
              WHERE (r.tenant_id,r.factory_id,r.batch_id,r.lot_id,r.is_synthetic)
                =(b.tenant_id,b.factory_id,b.id,b.lot_id,b.is_synthetic)), '[]'::jsonb) AS reservations,
            (SELECT trim_scale(b.quantity_ml-COALESCE(sum(r.quantity_ml),0))::text FROM sobatnira.juice_reservations r
               WHERE (r.tenant_id,r.factory_id,r.batch_id)=(b.tenant_id,b.factory_id,b.id)
                 AND r.lot_id=b.lot_id
                 AND r.is_synthetic=b.is_synthetic AND r.state<>'released') AS "remainingMl"
          FROM sobatnira.production_batches b JOIN authorized_scope s
            ON s."tenantId"=b.tenant_id AND s."factoryId"=b.factory_id WHERE b.id=$4`, [...scopeValues(access), id]);
        const batch = found(row);
        return { ...batch, ...batchGradeTotals(batch.grades ?? []),
            lotClosed: batch.lotClosureId !== null,
            canCorrect: access.role === 'admin' && batch.status === 'approved' };
    }

    async correct(access: FactoryAccess, id: string, correctionId: string, action: 'open' | 'save' | 'approve' | 'discard', input: unknown) {
        const body = object(input, action === 'open' ? ['reason', 'reopenClosureId'] :
            action === 'save' ? ['version', 'physicalWeightKg', 'grades'] : ['version']);
        const reason = action === 'open' ? text(body.reason, 'Alasan koreksi', 500) : null;
        const reopenClosureId = body.reopenClosureId === undefined ? null : uuid(body.reopenClosureId, 'reopenClosureId');
        const version = body.version as number;
        if (action !== 'open' && (!Number.isSafeInteger(version) || version < 1)) {
            throw new BadRequestException('Versi koreksi tidak valid.');
        }
        const proposed = action === 'save' ? correctionData(body.physicalWeightKg, body.grades) : null;
        return this.juice.mutate(access, async (tx) => {
            const batch = await this.lockBatch(tx, access, id);
            const scope = [access.tenantId, access.factoryId, batch.lot_id, batch.is_synthetic];
            if (batch.status !== 'approved') {
                throw new ConflictException('Batch tidak dapat dikoreksi.');
            }
            const existing = (await tx.query(`SELECT *, proposed_data=$3::jsonb AS same_data
              FROM sobatnira.production_batch_corrections WHERE id=$1 AND batch_id=$2 FOR UPDATE`,
              [correctionId, id, proposed == null ? null : JSON.stringify(proposed)])).rows[0];
            if (action === 'open' && existing) {
                if (existing.reason !== reason) throw new ConflictException('ID koreksi sudah dipakai.');
                return existing;
            }
            if (action !== 'open') {
                const correction = found(existing);
                if (correction.version === version && correction.status === (action === 'approve' ? 'approved' : 'discarded') && action !== 'save') return correction;
                if (action === 'save' && correction.status === 'draft' && correction.version === version + 1 && correction.same_data) return correction;
                if (correction.status !== 'draft' || correction.version !== version) {
                    throw new ConflictException('Koreksi sudah berubah. Muat ulang batch.');
                }
            }
            const { rows: [activeClosure] } = await tx.query<{id: string}>(`SELECT id FROM sobatnira.lot_closures
              WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4 AND reopened_at IS NULL`, scope);
            if (activeClosure && (action !== 'open' || reopenClosureId !== activeClosure.id)) {
                throw new ConflictException('Konfirmasi pembukaan kembali kloter terbaru sebelum mengoreksi batch.');
            }
            if (action === 'open') {
                const grades = (await tx.query<Grade>(`SELECT code, weight_kg::text AS "weightKg",
                  price_per_kg_rupiah::text AS "pricePerKgRupiah" FROM sobatnira.batch_grade_results
                  WHERE batch_id=$1 ORDER BY code`, [id])).rows;
                const result = await tx.query(`INSERT INTO sobatnira.production_batch_corrections
                  (id,batch_id,reason,before_data,proposed_data,created_by,updated_by)
                  SELECT $1,$2,$3,$4,$4,$5,$5
                  WHERE NOT EXISTS (SELECT 1 FROM sobatnira.production_batch_corrections WHERE batch_id=$2 AND status='draft')
                  ON CONFLICT DO NOTHING RETURNING *`, [correctionId, id, reason,
                    JSON.stringify(correctionData(String(batch.physical_weight_kg), grades)), access.userId]);
                if (!result.rows.length) throw new ConflictException('Batch sudah memiliki draf koreksi atau ID koreksi telah dipakai.');
                if (activeClosure && !(await reopenActiveClosure(tx, access, batch.lot_id, batch.is_synthetic,
                  activeClosure.id, `Koreksi batch ${batch.code}.`))) {
                    throw new ConflictException('Penutupan kloter sudah berubah.');
                }
                return result.rows[0];
            }
            if (action === 'save') {
                return (await tx.query(`UPDATE sobatnira.production_batch_corrections
                  SET proposed_data=$2,version=version+1,updated_by=$3,updated_at=clock_timestamp() WHERE id=$1 RETURNING *`,
                  [correctionId, JSON.stringify(proposed), access.userId])).rows[0];
            }
            if (action === 'approve') {
                const data = existing.proposed_data as ReturnType<typeof correctionData>;
                assertGradeWeight(data.physicalWeightKg, data.grades);
                await tx.query('UPDATE sobatnira.production_batches SET physical_weight_kg=$2 WHERE id=$1', [id, data.physicalWeightKg]);
                await tx.query('DELETE FROM sobatnira.batch_grade_results WHERE batch_id=$1', [id]);
                for (const grade of data.grades) {
                    await tx.query(`INSERT INTO sobatnira.batch_grade_results(batch_id,code,weight_kg,price_per_kg_rupiah)
                      VALUES($1,$2,$3,$4)`, [id, grade.code, grade.weightKg, grade.pricePerKgRupiah]);
                }
                await this.inventory.postBatch(tx, access, batch, correctionId, true);
                await this.snapshot(tx, access, {id, lot_id: batch.lot_id, is_synthetic: batch.is_synthetic}, correctionId);
            }
            return (await tx.query(`UPDATE sobatnira.production_batch_corrections
              SET status=$2,updated_by=$3,updated_at=clock_timestamp() WHERE id=$1 RETURNING *`,
              [correctionId, action === 'approve' ? 'approved' : 'discarded', access.userId])).rows[0];
        });
    }

    private async lockBatch(tx: DatabaseSession, access: FactoryAccess, id: string) {
        // Read identity first, then lock the lot before locking the batch.
        const scope = [access.tenantId, access.factoryId, id];
        const batch = found((await tx.query<{lot_id: string}>(`SELECT lot_id FROM sobatnira.production_batches
          WHERE tenant_id=$1 AND factory_id=$2 AND id=$3`, scope)).rows[0]);
        await this.juice.lockLots(tx, access, [batch.lot_id]);
        return found((await tx.query(`SELECT * FROM sobatnira.production_batches
          WHERE tenant_id=$1 AND factory_id=$2 AND id=$3 FOR UPDATE`, scope)).rows[0]);
    }

    async cancel(access: FactoryAccess, id: string) {
        return this.juice.mutate(access, async (tx) => {
            const keys = [access.tenantId, access.factoryId, id];
            const row = await this.lockBatch(tx, access, id);
            if (row.status === 'cancelled') return row;
            if (row.status !== 'draft') throw new ConflictException('Hanya draf batch yang dapat dibatalkan.');
            const reservations = (await tx.query(`SELECT lot_id, state FROM sobatnira.juice_reservations
              WHERE tenant_id=$1 AND factory_id=$2 AND batch_id=$3 AND state<>'released' FOR UPDATE`, keys)).rows;
            if (reservations.some(r => r.state === 'consumed' || r.lot_id !== row.lot_id)) {
                throw new ConflictException('Nira sudah dikonsumsi atau reservasi berada di kloter lain.');
            }
            await tx.query(`UPDATE sobatnira.juice_reservations SET state='released',finalized_by=$4,finalized_at=clock_timestamp()
              WHERE tenant_id=$1 AND factory_id=$2 AND batch_id=$3 AND state='reserved'`, [...keys, access.userId]);
            const updated = (await tx.query(`UPDATE sobatnira.production_batches SET status='cancelled'
              WHERE tenant_id=$1 AND factory_id=$2 AND id=$3 RETURNING *`, keys)).rows[0];
            await tx.query("INSERT INTO sobatnira.production_batch_events(batch_id,action,actor_id) VALUES($1,'cancelled',$2)", [id, access.userId]);
            return updated;
        });
    }

    async list(access: FactoryAccess, query: unknown) {
        const q = object(query, ['limit','offset','lotId','synthetic']);
        const page = parsePage({ limit: q.limit, offset: q.offset });
        const lotId = q.lotId === undefined ? null : uuid(q.lotId);
        const synthetic = q.synthetic === undefined ? null : String(q.synthetic);
        if (synthetic !== null && synthetic !== 'true' && synthetic !== 'false') {
            throw new BadRequestException('synthetic tidak valid.');
        }
        const rows = await this.db.query(`WITH ${FACTORY_SCOPE_CTE} SELECT b.*, EXISTS(
          SELECT 1 FROM sobatnira.production_batch_corrections c WHERE c.batch_id=b.id AND c.status='draft'
        ) AS "hasCorrection" FROM sobatnira.production_batches b
          JOIN authorized_scope s ON s."tenantId"=b.tenant_id AND s."factoryId"=b.factory_id
          WHERE ($6::uuid IS NULL OR b.lot_id=$6) AND ($7::boolean IS NULL OR b.is_synthetic=$7)
          ORDER BY b.occurred_at DESC,b.id LIMIT $4 OFFSET $5`,
          [...scopeValues(access), page.limit, page.offset, lotId, synthetic]);
        return { items: rows.rows, ...page };
    }
    async productionReport(access: FactoryAccess, query: unknown, maxLots = REPORT_MAX_LOTS, includeJuiceSources = false) {
        const q = object(query, ['from', 'before', 'synthetic', 'supplierId', 'lotId', 'batchId', 'grade', 'view', 'limit', 'offset']);
        if (q.view !== undefined && !['summary', 'page'].includes(String(q.view))) throw new BadRequestException('view laporan tidak valid.');
        if (q.view !== 'page' && (q.limit !== undefined || q.offset !== undefined)) throw new BadRequestException('Pagination memerlukan view=page.');
        if (q.synthetic !== undefined && !['true', 'false'].includes(String(q.synthetic)))
            throw new BadRequestException('synthetic tidak valid.');
        const from = q.from === undefined ? null : timestamp(q.from, 'from');
        const before = q.before === undefined ? null : timestamp(q.before, 'before');
        reportPeriod(from, before);
        const synthetic = q.synthetic === 'true';
        const selection = reportSelection(q);
        const header = { factory: access.factoryName, from, before, synthetic, periodBasis: 'lot_received_at', selection };
        if (selection.batchId || selection.grade) {
          // Keep the filtered result bounded before computing exact full-result totals.
          const items = await this.reportRows(access, synthetic, from, before, {
            limit: maxLots + 1, includeJuiceSources, ...selection,
          });
          checkReportSize(items, maxLots);
          const report = reportProductionSelection(items, selection);
          if (q.view === 'summary') return boundedReport({ ...header, ...report, view: 'summary', items: [] });
          if (q.view === 'page') {
            const page = parsePage({ limit: q.limit, offset: q.offset });
            const end = page.offset + page.limit;
            return boundedReport({ ...header, ...report, view: 'page', ...page,
              items: report.items.slice(page.offset, end), nextOffset: end < items.length ? end : null });
          }
          return boundedReport({ ...header, ...report });
        }
        if (q.view === 'summary') return this.reportSummary(access, synthetic, from, before, selection);
        if (q.view === 'page') {
          const page = parsePage({ limit: q.limit, offset: q.offset });
          return this.db.transaction(async session => {
          await session.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY', []);
          const summary = await this.reportSummary(access, synthetic, from, before, selection, session);
          const items = await this.reportRows(access, synthetic, from, before,
            { limit: page.limit + 1, offset: page.offset, includeJuiceSources, ...selection, session });
          const more = items.length > page.limit;
          checkReportSize(items);
          return boundedReport({ ...summary, view: 'page', items: productionReport(items.slice(0, page.limit)).items,
            ...page, nextOffset: more ? page.offset + page.limit : null });
          });
        }
        const items = await this.reportRows(access, synthetic, from, before, {
          limit: maxLots === undefined ? null : maxLots + 1, includeJuiceSources, ...selection,
        });
        checkReportSize(items, maxLots);
        return boundedReport({ ...header, ...productionReport(items) });
    }

    async reportSummary(access: FactoryAccess, synthetic: boolean, from: string | null, before: string | null, selection: ReportSelection, session: DatabaseSession = this.db) {
        const { rows: [row] } = await session.query<ReturnType<typeof productionReport>['totals'] & {
          grades: ReturnType<typeof productionReport>['grades']; provisional: boolean; latestReceivedAt: Date | null;
        }>(`WITH ${FACTORY_SCOPE_CTE}, selected AS (
          SELECT l.id,l.received_at,i.net_weight_kg,p.output_snapshot AS calculation,
            p.id AS snapshot_id,p.calculation_version,p.input_snapshot, EXISTS(SELECT 1 FROM sobatnira.lot_closures c
              WHERE (c.tenant_id,c.factory_id,c.lot_id,c.is_synthetic)=(l.tenant_id,l.factory_id,l.id,$4)
              AND c.reopened_at IS NULL) AS closed
          FROM sobatnira.lots l JOIN authorized_scope a ON (l.tenant_id,l.factory_id)=(a."tenantId",a."factoryId")
          JOIN sobatnira.intake_records i ON (i.tenant_id,i.factory_id,i.lot_id,i.is_synthetic)=(l.tenant_id,l.factory_id,l.id,$4)
          LEFT JOIN LATERAL (SELECT id,calculation_version,input_snapshot,output_snapshot FROM sobatnira.production_calculation_snapshots
            WHERE (tenant_id,factory_id,lot_id,is_synthetic)=(l.tenant_id,l.factory_id,l.id,$4)
            ORDER BY approved_at DESC,id DESC LIMIT 1) p ON true
          WHERE ($5::timestamptz IS NULL OR l.received_at >= $5) AND ($6::timestamptz IS NULL OR l.received_at < $6)
            AND ($7::uuid IS NULL OR l.id=$7)
            AND ($8::uuid IS NULL OR l.supplier_id=$8)
        ), approved AS (
          SELECT b.id FROM sobatnira.production_batches b JOIN selected s ON s.id=b.lot_id
          WHERE (b.tenant_id,b.factory_id,b.is_synthetic)=($2,$3,$4) AND b.status='approved'
            AND s.calculation_version IS DISTINCT FROM 'production-v2'
          UNION
          SELECT (entry->>'id')::uuid FROM selected s CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN s.calculation_version='production-v2' THEN s.input_snapshot->'allocatedBatches' ELSE '[]'::jsonb END) entry
        ), grade_rows AS (
          SELECT g.code,g.weight_kg,g.price_per_kg_rupiah FROM sobatnira.batch_grade_results g
          JOIN sobatnira.production_batches b ON b.id=g.batch_id JOIN selected s ON s.id=b.lot_id
          WHERE (b.tenant_id,b.factory_id,b.is_synthetic)=($2,$3,$4) AND b.status='approved'
            AND s.calculation_version IS DISTINCT FROM 'production-v2'
          UNION ALL
          SELECT g->>'code',(g->>'weightKg')::numeric,(g->>'pricePerKgRupiah')::numeric
          FROM selected s CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN s.calculation_version='production-v2' THEN s.input_snapshot->'allocatedBatches' ELSE '[]'::jsonb END) entry
          CROSS JOIN LATERAL jsonb_array_elements(entry->'grades') g
        ) SELECT count(*)::int AS "lotCount",count(snapshot_id)::int AS "producedLotCount",
          (SELECT count(*)::int FROM approved) AS "batchCount",
          COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY code) FROM (
            SELECT code,trim_scale(sum(weight_kg))::text AS "weightKg",
              trim_scale(sum(weight_kg*price_per_kg_rupiah))::text AS "exactValueRupiah"
            FROM grade_rows GROUP BY code
          ) g),'[]'::jsonb) AS grades,
          trim_scale(COALESCE(sum(net_weight_kg),0))::text AS "caneNetKg",
          trim_scale(COALESCE(sum((calculation->>'finalSugarKg')::numeric),0))::text AS "finalSugarKg",
          trim_scale(COALESCE(sum((calculation->>'productionValueRupiah')::numeric),0))::text AS "productionValueRupiah",
          trim_scale(COALESCE(sum((calculation->>'totalCostRupiah')::numeric),0))::text AS "totalCostRupiah",
          trim_scale(COALESCE(sum((calculation->>'productionMarginRupiah')::numeric),0))::text AS "productionMarginRupiah",
          COALESCE(bool_or(snapshot_id IS NOT NULL AND NOT closed),false) AS provisional,
          max(received_at) AS "latestReceivedAt" FROM selected`,
        [...scopeValues(access), synthetic, from, before, selection.lotId ?? null, selection.supplierId ?? null]);
        const { provisional, latestReceivedAt, grades, ...totals } = row;
        return boundedReport({ factory: access.factoryName, from, before, synthetic, periodBasis: 'lot_received_at', selection,
          view: 'summary', totals, provisional, latestReceivedAt, items: [], grades });
    }

    async compareProductionReports(access: FactoryAccess, first: ReportPeriod, second: ReportPeriod, maxLots: number) {
        const synthetic = first.synthetic === 'true';
        const items = await this.reportRows(access, synthetic, first.from, first.before, { limit: maxLots * 2 + 1, second });
        return [first, second].map(({ from, before }) => {
            const lower = Date.parse(from), upper = Date.parse(before);
            const matching = items.filter(lot => {
                const received = new Date(lot.receivedAt).getTime();
                return lower <= received && received < upper;
            });
            checkReportSize(matching, maxLots);
            return boundedReport({ from, before, synthetic, periodBasis: 'lot_received_at', ...productionReport(matching) });
        });
    }

    private async reportRows(access: FactoryAccess, synthetic: boolean, from: string | null, before: string | null,
      { limit, second, includeJuiceSources, lotId, supplierId, batchId, grade, offset = 0, session = this.db }: ReportSelection & {
        limit: number | null; second?: ReportPeriod; includeJuiceSources?: boolean; offset?: number; session?: DatabaseSession;
      }) {
        const batchesSql = `CASE WHEN p.calculation_version='production-v2' THEN
            ${includeJuiceSources ? `(SELECT jsonb_agg(entry || jsonb_build_object('consumedByOrigin', COALESCE((
              SELECT jsonb_agg(to_jsonb(src)) FROM (
                SELECT r.origin_lot_id AS "originLotId",COALESCE(l.display_code,l.id::text) AS "lotCode",
                  trim_scale(sum(r.quantity_ml))::text AS "quantityMl"
                FROM sobatnira.juice_reservations r WHERE r.tenant_id=l.tenant_id AND r.factory_id=l.factory_id
                  AND r.batch_id=(entry->>'id')::uuid AND r.origin_lot_id=l.id
                  AND r.is_synthetic=$4 AND r.state='consumed' GROUP BY r.origin_lot_id
              ) src),'[]'::jsonb))) FROM jsonb_array_elements(p.input_snapshot->'allocatedBatches') entry)` : "p.input_snapshot->'allocatedBatches'"}
            ELSE COALESCE(b.items,'[]'::jsonb) END`;
        // A single statement gives receipt, latest cumulative snapshot and approved
        // batch details one consistent PostgreSQL read snapshot, scoped by membership.
        const { rows } = await session.query<ProductionReportLot>(`WITH ${FACTORY_SCOPE_CTE}
          SELECT l.id AS "lotId", COALESCE(l.display_code,l.id::text) AS code,l.supplier_id AS "supplierId",
            s.name AS supplier,l.received_at AS "receivedAt",i.net_weight_kg::text AS "caneNetKg",
            i.cane_type_code AS "caneType",trim_scale(COALESCE(mc.quantity_after,m.juice_produced_liters))::text AS "juiceLiters",
            p.id AS "calculationSnapshotId", p.calculation_version AS "calculationVersion",
            p.output_snapshot AS calculation,COALESCE(report_batches.items,'[]'::jsonb) AS batches,
            EXISTS(SELECT 1 FROM sobatnira.lot_closures c
              WHERE (c.tenant_id,c.factory_id,c.lot_id,c.is_synthetic)=(l.tenant_id,l.factory_id,l.id,i.is_synthetic)
              AND c.reopened_at IS NULL) AS closed
          FROM sobatnira.lots l
          JOIN authorized_scope a ON a."tenantId"=l.tenant_id AND a."factoryId"=l.factory_id
          JOIN sobatnira.suppliers s ON s.id=l.supplier_id AND s.tenant_id=l.tenant_id
          JOIN sobatnira.intake_records i ON i.lot_id=l.id AND i.tenant_id=l.tenant_id AND i.factory_id=l.factory_id AND i.is_synthetic=$4
          LEFT JOIN sobatnira.milling_records m ON m.lot_id=l.id AND m.tenant_id=l.tenant_id AND m.factory_id=l.factory_id AND m.is_synthetic=$4
          LEFT JOIN LATERAL (SELECT quantity_after FROM sobatnira.stock_reconciliations WHERE milling_record_id=m.id ORDER BY revision_version DESC LIMIT 1) mc ON true
          LEFT JOIN LATERAL (SELECT id,calculation_version,input_snapshot,output_snapshot FROM sobatnira.production_calculation_snapshots
            WHERE lot_id=l.id AND tenant_id=l.tenant_id AND factory_id=l.factory_id AND is_synthetic=$4
            ORDER BY approved_at DESC,id DESC LIMIT 1) p ON true
          LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object(
            'id',pb.id,'code',pb.code,'wokNumber',pb.wok_number,'occurredAt',pb.occurred_at,
            'quantityMl',pb.quantity_ml::text,'physicalWeightKg',pb.physical_weight_kg::text,
            'grades',(SELECT jsonb_agg(jsonb_build_object('code',g.code,'weightKg',g.weight_kg::text,
              'pricePerKgRupiah',g.price_per_kg_rupiah::text) ORDER BY g.code) FROM sobatnira.batch_grade_results g WHERE g.batch_id=pb.id)
            ${includeJuiceSources ? `,'consumedByOrigin',COALESCE((
              SELECT jsonb_agg(to_jsonb(c) ORDER BY c."originLotId") FROM (
                SELECT r.origin_lot_id AS "originLotId",
                  COALESCE(origin.display_code,r.origin_lot_id::text) AS "lotCode",
                  trim_scale(sum(r.quantity_ml))::text AS "quantityMl"
                FROM sobatnira.juice_reservations r
                LEFT JOIN sobatnira.lots origin ON (origin.tenant_id,origin.factory_id,origin.id)
                  =(r.tenant_id,r.factory_id,r.origin_lot_id)
                WHERE (r.tenant_id,r.factory_id,r.batch_id,r.is_synthetic)
                  =(pb.tenant_id,pb.factory_id,pb.id,pb.is_synthetic) AND r.state='consumed'
                GROUP BY r.origin_lot_id,origin.display_code
              ) c
            ),'[]'::jsonb)` : ''}
            ) ORDER BY pb.occurred_at,pb.id) AS items FROM (
              SELECT batch.* FROM sobatnira.production_batches batch WHERE batch.lot_id=l.id AND batch.tenant_id=l.tenant_id
                AND batch.factory_id=l.factory_id AND batch.is_synthetic=$4 AND batch.status='approved'
                AND ($13::uuid IS NULL OR batch.id=$13)
                AND ($14::text IS NULL OR EXISTS (
                  SELECT 1 FROM sobatnira.batch_grade_results grade
                  WHERE grade.batch_id=batch.id AND grade.code=$14
                ))
              ORDER BY occurred_at,id LIMIT 1001
            ) pb WHERE pb.status='approved') b ON true
          CROSS JOIN LATERAL (SELECT ${batchesSql} AS items) report_batches
          WHERE ($10::uuid IS NULL OR l.id = $10)
            AND ($12::uuid IS NULL OR l.supplier_id=$12)
            AND (($13::uuid IS NULL AND $14::text IS NULL) OR EXISTS (
              SELECT 1 FROM jsonb_array_elements(report_batches.items) entry
              WHERE ($13::uuid IS NULL OR entry->>'id'=$13::text)
                AND ($14::text IS NULL OR EXISTS (
                  SELECT 1 FROM jsonb_array_elements(entry->'grades') g WHERE g->>'code'=$14
                ))
            ))
            AND ((($5::timestamptz IS NULL OR l.received_at >= $5) AND ($6::timestamptz IS NULL OR l.received_at < $6))
              OR (l.received_at >= $8::timestamptz AND l.received_at < $9::timestamptz))
          ORDER BY l.received_at DESC,l.id LIMIT $7 OFFSET $11`, [...scopeValues(access), synthetic, from, before, limit,
            second?.from ?? null, second?.before ?? null, lotId ?? null, offset, supplierId ?? null, batchId ?? null, grade ?? null]);
        return rows;
    }

    async report(access: FactoryAccess, query: unknown, includeBatches = false) {

        const q = object(query, ['from', 'before', 'synthetic']);
        if (q.synthetic !== undefined && !['true', 'false'].includes(String(q.synthetic)))
            throw new BadRequestException('synthetic tidak valid.');
        const from = q.from === undefined ? null : timestamp(q.from, 'from'), before = q.before === undefined ? null : timestamp(q.before, 'before');
        reportPeriod(from, before);
        // Latest cumulative snapshot per lot; report period follows lot receipt time.
        const rows = (await this.db.query(`WITH ${FACTORY_SCOPE_CTE}, latest AS (
   SELECT DISTINCT ON(p.lot_id) p.* FROM sobatnira.production_calculation_snapshots p JOIN authorized_scope s ON s."tenantId"=p.tenant_id AND s."factoryId"=p.factory_id
   WHERE p.is_synthetic=$4 ORDER BY p.lot_id,p.approved_at DESC,p.id DESC)
   SELECT l.id AS "lotId",l.display_code AS code,s.name AS supplier,l.received_at AS "receivedAt",p.id AS "snapshotId",p.output_snapshot AS calculation,
    EXISTS(SELECT 1 FROM sobatnira.lot_closures c WHERE (c.tenant_id,c.factory_id,c.lot_id,c.is_synthetic)=
      (p.tenant_id,p.factory_id,p.lot_id,p.is_synthetic) AND c.reopened_at IS NULL) AS closed
    ${includeBatches ? `, CASE WHEN p.calculation_version='production-v2' THEN p.input_snapshot->'allocatedBatches' ELSE (SELECT jsonb_agg(jsonb_build_object('id',b.id,'code',b.code,'wokNumber',b.wok_number,
       'occurredAt',b.occurred_at,'volumeMl',b.quantity_ml::text,'physicalWeightKg',b.physical_weight_kg::text,
       'grades',(SELECT jsonb_agg(jsonb_build_object('code',g.code,'weightKg',g.weight_kg::text) ORDER BY g.code)
         FROM sobatnira.batch_grade_results g WHERE g.batch_id=b.id)) ORDER BY b.occurred_at,b.id)
       FROM (SELECT * FROM sobatnira.production_batches b
       WHERE (b.tenant_id,b.factory_id,b.lot_id,b.is_synthetic)=(p.tenant_id,p.factory_id,p.lot_id,p.is_synthetic)
         AND b.status='approved' AND EXISTS(SELECT 1 FROM sobatnira.production_calculation_snapshots bs
           WHERE bs.batch_id=b.id AND bs.correction_id IS NULL AND (bs.approved_at,bs.id)<=(p.approved_at,p.id))
       ORDER BY b.occurred_at,b.id LIMIT 1001) b) END AS batches` : ''}
   FROM latest p JOIN sobatnira.lots l ON l.id=p.lot_id JOIN sobatnira.suppliers s ON s.id=l.supplier_id
   WHERE ($5::timestamptz IS NULL OR l.received_at >= $5) AND ($6::timestamptz IS NULL OR l.received_at < $6)
   ORDER BY l.received_at DESC,l.id LIMIT 101`, [...scopeValues(access), q.synthetic === 'true', from, before])).rows;
        if (rows.length > REPORT_MAX_LOTS) throw new BadRequestException('Persempit periode laporan: maksimum 100 kloter. Gunakan ekspor asinkron.');
        if (includeBatches && rows.some(row => row.batches?.length > 1000)) throw new BadRequestException('Laporan melebihi 1000 batch per kloter.');
        return boundedReport({ factory: access.factoryName, from, before, synthetic: q.synthetic === 'true', items: rows,
            total: rows.length, totalSugarKg: sumDecimals(rows.map(r => r.calculation.finalSugarKg)),
            totalMarginRupiah: rows.reduce((v, r) => v + BigInt(r.calculation.productionMarginRupiah), 0n).toString() });
    }
}
@Controller('tenants/:tenantId/factories/:factoryId/production')
@FactoryRoles('admin', 'owner')
export class BatchesController {
    constructor(private readonly batches: Batches) { }
    @Get('lots/:id/batch-sources')
    sources(@CurrentFactory() a: FactoryAccess, @Param('id') id: string) { return this.batches.sources(a, uuid(id)); }
    @Get('batches')
    list(
    @CurrentFactory()
    a: FactoryAccess, 
    @Query()
    q: unknown) { return this.batches.list(a, q); }
    @Get('batches/:id')
    detail(@CurrentFactory() a: FactoryAccess, @Param('id') id: string) {
        return this.batches.detail(a, uuid(id));
    }
    @Post('batches/:id/corrections/:correctionId')
    @FactoryRoles('admin')
    openCorrection(@CurrentFactory() a: FactoryAccess, @Param('id') id: string,
        @Param('correctionId') correction: string, @Body() body: unknown) {
        return this.batches.correct(a, uuid(id), uuid(correction), 'open', body);
    }
    @Patch('batches/:id/corrections/:correctionId')
    @FactoryRoles('admin')
    saveCorrection(@CurrentFactory() a: FactoryAccess, @Param('id') id: string,
        @Param('correctionId') correction: string, @Body() body: unknown) {
        return this.batches.correct(a, uuid(id), uuid(correction), 'save', body);
    }
    @Post('batches/:id/corrections/:correctionId/:action')
    @FactoryRoles('admin')
    @HttpCode(200)
    finishCorrection(@CurrentFactory() a: FactoryAccess, @Param('id') id: string,
        @Param('correctionId') correction: string, @Param('action') action: string, @Body() body: unknown) {
        if (action !== 'approve' && action !== 'discard') throw new BadRequestException('Tindakan koreksi tidak valid.');
        return this.batches.correct(a, uuid(id), uuid(correction), action, body);
    }
    @Post('batches/:id/cancel')
    @FactoryRoles('admin')
    @HttpCode(200)
    cancel(@CurrentFactory() a: FactoryAccess, @Param('id') id: string) {
        return this.batches.cancel(a, uuid(id));
    }
    @Get('recap')
    recap(@CurrentFactory() a: FactoryAccess, @Query() q: unknown) {
        return this.batches.report(a, q, true);
    }
    @Post('batches')
    @FactoryRoles('admin')
    create(
    @CurrentFactory()
    a: FactoryAccess, 
    @Body()
    b: unknown) { return this.batches.create(a, b); }
    @Post('batches/:id/approve')
    @FactoryRoles('admin')
    @HttpCode(200)
    approve(
    @CurrentFactory()
    a: FactoryAccess, 
    @Param('id')
    id: string) { return this.batches.approve(a, uuid(id)); }
    @Post('lots/:id/costs')
    @FactoryRoles('admin')
    @HttpCode(200)
    costs(
    @CurrentFactory()
    a: FactoryAccess, 
    @Param('id')
    id: string, 
    @Body()
    b: unknown) { return this.batches.costs(a, uuid(id), b); }
    @Get('production-report')
    productionReport(@CurrentFactory() a: FactoryAccess, @Query() q: unknown) {
        return this.batches.productionReport(a, q);
    }
    @Get('profit-report')
    report(
    @CurrentFactory()
    a: FactoryAccess, 
    @Query()
    q: unknown) { return this.batches.report(a, q); }
}
