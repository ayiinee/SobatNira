import { Body, Controller, Get, Headers, Post } from '@nestjs/common';
import { ProductionMastersService } from './production-masters.service';
import { MasterKind } from './production-masters.types';

@Controller('production-masters')
export class ProductionMastersController {
  constructor(private readonly service: ProductionMastersService) {}
  private scope(headers: Record<string, string | undefined>) { return { tenantId: headers['x-dev-tenant-id'] ?? '', factoryId: headers['x-dev-factory-id'] ?? '', role: headers['x-dev-role'] ?? '' }; }
  @Get('pans') pans(@Headers() headers: Record<string, string | undefined>) { return this.service.list(this.scope(headers), 'pans'); }
  @Get('grades') grades(@Headers() headers: Record<string, string | undefined>) { return this.service.list(this.scope(headers), 'grades'); }
  @Get('additives') additives(@Headers() headers: Record<string, string | undefined>) { return this.service.list(this.scope(headers), 'additives'); }
  @Get('configs') configs(@Headers() headers: Record<string, string | undefined>) { return this.service.config(this.scope(headers)); }
  @Get('prices') prices(@Headers() headers: Record<string, string | undefined>) { return this.service.pricesList(this.scope(headers)); }
  @Post('pans') createPan(@Headers() headers: Record<string, string | undefined>, @Body() body: { code: string; name: string }) { return this.service.create(this.scope(headers), 'pans', body); }
  @Post('grades') createGrade(@Headers() headers: Record<string, string | undefined>, @Body() body: { code: string; name: string }) { return this.service.create(this.scope(headers), 'grades', body); }
  @Post('additives') createAdditive(@Headers() headers: Record<string, string | undefined>, @Body() body: { code: string; name: string }) { return this.service.create(this.scope(headers), 'additives', body); }
  @Post('configs') createConfig(@Headers() headers: Record<string, string | undefined>, @Body() body: { code: string; name: string; maxNiraMl?: number }) { return this.service.createConfig(this.scope(headers), body); }
  @Post('prices') createPrice(@Headers() headers: Record<string, string | undefined>, @Body() body: { code: string; name: string; effectiveAt: string; prices: Record<string, number> }) { return this.service.createPrice(this.scope(headers), body); }
}
