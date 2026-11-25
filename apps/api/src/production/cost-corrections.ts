import { BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Injectable, Param, Post } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { JuiceRepository } from '../juice/juice.repository';
import { DatabaseService } from '../database/database.service';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { calculateProductionPreview } from './calculation';
import { found, object, scopeValues, text, uuid } from './production.dto';
import { rebuildSnapshots } from './snapshots';

@Injectable()
export class CostCorrections {
  constructor(private readonly juice: JuiceRepository, private readonly db: DatabaseService) {}

  async current(access: FactoryAccess, lotId: string) {
    return found((await this.db.query(`WITH ${FACTORY_SCOPE_CTE} SELECT c.*,
      EXISTS (SELECT 1 FROM sobatnira.production_calculation_snapshots s
        WHERE (s.tenant_id,s.factory_id,s.lot_id)=(c.tenant_id,c.factory_id,c.lot_id)) AS frozen
      FROM sobatnira.lot_production_costs c
      JOIN authorized_scope a ON (c.tenant_id,c.factory_id)=(a."tenantId",a."factoryId")
      WHERE c.lot_id=$4`, [...scopeValues(access), lotId])).rows[0]);
  }

  request(access: FactoryAccess, lotId: string, id: string, body: unknown) {
    const b = object(body, ['version', 'reason', 'caneCostRupiah', 'operationalCostRupiah', 'ingredientCostRupiah', 'otherCostRupiah']);
    if (!Number.isSafeInteger(b.version) || Number(b.version) < 1) throw new BadRequestException('Versi biaya tidak valid.');
    const reason = text(b.reason, 'reason', 500);
    const costs = calculateProductionPreview({ caneNetKg: '1', rounding: 'HALF_UP',
      caneCostRupiah: b.caneCostRupiah, operationalCostRupiah: b.operationalCostRupiah,
      ingredientCostRupiah: b.ingredientCostRupiah, otherCostRupiah: b.otherCostRupiah,
      grades: [{ code: 'CHECK', weightKg: '1', pricePerKgRupiah: '0' }] }).costs;
    const hash = createHash('sha256').update(JSON.stringify([lotId, b.version, reason, costs])).digest('hex');
    return this.juice.mutate(access, async tx => {
      await this.juice.lockLots(tx, access, [lotId]);
      const old = (await tx.query('SELECT * FROM sobatnira.production_cost_corrections WHERE id=$1', [id])).rows[0];
      if (old) {
        if (old.tenant_id !== access.tenantId || old.factory_id !== access.factoryId || old.input_hash !== hash)
          throw new ConflictException('ID koreksi sudah dipakai.');
        return old;
      }
      const cost = found((await tx.query(`SELECT version FROM sobatnira.lot_production_costs
        WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 FOR UPDATE`, [access.tenantId, access.factoryId, lotId])).rows[0]);
      if (cost.version !== b.version) throw new ConflictException('Biaya sudah berubah. Muat ulang.');
      return (await tx.query(`INSERT INTO sobatnira.production_cost_corrections
        (id,tenant_id,factory_id,lot_id,expected_version,reason,proposed_data,input_hash,created_by)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
        [id, access.tenantId, access.factoryId, lotId, b.version, reason, JSON.stringify(costs), hash, access.userId])).rows[0];
    });
  }

  approve(access: FactoryAccess, lotId: string, id: string) {
    if (access.role !== 'owner') throw new ForbiddenException('Persetujuan koreksi biaya memerlukan owner.');
    return this.juice.mutate(access, async tx => {
      await this.juice.lockLots(tx, access, [lotId]);
      const correction = found((await tx.query(`SELECT * FROM sobatnira.production_cost_corrections
        WHERE id=$1 AND tenant_id=$2 AND factory_id=$3 AND lot_id=$4 FOR UPDATE`,
        [id, access.tenantId, access.factoryId, lotId])).rows[0]);
      if (correction.status === 'approved') return correction;
      const p = correction.proposed_data;
      const changed = await tx.query(`UPDATE sobatnira.lot_production_costs SET cane_rupiah=$4,
        operational_rupiah=$5,ingredient_rupiah=$6,other_rupiah=$7,version=version+1,
        updated_by=$8,updated_at=clock_timestamp() WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3
        AND version=$9 RETURNING *`, [access.tenantId, access.factoryId, lotId,
        p.caneRupiah, p.operationalRupiah, p.ingredientRupiah, p.otherRupiah, access.userId, correction.expected_version]);
      if (!changed.rows.length) throw new ConflictException('Biaya sudah berubah. Ajukan koreksi baru.');
      // A donor lot may have no cooking batch of its own; find its connected batch.
      const batches = (await tx.query(`SELECT DISTINCT b.id,b.lot_id,b.is_synthetic FROM sobatnira.production_batches b
        LEFT JOIN sobatnira.juice_reservations r ON r.batch_id=b.id AND r.state='consumed'
        WHERE b.tenant_id=$1 AND b.factory_id=$2 AND b.status='approved'
        AND (b.lot_id=$3 OR r.origin_lot_id=$3) ORDER BY b.id`, [access.tenantId, access.factoryId, lotId])).rows;
      for (const synthetic of [false, true]) {
        const batch = batches.find(b => b.is_synthetic === synthetic);
        if (batch) await rebuildSnapshots(tx, access, { id: batch.id, lot_id: lotId, is_synthetic: synthetic }, null, id);
      }
      return (await tx.query(`UPDATE sobatnira.production_cost_corrections SET status='approved',approved_by=$2,
        approved_at=clock_timestamp() WHERE id=$1 RETURNING *`, [id, access.userId])).rows[0];
    });
  }
}

@Controller('tenants/:tenantId/factories/:factoryId/production/lots/:lotId/cost-corrections')
@FactoryRoles('admin', 'owner')
export class CostCorrectionsController {
  constructor(private readonly costs: CostCorrections) {}
  @Get()
  current(@CurrentFactory() a: FactoryAccess, @Param('lotId') lot: string) {
    return this.costs.current(a, uuid(lot));
  }
  @Post(':id')
  request(@CurrentFactory() a: FactoryAccess, @Param('lotId') lot: string, @Param('id') id: string, @Body() b: unknown) {
    return this.costs.request(a, uuid(lot), uuid(id), b);
  }
  @Post(':id/approve')
  @FactoryRoles('owner')
  approve(@CurrentFactory() a: FactoryAccess, @Param('lotId') lot: string, @Param('id') id: string) {
    return this.costs.approve(a, uuid(lot), uuid(id));
  }
}
