import { Controller, Get, Headers, Header, Query } from '@nestjs/common';
import { ReportingService } from './reporting.service';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';

@Controller()
@FactoryRoles('admin', 'owner')
export class ReportingController {
  constructor(private readonly service: ReportingService) {}
  private scope(access: FactoryAccess) { return { tenantId: access.tenantId, factoryId: access.factoryId, role: access.role }; }
  @Get('dashboard/production') dashboard(@CurrentFactory() access: FactoryAccess, @Query() query: { from?: string; to?: string }) { return this.service.dashboard(this.scope(access), query); }
  @Get('analytics/production') analytics(@CurrentFactory() access: FactoryAccess, @Query() query: { from?: string; to?: string }) { return this.service.analytics(this.scope(access), query); }
  @Get('exports/batches.csv') @Header('Content-Type', 'text/csv; charset=utf-8') exportCsv(@CurrentFactory() access: FactoryAccess, @Query() query: { from?: string; to?: string }) { return this.service.exportCsv(this.scope(access), query); }
}
