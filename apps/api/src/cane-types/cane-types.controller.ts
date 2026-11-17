import { Body, Controller, ForbiddenException, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { found, parseCatalogQuery, parsePage, uuid } from '../production/production.dto';
import { ProductionHistoryRepository } from '../production/production.repository';
import { parseCaneTypeCreate, parseCaneTypeUpdate } from './cane-types.dto';
import { CaneTypesRepository } from './cane-types.repository';

@Controller('tenants/:tenantId/factories/:factoryId/cane-types')
@FactoryRoles('admin', 'owner')
export class CaneTypesController {
  constructor(private readonly caneTypes: CaneTypesRepository, private readonly history: ProductionHistoryRepository) {}

  @Get()
  list(@CurrentFactory() access: FactoryAccess, @Query() query: unknown) {
    return this.caneTypes.list(access, parseCatalogQuery(query));
  }

  @Post()
  async create(@CurrentFactory() access: FactoryAccess, @Body() body: unknown) {
    const row = await this.caneTypes.create(access, parseCaneTypeCreate(body));
    if (!row) throw new ForbiddenException('Akses pabrik tidak lagi tersedia.');
    return row;
  }

  @Get(':caneTypeId')
  async detail(@CurrentFactory() access: FactoryAccess, @Param('caneTypeId') id: string) {
    return found(await this.caneTypes.find(access, uuid(id, 'caneTypeId')));
  }

  @Patch(':caneTypeId')
  async update(@CurrentFactory() access: FactoryAccess, @Param('caneTypeId') id: string, @Body() body: unknown) {
    return found(await this.caneTypes.update(access, uuid(id, 'caneTypeId'), parseCaneTypeUpdate(body)));
  }

  @Get(':caneTypeId/history')
  async events(@CurrentFactory() access: FactoryAccess, @Param('caneTypeId') id: string, @Query() query: unknown) {
    id = uuid(id, 'caneTypeId');
    const page = parsePage(query);
    found(await this.caneTypes.find(access, id));
    return this.history.list(access, 'cane_type', id, page);
  }
}
