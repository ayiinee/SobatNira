import { Controller, Get, Headers, Header, Query } from '@nestjs/common';
import { ReportingService } from './reporting.service';

@Controller()
export class ReportingController {
  constructor(private readonly service: ReportingService) {}
  private scope(headers: Record<string, string | undefined>) { return { tenantId: headers['x-dev-tenant-id'] ?? '', factoryId: headers['x-dev-factory-id'] ?? '', role: headers['x-dev-role'] ?? '' }; }
  @Get('dashboard/production') dashboard(@Headers() headers: Record<string, string | undefined>, @Query() query: { from?: string; to?: string }) { return this.service.dashboard(this.scope(headers), query); }
  @Get('analytics/production') analytics(@Headers() headers: Record<string, string | undefined>, @Query() query: { from?: string; to?: string }) { return this.service.analytics(this.scope(headers), query); }
  @Get('exports/batches.csv') @Header('Content-Type', 'text/csv; charset=utf-8') exportCsv(@Headers() headers: Record<string, string | undefined>, @Query() query: { from?: string; to?: string }) { return this.service.exportCsv(this.scope(headers), query); }
}
