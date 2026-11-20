import { BadRequestException, Body, Controller, ForbiddenException, HttpCode, Injectable, Post } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService } from '../database/database.service';
import { Review } from '../documents/review';
import { LotsRepository } from '../lots/lots.repository';
import { Batches } from './batches';
import { contributionRanking } from './production-report';
import { sumDecimals } from './decimal';
import { found, object, parsePage, scopeValues, timestamp, uuid } from './production.dto';

function synthetic(value: unknown) {
  if (value !== undefined && typeof value !== 'boolean') throw new BadRequestException('synthetic harus boolean.');
  return value === true;
}

function period(input: unknown, useSynthetic: boolean) {
  const value = object(input, ['from', 'before']);
  const from = timestamp(value.from, 'from');
  const before = timestamp(value.before, 'before');
  const duration = Date.parse(before) - Date.parse(from);
  if (duration <= 0 || duration > 366 * 86_400_000) throw new BadRequestException('Periode maksimum 366 hari.');
  return { from, before, synthetic: String(useSynthetic) };
}

@Injectable()
export class Capabilities {
  constructor(private readonly batches: Batches, private readonly lots: LotsRepository,
    private readonly db: DatabaseService, private readonly review: Review) {}

  async query(access: FactoryAccess, input: unknown) {
    if (access.role !== 'owner') throw new ForbiddenException('Akses owner diperlukan.');
    const body = object(input, ['operation', 'arguments', 'request_id', 'correlation_id']);
    const request_id = body.request_id === undefined ? randomUUID() : uuid(body.request_id, 'request_id');
    const correlation_id = body.correlation_id === undefined ? request_id : uuid(body.correlation_id, 'correlation_id');
    const scope = { tenantId: access.tenantId, factoryId: access.factoryId };
    const reply = (result: unknown, sources: unknown[], missing_relations: string[] = [],
      data_status = missing_relations.length ? 'partial' : 'complete', limitations: string[] = []) => ({
      operation: body.operation, request_id, correlation_id, scope, status: missing_relations.length ? 'partial' : 'ok',
      data_status, missing_relations, limitations, sources, result, generated_at: new Date().toISOString(),
    });

    switch (body.operation) {
      case 'get_lot_traceability': {
        const args = object(body.arguments, ['lotId', 'synthetic']);
        const lot = found(await this.lots.find(access, uuid(args.lotId, 'lotId'), synthetic(args.synthetic)));
        const missing = [...(lot.intake ? [] : ['approved_intake']), ...(lot.milling ? [] : ['approved_milling'])];
        return reply({ id: lot.id, code: lot.displayCode, status: lot.status, receivedAt: lot.receivedAt,
          synthetic: lot.synthetic, intake: lot.intake, milling: lot.milling },
        [{ resource: 'lots', id: lot.id }], missing);
      }
      case 'get_batch_traceability': {
        const args = object(body.arguments, ['batchId']);
        const batch = await this.batches.detail(access, uuid(args.batchId, 'batchId'));
        found(batch.status === 'approved' ? batch : undefined);
        const rows = await this.contributions(access, 'batch', batch.id, 0);
        return reply({ batchId: batch.id, code: batch.code, lotId: batch.lot_id, wokNumber: batch.wok_number,
          occurredAt: batch.occurred_at, synthetic: batch.is_synthetic, grades: batch.grades, ...rows },
        [{ resource: 'production_batches', id: batch.id }, { resource: 'juice_reservations' }],
        ['official_rework_link', ...(rows.nextOffset !== null ? ['additional_contribution_rows'] :
          rows.items.length ? [] : ['consumed_nira'])]);
      }
      case 'get_document_lineage': {
        const args = object(body.arguments, ['documentId', 'beforeVersion']);
        const documentId = uuid(args.documentId, 'documentId');
        const version = args.beforeVersion;
        if (version !== undefined && (typeof version !== 'number' || !Number.isInteger(version) ||
          version < 1 || version > 2147483647)) throw new BadRequestException('beforeVersion tidak valid.');
        const lineage = await this.review.lineage(access.userId, scope.factoryId, documentId, version ?? null);
        const missing = lineage.nextBeforeVersion !== null ? ['earlier_revisions'] : [];
        return reply(lineage, [{ resource: 'source_documents', id: documentId }], missing);
      }
      case 'get_lot_contribution_summary':
      case 'get_material_contributions': {
        const args = object(body.arguments, ['lotId', 'batchId', 'synthetic', 'offset']);
        const useLot = args.lotId !== undefined;
        const useBatch = args.batchId !== undefined;
        if (useLot === useBatch || (useBatch && (args.synthetic !== undefined ||
          body.operation === 'get_lot_contribution_summary'))) throw new BadRequestException('Pilih satu rujukan yang didukung.');
        const id = useLot ? uuid(args.lotId, 'lotId') : uuid(args.batchId, 'batchId');
        const isSynthetic = synthetic(args.synthetic);
        if (useLot) found(await this.lots.find(access, id, isSynthetic));
        else {
          const batch = await this.batches.detail(access, id);
          found(batch.status === 'approved' ? batch : undefined);
        }
        const { offset } = parsePage({ offset: args.offset });
        const rows = await this.contributions(access, useLot ? 'origin' : 'batch', id, offset, isSynthetic);
        const result = { ...rows, unit: 'mL', ...(body.operation === 'get_lot_contribution_summary'
          ? { pageConsumedQuantityMl: sumDecimals(rows.items.map(r => r.quantityMl)) } : {}) };
        return reply(result, [{ resource: 'juice_reservations' }],
          rows.nextOffset !== null ? ['additional_contribution_rows'] : [], rows.items.length
            ? rows.nextOffset !== null ? 'partial' : 'complete' : 'no_data', ['approved_consumed_nira_only']);
      }
      case 'compare_production_periods': {
        const args = object(body.arguments, ['first', 'second', 'synthetic']);
        const useSynthetic = synthetic(args.synthetic);
        const firstPeriod = period(args.first, useSynthetic);
        const secondPeriod = period(args.second, useSynthetic);
        const [first, second] = await this.batches.compareProductionReports(access, firstPeriod, secondPeriod, 500);
        const summarize = (report: typeof first) => ({ from: report.from, before: report.before,
          periodBasis: report.periodBasis, synthetic: report.synthetic, totals: report.totals });
        return reply({ first: summarize(first), second: summarize(second) },
          [...this.reportSources(first.items), ...this.reportSources(second.items)], [],
          first.items.length || second.items.length ? 'complete' : 'no_data', ['margin_has_business_scope_limits']);
      }
      case 'get_production_insight': {
        const args = object(body.arguments, ['from', 'before', 'synthetic', 'contributionBasis']);
        const basis = args.contributionBasis;
        if (basis !== undefined && basis !== 'consumed_nira_by_lot_received_at') {
          throw new BadRequestException('Basis kontribusi tidak didukung.');
        }
        const report = await this.batches.productionReport(access,
          period({ from: args.from, before: args.before }, synthetic(args.synthetic)), 500, basis !== undefined);
        const { from, before, periodBasis, synthetic: isSynthetic, totals, grades, items } = report;
        const contributions = basis === undefined ? undefined : { basis, ...contributionRanking(items) };
        const missing = contributions?.status === 'incomplete' ? ['incomplete_consumed_nira'] : [];
        return reply({ from, before, periodBasis, synthetic: isSynthetic, totals, grades, contributions },
          this.reportSources(items), missing, items.length ? missing.length ? 'partial' : 'complete' : 'no_data',
          ['margin_has_business_scope_limits']);
      }
      case 'get_production_summary':
      case 'get_grade_distribution':
      case 'get_production_metrics':
      case 'get_report_snapshot': {
        const args = object(body.arguments, ['from', 'before', 'synthetic']);
        const report = await this.batches.productionReport(access,
          period({ from: args.from, before: args.before }, synthetic(args.synthetic)), 500);
        const { from, before, periodBasis, synthetic: isSynthetic, totals, grades, items } = report;
        const result = { from, before, periodBasis, synthetic: isSynthetic,
          ...(body.operation === 'get_grade_distribution' ? { grades } : { totals }),
          ...(body.operation === 'get_report_snapshot' ? { grades, items } : {}),
          ...(body.operation === 'get_production_metrics' ? { lotMetrics: items.flatMap(lot => lot.calculation
            ? [{ lotId: lot.lotId, ...lot.calculation }] : []) } : {}),
        };
        return reply(result, this.reportSources(items), [], items.length ? 'complete' : 'no_data',
          body.operation === 'get_grade_distribution' ? [] : ['margin_has_business_scope_limits']);
      }
      default:
        throw new BadRequestException('Operasi capability tidak didukung.');
    }
  }

