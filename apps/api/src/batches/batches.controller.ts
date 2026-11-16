import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { BatchesService } from './batches.service';
import { BatchInput } from './batches.types';

@Controller('batches')
@FactoryRoles('admin', 'owner')
export class BatchesController {
  constructor(private readonly service: BatchesService) {}
  private scope(headers: Record<string, string | undefined>) { return { tenantId: headers['x-dev-tenant-id'] ?? '', factoryId: headers['x-dev-factory-id'] ?? '', role: headers['x-dev-role'] ?? '' }; }
  private accessScope(access: FactoryAccess) { return { tenantId: access.tenantId, factoryId: access.factoryId, role: access.role, userId: access.userId }; }
  @Get() list(@CurrentFactory() access: FactoryAccess, @Query() query: { status?: string; from?: string; to?: string }) { return this.service.list(this.accessScope(access), query); }
  @Get('nira/:kloterId/availability') niraAvailability(@CurrentFactory() access: FactoryAccess, @Param('kloterId') kloterId: string) { return this.service.niraAvailability(this.accessScope(access), kloterId); }
  @Get('closure-check/:kloterId') closureCheck(@CurrentFactory() access: FactoryAccess, @Param('kloterId') kloterId: string) { return this.service.closureCheck(this.accessScope(access), kloterId); }
  @Get(':id') get(@CurrentFactory() access: FactoryAccess, @Param('id') id: string) { return this.service.get(this.accessScope(access), id); }
  @Post() create(@CurrentFactory() access: FactoryAccess, @Headers('idempotency-key') key: string | undefined, @Body() body: BatchInput) { return this.service.create(this.accessScope(access), body, key); }
  @Post(':id/contributions') @FactoryRoles('admin') contribution(@CurrentFactory() access: FactoryAccess, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { kloterId?: string; lotId?: string; volumeMl: number; occurredAt?: string }) { return this.service.contribution(this.accessScope(access), id, body, key); }
  @Post(':id/cooking') @FactoryRoles('admin') cooking(@CurrentFactory() access: FactoryAccess, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { startedAt: string; endedAt?: string; additiveIds?: string[] }) { return this.service.cooking(this.accessScope(access), id, body, key); }
  @Post(':id/weighing') @FactoryRoles('admin') weighing(@CurrentFactory() access: FactoryAccess, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { sugarWeightGrams: number; caneWeightGrams?: number; occurredAt?: string }) { return this.service.weighing(this.accessScope(access), id, body, key); }
  @Post(':id/grading') @FactoryRoles('admin') grading(@CurrentFactory() access: FactoryAccess, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { gradeCode: string; occurredAt?: string }) { return this.service.grading(this.accessScope(access), id, body, key); }
  @Post(':id/reworks') @FactoryRoles('admin') rework(@CurrentFactory() access: FactoryAccess, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { receivingBatchId: string; weightGrams: number; occurredAt?: string }) { return this.service.rework(this.accessScope(access), id, body, key); }
  @Get(':id/traceability') traceability(@CurrentFactory() access: FactoryAccess, @Param('id') id: string) { return this.service.traceability(this.accessScope(access), id); }
}
