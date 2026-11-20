import { BadRequestException, Body, ConflictException, Controller, Get, HttpCode, Injectable, Param, Patch, Post, Query } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { JuiceRepository } from '../juice/juice.repository';
import { object, uuid, text, timestamp, scopeValues, found, parsePage } from './production.dto';
import { decimal, sumDecimals, compareDecimals } from './decimal';
import { calculateProductionPreview } from './calculation';
import { batchGradeTotals, type Grade, productionReport, ProductionReportLot } from './production-report';

type ReportPeriod = { from: string; before: string; synthetic: string };

function checkReportSize(items: ProductionReportLot[], maxLots?: number) {
    if (maxLots !== undefined && items.length > maxLots) {
        throw new BadRequestException('Persempit periode laporan agar semua kloter dapat dihitung.');
    }
}
export function parseBatch(input: unknown) {
    const b = object(input, ['id', 'lotId', 'code', 'wokNumber', 'occurredAt', 'quantityMl', 'physicalWeightKg', 'grades', 'synthetic']);
    if (!Number.isSafeInteger(b.wokNumber) || Number(b.wokNumber) < 1 || Number(b.wokNumber) > 10000)
        throw new BadRequestException('Nomor wajan tidak valid.');
    if (b.synthetic !== undefined && typeof b.synthetic !== 'boolean')
        throw new BadRequestException('synthetic harus boolean.');
    // Reuse exact calculator validation for weights, prices and duplicate grade codes.
    const calculation = calculateProductionPreview({ caneNetKg: '1', caneCostRupiah: '0', operationalCostRupiah: '0', ingredientCostRupiah: '0', otherCostRupiah: '0', rounding: 'HALF_UP', grades: b.grades });
    return { id: uuid(b.id), lotId: uuid(b.lotId), code: text(b.code, 'code', 100), wokNumber: Number(b.wokNumber), occurredAt: timestamp(b.occurredAt, 'occurredAt'), quantityMl: decimal(b.quantityMl, 'quantityMl'), physicalWeightKg: decimal(b.physicalWeightKg, 'physicalWeightKg'), grades: calculation.grades.map(g => ({ code: g.code, weightKg: g.weightKg, pricePerKgRupiah: g.pricePerKgRupiah })), synthetic: b.synthetic === true };
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
    constructor(private readonly db: DatabaseService, private readonly juice: JuiceRepository) { }
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
            if (b.grades.length !== 1) throw new BadRequestException('Batch baru harus memiliki satu grade.');
            const scope = [access.tenantId, access.factoryId, b.lotId, b.synthetic];
            const source = await tx.query('SELECT occurred_at FROM sobatnira.milling_records WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4', scope);
            if (!source.rows.length || new Date(source.rows[0].occurred_at).getTime() > Date.parse(b.occurredAt))
                throw new ConflictException('Batch memerlukan penggilingan sah sebelum waktu memasak.');
            const closed = await tx.query('SELECT 1 FROM sobatnira.lot_closures WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4 AND reopened_at IS NULL', scope);
            if (closed.rows.length)
                throw new ConflictException('Kloter sudah ditutup.');
            const result = await tx.query(`INSERT INTO sobatnira.production_batches(id,tenant_id,factory_id,lot_id,code,wok_number,occurred_at,quantity_ml,physical_weight_kg,is_synthetic,input_hash,created_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *`, [b.id, access.tenantId, access.factoryId, b.lotId, b.code, b.wokNumber, b.occurredAt, b.quantityMl, b.physicalWeightKg, b.synthetic, hash, access.userId]);
            for (const g of b.grades)
                await tx.query('INSERT INTO sobatnira.batch_grade_results(batch_id,code,weight_kg,price_per_kg_rupiah) VALUES($1,$2,$3,$4)', [b.id, g.code, g.weightKg, g.pricePerKgRupiah]);
            await tx.query("INSERT INTO sobatnira.production_batch_events(batch_id,action,actor_id) VALUES($1,'created',$2)", [b.id, access.userId]);
            return result.rows[0];
        });
    }
    async costs(access: FactoryAccess, lotId: string, input: unknown) {
        const b = object(input, ['caneCostRupiah', 'operationalCostRupiah', 'ingredientCostRupiah', 'otherCostRupiah']);
        const c = calculateProductionPreview({ ...b, caneNetKg: '1', rounding: 'HALF_UP', grades: [{ code: 'CHECK', weightKg: '1', pricePerKgRupiah: '0' }] }).costs;
        return this.juice.mutate(access, async (tx) => {
            await this.juice.lockLots(tx, access, [lotId]);
            const approved = await tx.query('SELECT 1 FROM sobatnira.production_calculation_snapshots WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3', [access.tenantId, access.factoryId, lotId]);
            if (approved.rows.length)
                throw new ConflictException('Biaya historis sudah dibekukan.');
            return (await tx.query(`INSERT INTO sobatnira.lot_production_costs(tenant_id,factory_id,lot_id,cane_rupiah,operational_rupiah,ingredient_rupiah,other_rupiah,created_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(tenant_id,factory_id,lot_id) DO UPDATE SET cane_rupiah=$4,operational_rupiah=$5,ingredient_rupiah=$6,other_rupiah=$7 RETURNING *`, [access.tenantId, access.factoryId, lotId, c.caneRupiah, c.operationalRupiah, c.ingredientRupiah, c.otherRupiah, access.userId])).rows[0];
        });
    }
    async approve(access: FactoryAccess, id: string) {
        // Read identity only; lock order is lot, then batch, matching stock operations.
        const initial = found((await this.db.query(`WITH ${FACTORY_SCOPE_CTE} SELECT b.* FROM sobatnira.production_batches b JOIN authorized_scope s ON s."tenantId"=b.tenant_id AND s."factoryId"=b.factory_id WHERE b.id=$4`, [...scopeValues(access), id])).rows[0]);
        return this.juice.mutate(access, async (tx) => {
            await this.juice.lockLots(tx, access, [initial.lot_id]);
            const b = found((await tx.query('SELECT * FROM sobatnira.production_batches WHERE id=$1 FOR UPDATE', [id])).rows[0]);
            if (b.status === 'approved')
                return found((await tx.query('SELECT * FROM sobatnira.production_calculation_snapshots WHERE batch_id=$1 AND correction_id IS NULL', [id])).rows[0]);
            if (b.status !== 'draft')
                throw new ConflictException('Batch tidak dapat disahkan.');
            const scope = [access.tenantId, access.factoryId, b.lot_id, b.is_synthetic];
            if ((await tx.query('SELECT 1 FROM sobatnira.lot_closures WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4 AND reopened_at IS NULL', scope)).rows.length)
                throw new ConflictException('Kloter sudah ditutup.');
            // Single-origin approval only until mixed-result allocation policy is agreed.
            const reservations = (await tx.query(`SELECT * FROM sobatnira.juice_reservations WHERE tenant_id=$1 AND factory_id=$2 AND batch_id=$3 AND state<>'released' ORDER BY request_id FOR UPDATE`, [access.tenantId, access.factoryId, id])).rows;
            if (!reservations.length || reservations.some(r => r.lot_id !== b.lot_id || r.origin_lot_id !== b.lot_id || r.is_synthetic !== b.is_synthetic || !['reserved', 'consumed'].includes(r.state)) || compareDecimals(sumDecimals(reservations.map(r => String(r.quantity_ml))), String(b.quantity_ml)) !== 0)
                throw new ConflictException('Reservasi harus sesuai volume dan satu asal kloter. Batch campuran belum boleh disahkan.');
            await tx.query("UPDATE sobatnira.juice_reservations SET state='consumed',finalized_by=$4,finalized_at=clock_timestamp() WHERE tenant_id=$1 AND factory_id=$2 AND batch_id=$3 AND state='reserved'", [access.tenantId, access.factoryId, id, access.userId]);
            await tx.query("UPDATE sobatnira.production_batches SET status='approved',approved_by=$2,approved_at=clock_timestamp() WHERE id=$1", [id, access.userId]);
            const snapshot = await this.snapshot(tx, access, {id, lot_id: b.lot_id, is_synthetic: b.is_synthetic}, null);
            await tx.query("INSERT INTO sobatnira.production_batch_events(batch_id,action,actor_id) VALUES($1,'approved',$2)", [id, access.userId]);
            return snapshot;
        });
    }
    private async snapshot(tx: DatabaseSession, access: FactoryAccess,
        batch: {id: string; lot_id: string; is_synthetic: boolean}, correctionId: string | null) {
        const scope = [access.tenantId, access.factoryId, batch.lot_id, batch.is_synthetic];
        const cost = found((await tx.query('SELECT * FROM sobatnira.lot_production_costs WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3', scope.slice(0, 3))).rows[0]);
        const receipt = found((await tx.query('SELECT net_weight_kg::text AS weight FROM sobatnira.intake_records WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4', scope)).rows[0]);
        const grades = (await tx.query(`SELECT g.code,g.weight_kg::text AS "weightKg",g.price_per_kg_rupiah::text AS "pricePerKgRupiah"
FROM sobatnira.batch_grade_results g JOIN sobatnira.production_batches pb ON pb.id=g.batch_id WHERE pb.tenant_id=$1 AND pb.factory_id=$2 AND pb.lot_id=$3 AND pb.is_synthetic=$4 AND pb.status='approved'`, scope)).rows;
        const combined = new Map<string, {
            code: string;
            weightKg: string;
            pricePerKgRupiah: string;
        }>();
        for (const grade of grades) {
            const key = grade.code + ':' + grade.pricePerKgRupiah;
            const previous = combined.get(key);
            if (previous)
                previous.weightKg = sumDecimals([previous.weightKg, grade.weightKg]);
            else
                combined.set(key, { code: 'G_' + combined.size, weightKg: grade.weightKg, pricePerKgRupiah: grade.pricePerKgRupiah });
        }
        const input = { caneNetKg: receipt.weight, caneCostRupiah: String(cost.cane_rupiah), operationalCostRupiah: String(cost.operational_rupiah), ingredientCostRupiah: String(cost.ingredient_rupiah), otherCostRupiah: String(cost.other_rupiah), rounding: 'HALF_UP', grades: [...combined.values()] };
        const preview = calculateProductionPreview(input);
        const output = { ...preview, mode: 'approved', persisted: true, calculationVersion: 'production-v1' };
        return (await tx.query(`INSERT INTO sobatnira.production_calculation_snapshots
          (tenant_id,factory_id,lot_id,batch_id,calculation_version,input_snapshot,output_snapshot,is_synthetic,approved_by,correction_id)
          VALUES($1,$2,$3,$4,'production-v1',$5,$6,$7,$8,$9) RETURNING *`,
          [access.tenantId, access.factoryId, batch.lot_id, batch.id, JSON.stringify(input), JSON.stringify(output),
            batch.is_synthetic, access.userId, correctionId])).rows[0];
    }
    async detail(access: FactoryAccess, id: string) {
        const { rows: [row] } = await this.db.query<{ id: string; code: string; lot_id: string; wok_number: number;
          occurred_at: string; status: string; is_synthetic: boolean; lotClosed: boolean; grades: Grade[] | null }>(`WITH ${FACTORY_SCOPE_CTE}
          SELECT b.*,
            (SELECT to_jsonb(c) - ARRAY['before_data','created_by','updated_by']
             FROM sobatnira.production_batch_corrections c WHERE c.batch_id=b.id AND c.status='draft') AS correction,
            EXISTS(SELECT 1 FROM sobatnira.lot_closures c
              WHERE (c.tenant_id,c.factory_id,c.lot_id,c.is_synthetic)=(b.tenant_id,b.factory_id,b.lot_id,b.is_synthetic)
              AND c.reopened_at IS NULL) AS "lotClosed",
            (SELECT jsonb_agg(jsonb_build_object('code',g.code,'weightKg',g.weight_kg::text,
              'pricePerKgRupiah',g.price_per_kg_rupiah::text) ORDER BY g.code)
             FROM sobatnira.batch_grade_results g WHERE g.batch_id=b.id) AS grades,
            EXISTS(SELECT 1 FROM sobatnira.lot_production_costs c
              WHERE (c.tenant_id,c.factory_id,c.lot_id)=(b.tenant_id,b.factory_id,b.lot_id)) AS "costSaved",
            (SELECT trim_scale(b.quantity_ml-COALESCE(sum(r.quantity_ml),0))::text FROM sobatnira.juice_reservations r
               WHERE (r.tenant_id,r.factory_id,r.batch_id)=(b.tenant_id,b.factory_id,b.id)
                 AND r.lot_id=b.lot_id AND r.origin_lot_id=b.lot_id
                 AND r.is_synthetic=b.is_synthetic AND r.state<>'released') AS "remainingMl"
          FROM sobatnira.production_batches b JOIN authorized_scope s
            ON s."tenantId"=b.tenant_id AND s."factoryId"=b.factory_id WHERE b.id=$4`, [...scopeValues(access), id]);
        const batch = found(row);
        const canManage = access.role === 'admin' && !batch.lotClosed;
        return { ...batch, ...batchGradeTotals(batch.grades ?? []),
            canCorrect: canManage && batch.status === 'approved' };
    }

    async correct(access: FactoryAccess, id: string, correctionId: string, action: 'open' | 'save' | 'approve' | 'discard', input: unknown) {
        const body = object(input, action === 'open' ? ['reason'] :
            action === 'save' ? ['version', 'physicalWeightKg', 'grades'] : ['version']);
        const reason = action === 'open' ? text(body.reason, 'Alasan koreksi', 500) : null;
        const version = body.version as number;
        if (action !== 'open' && (!Number.isSafeInteger(version) || version < 1)) {
            throw new BadRequestException('Versi koreksi tidak valid.');
        }
        const proposed = action === 'save' ? correctionData(body.physicalWeightKg, body.grades) : null;
        const initial = await this.detail(access, id);
        return this.juice.mutate(access, async (tx) => {
            await this.juice.lockLots(tx, access, [initial.lot_id]);
            const scope = [access.tenantId, access.factoryId, initial.lot_id, initial.is_synthetic];
            const batch = found((await tx.query(`SELECT * FROM sobatnira.production_batches
              WHERE tenant_id=$1 AND factory_id=$2 AND id=$3 FOR UPDATE`, [scope[0], scope[1], id])).rows[0]);
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
            if ((await tx.query(`SELECT 1 FROM sobatnira.lot_closures
              WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4 AND reopened_at IS NULL`, scope)).rows.length) {
                throw new ConflictException('Kloter sudah ditutup.');
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
                return result.rows[0];
            }
            if (action === 'save') {
                return (await tx.query(`UPDATE sobatnira.production_batch_corrections
                  SET proposed_data=$2,version=version+1,updated_by=$3,updated_at=clock_timestamp() WHERE id=$1 RETURNING *`,
                  [correctionId, JSON.stringify(proposed), access.userId])).rows[0];
            }
            if (action === 'approve') {
                const data = existing.proposed_data as ReturnType<typeof correctionData>;
                await tx.query('UPDATE sobatnira.production_batches SET physical_weight_kg=$2 WHERE id=$1', [id, data.physicalWeightKg]);
                await tx.query('DELETE FROM sobatnira.batch_grade_results WHERE batch_id=$1', [id]);
                for (const grade of data.grades) {
                    await tx.query(`INSERT INTO sobatnira.batch_grade_results(batch_id,code,weight_kg,price_per_kg_rupiah)
                      VALUES($1,$2,$3,$4)`, [id, grade.code, grade.weightKg, grade.pricePerKgRupiah]);
                }
                await this.snapshot(tx, access, {id, lot_id: batch.lot_id, is_synthetic: batch.is_synthetic}, correctionId);
            }
            return (await tx.query(`UPDATE sobatnira.production_batch_corrections
              SET status=$2,updated_by=$3,updated_at=clock_timestamp() WHERE id=$1 RETURNING *`,
              [correctionId, action === 'approve' ? 'approved' : 'discarded', access.userId])).rows[0];
        });
    }

    async cancel(access: FactoryAccess, id: string) {
        const initial = await this.detail(access, id);
        return this.juice.mutate(access, async (tx) => {
            await this.juice.lockLots(tx, access, [initial.lot_id]);
            const keys = [access.tenantId, access.factoryId, id];
            const row = found((await tx.query(`SELECT * FROM sobatnira.production_batches
              WHERE tenant_id=$1 AND factory_id=$2 AND id=$3 FOR UPDATE`, keys)).rows[0]);
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
        const rows = await this.db.query(`WITH ${FACTORY_SCOPE_CTE} SELECT b.* FROM sobatnira.production_batches b
          JOIN authorized_scope s ON s."tenantId"=b.tenant_id AND s."factoryId"=b.factory_id
          WHERE ($6::uuid IS NULL OR b.lot_id=$6) AND ($7::boolean IS NULL OR b.is_synthetic=$7)
          ORDER BY b.occurred_at DESC,b.id LIMIT $4 OFFSET $5`,
          [...scopeValues(access), page.limit, page.offset, lotId, synthetic]);
        return { items: rows.rows, ...page };
    }
    async productionReport(access: FactoryAccess, query: unknown, maxLots?: number, includeJuiceSources = false) {
        const q = object(query, ['from', 'before', 'synthetic']);
        if (q.synthetic !== undefined && !['true', 'false'].includes(String(q.synthetic)))
            throw new BadRequestException('synthetic tidak valid.');
        const from = q.from === undefined ? null : timestamp(q.from, 'from');
        const before = q.before === undefined ? null : timestamp(q.before, 'before');
        if (from && before && from >= before) throw new BadRequestException('Periode tidak valid.');
        const synthetic = q.synthetic === 'true';
        const items = await this.reportRows(access, synthetic, from, before,
          maxLots === undefined ? null : maxLots + 1, undefined, includeJuiceSources);
        checkReportSize(items, maxLots);
        return { factory: access.factoryName, from, before, synthetic, periodBasis: 'lot_received_at', ...productionReport(items) };
    }

    async compareProductionReports(access: FactoryAccess, first: ReportPeriod, second: ReportPeriod, maxLots: number) {
        const synthetic = first.synthetic === 'true';
        const items = await this.reportRows(access, synthetic, first.from, first.before, maxLots * 2 + 1, second);
        return [first, second].map(({ from, before }) => {
            const lower = Date.parse(from), upper = Date.parse(before);
            const matching = items.filter(lot => {
                const received = new Date(lot.receivedAt).getTime();
                return lower <= received && received < upper;
            });
            checkReportSize(matching, maxLots);
            return { from, before, synthetic, periodBasis: 'lot_received_at', ...productionReport(matching) };
        });
    }

    private async reportRows(access: FactoryAccess, synthetic: boolean, from: string | null, before: string | null,
      limit: number | null, second?: ReportPeriod, includeJuiceSources = false) {
        // A single statement gives receipt, latest cumulative snapshot and approved
        // batch details one consistent PostgreSQL read snapshot, scoped by membership.
        const { rows } = await this.db.query<ProductionReportLot>(`WITH ${FACTORY_SCOPE_CTE}
          SELECT l.id AS "lotId", COALESCE(l.display_code,l.id::text) AS code,
            s.name AS supplier,l.received_at AS "receivedAt",i.net_weight_kg::text AS "caneNetKg",
            i.cane_type_code AS "caneType",trim_scale(COALESCE(mc.quantity_after,m.juice_produced_liters))::text AS "juiceLiters",
            p.id AS "calculationSnapshotId", p.calculation_version AS "calculationVersion",
            p.output_snapshot AS calculation,COALESCE(b.items,'[]'::jsonb) AS batches,
            EXISTS(SELECT 1 FROM sobatnira.lot_closures c
              WHERE (c.tenant_id,c.factory_id,c.lot_id,c.is_synthetic)=(l.tenant_id,l.factory_id,l.id,i.is_synthetic)
              AND c.reopened_at IS NULL) AS closed
          FROM sobatnira.lots l
          JOIN authorized_scope a ON a."tenantId"=l.tenant_id AND a."factoryId"=l.factory_id
          JOIN sobatnira.suppliers s ON s.id=l.supplier_id AND s.tenant_id=l.tenant_id
          JOIN sobatnira.intake_records i ON i.lot_id=l.id AND i.tenant_id=l.tenant_id AND i.factory_id=l.factory_id AND i.is_synthetic=$4
          LEFT JOIN sobatnira.milling_records m ON m.lot_id=l.id AND m.tenant_id=l.tenant_id AND m.factory_id=l.factory_id AND m.is_synthetic=$4
          LEFT JOIN LATERAL (SELECT quantity_after FROM sobatnira.stock_reconciliations WHERE milling_record_id=m.id ORDER BY revision_version DESC LIMIT 1) mc ON true
          LEFT JOIN LATERAL (SELECT id,calculation_version,output_snapshot FROM sobatnira.production_calculation_snapshots
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
            ) ORDER BY pb.occurred_at,pb.id) AS items FROM sobatnira.production_batches pb
            WHERE pb.lot_id=l.id AND pb.tenant_id=l.tenant_id AND pb.factory_id=l.factory_id AND pb.is_synthetic=$4 AND pb.status='approved') b ON true
          WHERE ($5::timestamptz IS NULL OR l.received_at >= $5) AND ($6::timestamptz IS NULL OR l.received_at < $6)
            OR (l.received_at >= $8::timestamptz AND l.received_at < $9::timestamptz)
          ORDER BY l.received_at DESC,l.id LIMIT $7`, [...scopeValues(access), synthetic, from, before, limit,
            second?.from ?? null, second?.before ?? null]);
        return rows;
    }

    async report(access: FactoryAccess, query: unknown, includeBatches = false) {

        const q = object(query, ['from', 'before', 'synthetic']);
        if (q.synthetic !== undefined && !['true', 'false'].includes(String(q.synthetic)))
            throw new BadRequestException('synthetic tidak valid.');
        const from = q.from === undefined ? null : timestamp(q.from, 'from'), before = q.before === undefined ? null : timestamp(q.before, 'before');
        if (from && before && from >= before)
            throw new BadRequestException('Periode tidak valid.');
        // Latest cumulative snapshot per lot; report period follows lot receipt time.
        const rows = (await this.db.query(`WITH ${FACTORY_SCOPE_CTE}, latest AS (
   SELECT DISTINCT ON(p.lot_id) p.* FROM sobatnira.production_calculation_snapshots p JOIN authorized_scope s ON s."tenantId"=p.tenant_id AND s."factoryId"=p.factory_id
   WHERE p.is_synthetic=$4 ORDER BY p.lot_id,p.approved_at DESC,p.id DESC)
   SELECT l.id AS "lotId",l.display_code AS code,s.name AS supplier,l.received_at AS "receivedAt",p.id AS "snapshotId",p.output_snapshot AS calculation,
    EXISTS(SELECT 1 FROM sobatnira.lot_closures c WHERE (c.tenant_id,c.factory_id,c.lot_id,c.is_synthetic)=
      (p.tenant_id,p.factory_id,p.lot_id,p.is_synthetic) AND c.reopened_at IS NULL) AS closed
    ${includeBatches ? `, (SELECT jsonb_agg(jsonb_build_object('id',b.id,'code',b.code,'wokNumber',b.wok_number,
       'occurredAt',b.occurred_at,'volumeMl',b.quantity_ml::text,'physicalWeightKg',b.physical_weight_kg::text,
       'grades',(SELECT jsonb_agg(jsonb_build_object('code',g.code,'weightKg',g.weight_kg::text) ORDER BY g.code)
         FROM sobatnira.batch_grade_results g WHERE g.batch_id=b.id)) ORDER BY b.occurred_at,b.id)
       FROM sobatnira.production_batches b
       WHERE (b.tenant_id,b.factory_id,b.lot_id,b.is_synthetic)=(p.tenant_id,p.factory_id,p.lot_id,p.is_synthetic)
         AND b.status='approved' AND EXISTS(SELECT 1 FROM sobatnira.production_calculation_snapshots bs
           WHERE bs.batch_id=b.id AND bs.correction_id IS NULL AND (bs.approved_at,bs.id)<=(p.approved_at,p.id))) AS batches` : ''}
   FROM latest p JOIN sobatnira.lots l ON l.id=p.lot_id JOIN sobatnira.suppliers s ON s.id=l.supplier_id
   WHERE ($5::timestamptz IS NULL OR l.received_at >= $5) AND ($6::timestamptz IS NULL OR l.received_at < $6)
   ORDER BY l.received_at DESC,l.id`, [...scopeValues(access), q.synthetic === 'true', from, before])).rows;
        return { factory: access.factoryName, from, before, synthetic: q.synthetic === 'true', items: rows,
            total: rows.length, totalSugarKg: sumDecimals(rows.map(r => r.calculation.finalSugarKg)),
            totalMarginRupiah: rows.reduce((v, r) => v + BigInt(r.calculation.productionMarginRupiah), 0n).toString() };
    }
}
@Controller('tenants/:tenantId/factories/:factoryId/production')
@FactoryRoles('admin', 'owner')
export class BatchesController {
    constructor(private readonly batches: Batches) { }
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
