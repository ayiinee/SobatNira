import { Body, Controller, ForbiddenException, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { found, parsePage, parseSupplierInput, parseSupplierQuery, uuid } from '../production/production.dto';
import { ProductionHistoryRepository } from '../production/production.repository';
import { SuppliersRepository } from './suppliers.repository';

@Controller('tenants/:tenantId/factories/:factoryId/suppliers')
@FactoryRoles('admin', 'owner')
export class SuppliersController {
  constructor(private readonly suppliers: SuppliersRepository, private readonly history: ProductionHistoryRepository) {}

  @Get()
  list(@CurrentFactory() access: FactoryAccess, @Query() query: unknown) {
    return this.suppliers.list(access, parseSupplierQuery(query));
  }

  @Post()
  async create(@CurrentFactory() access: FactoryAccess, @Body() body: unknown) {
    const row = await this.suppliers.create(access, parseSupplierInput(body));
    if (!row) throw new ForbiddenException('Akses pabrik tidak lagi tersedia.');
    return row;
  }

  @Get(':supplierId')
  async detail(@CurrentFactory() access: FactoryAccess, @Param('supplierId') id: string) {
    return found(await this.suppliers.find(access, uuid(id, 'supplierId')));
  }

  @Patch(':supplierId')
  async update(@CurrentFactory() access: FactoryAccess, @Param('supplierId') id: string, @Body() body: unknown) {
    return found(await this.suppliers.update(access, uuid(id, 'supplierId'), parseSupplierInput(body, true)));
  }

  @Get(':supplierId/history')
  async events(@CurrentFactory() access: FactoryAccess, @Param('supplierId') id: string, @Query() query: unknown) {
    id = uuid(id, 'supplierId');
    const page = parsePage(query);
    found(await this.suppliers.find(access, id));
    return this.history.list(access, 'supplier', id, page);
  }
}
