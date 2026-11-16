import { Controller, Get } from '@nestjs/common';
import { AccessRepository } from './access.repository';
import { CurrentFactory, FactoryRoles } from './auth.decorators';
import { FactoryAccess } from './auth.types';

@Controller('tenants/:tenantId/factories/:factoryId')
export class FactoryAccessController {
  constructor(private readonly access: AccessRepository) {}

  @Get()
  @FactoryRoles('admin', 'owner')
  factory(@CurrentFactory() access: FactoryAccess) {
    return { tenantId: access.tenantId, id: access.factoryId, name: access.factoryName, role: access.role };
  }

  @Get('memberships')
  @FactoryRoles('owner')
  async memberships(@CurrentFactory() access: FactoryAccess) {
    return { memberships: await this.access.listFactoryMembers(access) };
  }
}
