import { Body, Controller, Get, Headers, Post } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { ProductionMastersService } from './production-masters.service';
import { MasterKind } from './production-masters.types';

@Controller('production-masters')
@FactoryRoles('admin', 'owner')
export class ProductionMastersController {
  constructor(private readonly service: ProductionMastersService) {}
  private scope(access: FactoryAccess) { return { tenantId: access.tenantId, factoryId: access.factoryId, role: access.role }; }
  @Get('pans') pans(@CurrentFactory() access: FactoryAccess) { return this.service.list(this.scope(access), 'pans'); }
  @Get('grades') grades(@CurrentFactory() access: FactoryAccess) { return this.service.list(this.scope(access), 'grades'); }
  @Get('additives') additives(@CurrentFactory() access: FactoryAccess) { return this.service.list(this.scope(access), 'additives'); }
  @Get('configs') configs(@CurrentFactory() access: FactoryAccess) { return this.service.config(this.scope(access)); }
  @Get('prices') prices(@CurrentFactory() access: FactoryAccess) { return this.service.pricesList(this.scope(access)); }
  @Post('pans') @FactoryRoles('admin') createPan(@CurrentFactory() access: FactoryAccess, @Body() body: { code: string; name: string }) { return this.service.create(this.scope(access), 'pans', body); }
  @Post('grades') @FactoryRoles('admin') createGrade(@CurrentFactory() access: FactoryAccess, @Body() body: { code: string; name: string }) { return this.service.create(this.scope(access), 'grades', body); }
  @Post('additives') @FactoryRoles('admin') createAdditive(@CurrentFactory() access: FactoryAccess, @Body() body: { code: string; name: string }) { return this.service.create(this.scope(access), 'additives', body); }
  @Post('configs') @FactoryRoles('admin') createConfig(@CurrentFactory() access: FactoryAccess, @Body() body: { code: string; name: string; maxNiraMl?: number }) { return this.service.createConfig(this.scope(access), body); }
  @Post('prices') @FactoryRoles('admin') createPrice(@CurrentFactory() access: FactoryAccess, @Body() body: { code: string; name: string; effectiveAt: string; prices: Record<string, number> }) { return this.service.createPrice(this.scope(access), body); }
}
