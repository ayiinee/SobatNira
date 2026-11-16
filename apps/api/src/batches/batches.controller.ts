import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { BatchesService } from './batches.service';
import { BatchInput } from './batches.types';

@Controller('batches')
export class BatchesController {
  constructor(private readonly service: BatchesService) {}
  private scope(headers: Record<string, string | undefined>) { return { tenantId: headers['x-dev-tenant-id'] ?? '', factoryId: headers['x-dev-factory-id'] ?? '', role: headers['x-dev-role'] ?? '' }; }
  @Get() list(@Headers() headers: Record<string, string | undefined>, @Query() query: { status?: string; from?: string; to?: string }) { return this.service.list(this.scope(headers), query); }
  @Get('nira/:kloterId/availability') niraAvailability(@Headers() headers: Record<string, string | undefined>, @Param('kloterId') kloterId: string) { return this.service.niraAvailability(this.scope(headers), kloterId); }
  @Get('closure-check/:kloterId') closureCheck(@Headers() headers: Record<string, string | undefined>, @Param('kloterId') kloterId: string) { return this.service.closureCheck(this.scope(headers), kloterId); }
  @Get(':id') get(@Headers() headers: Record<string, string | undefined>, @Param('id') id: string) { return this.service.get(this.scope(headers), id); }
  @Post() create(@Headers() headers: Record<string, string | undefined>, @Headers('idempotency-key') key: string | undefined, @Body() body: BatchInput) { return this.service.create(this.scope(headers), body, key); }
  @Post(':id/contributions') contribution(@Headers() headers: Record<string, string | undefined>, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { kloterId?: string; lotId?: string; volumeMl: number; occurredAt?: string }) { return this.service.contribution(this.scope(headers), id, body, key); }
  @Post(':id/cooking') cooking(@Headers() headers: Record<string, string | undefined>, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { startedAt: string; endedAt?: string; additiveIds?: string[] }) { return this.service.cooking(this.scope(headers), id, body, key); }
  @Post(':id/weighing') weighing(@Headers() headers: Record<string, string | undefined>, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { sugarWeightGrams: number; caneWeightGrams?: number; occurredAt?: string }) { return this.service.weighing(this.scope(headers), id, body, key); }
  @Post(':id/grading') grading(@Headers() headers: Record<string, string | undefined>, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { gradeCode: string; occurredAt?: string }) { return this.service.grading(this.scope(headers), id, body, key); }
  @Post(':id/reworks') rework(@Headers() headers: Record<string, string | undefined>, @Headers('idempotency-key') key: string | undefined, @Param('id') id: string, @Body() body: { receivingBatchId: string; weightGrams: number; occurredAt?: string }) { return this.service.rework(this.scope(headers), id, body, key); }
  @Get(':id/traceability') traceability(@Headers() headers: Record<string, string | undefined>, @Param('id') id: string) { return this.service.traceability(this.scope(headers), id); }
}
