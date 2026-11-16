import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { EconomicsService } from './economics.service';

@Controller()
export class EconomicsController {
  constructor(private readonly service: EconomicsService) {}
  private scope(headers: Record<string, string | undefined>) { return { tenantId: headers['x-dev-tenant-id'] ?? '', factoryId: headers['x-dev-factory-id'] ?? '', role: headers['x-dev-role'] ?? '' }; }
  @Get('stock/sugar') stock(@Headers() headers: Record<string, string | undefined>, @Query('grade') grade?: string) { return this.service.stock(this.scope(headers), grade); }
  @Post('stock/sugar/movements') movement(@Headers() headers: Record<string, string | undefined>, @Headers('idempotency-key') key: string | undefined, @Body() body: { gradeCode: string; deltaGrams: number; reason: string; batchId?: string; correctionOfMovementId?: string; occurredAt?: string }) { return this.service.addMovement(this.scope(headers), body, key); }
  @Post('stock/sugar/corrections') correction(@Headers() headers: Record<string, string | undefined>, @Headers('idempotency-key') key: string | undefined, @Body() body: { gradeCode: string; deltaGrams: number; reason: string; correctionOfMovementId: string; batchId?: string; occurredAt?: string }) { return this.service.addMovement(this.scope(headers), { ...body, reason: body.reason.startsWith('CORRECTION') ? body.reason : `CORRECTION_${body.reason}` }, key); }
  @Get('batches/:id/economics') summary(@Headers() headers: Record<string, string | undefined>, @Param('id') id: string) { return this.service.summary(this.scope(headers), id); }
  @Post('batches/:id/economics/allocation') allocation(@Headers() headers: Record<string, string | undefined>, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { totalCostRupiah: number; totalRevenueRupiah: number }) { return this.service.allocate(this.scope(headers), id, body, key); }
}