  private reportSources(items: Awaited<ReturnType<Batches['productionReport']>>['items']) {
    return items.map(lot => ({ lotId: lot.lotId,
      snapshotId: lot.calculationSnapshotId, calculationVersion: lot.calculationVersion,
      batchIds: lot.batches.map(batch => batch.id) }));
  }

  private async contributions(access: FactoryAccess, kind: 'origin' | 'batch', id: string, offset: number, synthetic = false) {
    const { rows } = await this.db.query<{ reservationId: string; batchId: string; originLotId: string;
      stockLotId: string; quantityMl: string }>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT r.request_id AS "reservationId",r.batch_id AS "batchId",r.origin_lot_id AS "originLotId",
        r.lot_id AS "stockLotId",trim_scale(r.quantity_ml)::text AS "quantityMl"
      FROM sobatnira.juice_reservations r JOIN authorized_scope a
        ON (a."tenantId",a."factoryId")=(r.tenant_id,r.factory_id)
      JOIN sobatnira.production_batches b ON (b.tenant_id,b.factory_id,b.id,b.is_synthetic)
        =(r.tenant_id,r.factory_id,r.batch_id,r.is_synthetic)
      WHERE b.status='approved' AND r.state='consumed' AND
        CASE WHEN $4::boolean THEN r.origin_lot_id=$5 AND r.is_synthetic=$6 ELSE r.batch_id=$5 END
      ORDER BY r.finalized_at,r.request_id LIMIT 101 OFFSET $7`,
    [...scopeValues(access), kind === 'origin', id, synthetic, offset]);
    return { items: rows.slice(0, 100), nextOffset: rows.length > 100 ? offset + 100 : null };
  }
}

@Controller('tenants/:tenantId/factories/:factoryId/capabilities')
@FactoryRoles('owner')
export class CapabilitiesController {
  constructor(private readonly capabilities: Capabilities) {}

  @Post('query')
  @HttpCode(200)
  query(@CurrentFactory() access: FactoryAccess, @Body() input: unknown) {
    return this.capabilities.query(access, input);
  }
}
