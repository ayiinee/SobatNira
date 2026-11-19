import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { calculateProductionPreview, calculateProductionRecapPreview } from './calculation';

@Controller('tenants/:tenantId/factories/:factoryId/production')
@FactoryRoles('admin', 'owner')
export class CalculationController {
  @Post('calculation-preview')
  @HttpCode(200)
  preview(@CurrentFactory() access: FactoryAccess, @Body() body: unknown) {
    return { tenantId: access.tenantId, factoryId: access.factoryId, ...calculateProductionPreview(body) };
  }

  @Post('recap-preview')
  @HttpCode(200)
  recap(@CurrentFactory() access: FactoryAccess, @Body() body: unknown) {
    return { tenantId: access.tenantId, factoryId: access.factoryId, ...calculateProductionRecapPreview(body) };
  }
}
