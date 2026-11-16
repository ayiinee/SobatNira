import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { EconomicsService } from './economics.service';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';

@Controller()
@FactoryRoles('admin', 'owner')
export class EconomicsController {
  constructor(private readonly service: EconomicsService) {}
  private scope(access: FactoryAccess) { return { tenantId: access.tenantId, factoryId: access.factoryId, role: access.role }; }
  @Get('stock/sugar') stock(@CurrentFactory() access: FactoryAccess, @Query('grade') grade?: string) { return this.service.stock(this.scope(access), grade); }
  @Post('stock/sugar/movements') @FactoryRoles('admin') movement(@CurrentFactory() access: FactoryAccess, @Headers('idempotency-key') key: string | undefined, @Body() body: { gradeCode: string; deltaGrams: number; reason: string; batchId?: string; correctionOfMovementId?: string; occurredAt?: string }) { return this.service.addMovement(this.scope(access), body, key); }
  @Post('stock/sugar/corrections') @FactoryRoles('admin') correction(@CurrentFactory() access: FactoryAccess, @Headers('idempotency-key') key: string | undefined, @Body() body: { gradeCode: string; deltaGrams: number; reason: string; correctionOfMovementId: string; batchId?: string; occurredAt?: string }) { return this.service.addMovement(this.scope(access), { ...body, reason: body.reason.startsWith('CORRECTION') ? body.reason : `CORRECTION_${body.reason}` }, key); }
  @Get('batches/:id/economics') summary(@CurrentFactory() access: FactoryAccess, @Param('id') id: string) { return this.service.summary(this.scope(access), id); }
  @Post('batches/:id/economics/allocation') @FactoryRoles('admin') allocation(@CurrentFactory() access: FactoryAccess, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { totalCostRupiah: number; totalRevenueRupiah: number }) { return this.service.allocate(this.scope(access), id, body, key); }
}
