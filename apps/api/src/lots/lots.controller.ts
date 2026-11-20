import { BadRequestException, Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { parseStockQuery } from '../documents/intake.dto';
import { found, object, parseLotInput, parseLotQuery, parseLotCountsQuery, parseLotSuggestionsQuery, parsePage, uuid } from '../production/production.dto';
import { ProductionHistoryRepository } from '../production/production.repository';
import { LotsRepository } from './lots.repository';

@Controller('tenants/:tenantId/factories/:factoryId/lots')
@FactoryRoles('admin', 'owner')
export class LotsController {
  constructor(private readonly lots: LotsRepository, private readonly history: ProductionHistoryRepository) {}

  @Get()
  list(@CurrentFactory() access: FactoryAccess, @Query() query: unknown) {
    return this.lots.list(access, parseLotQuery(query));
  }

  @Get('counts')
  counts(@CurrentFactory() access: FactoryAccess, @Query() query: unknown) {
    return this.lots.counts(access, parseLotCountsQuery(query));
  }

  @Get('suggestions')
  suggestions(@CurrentFactory() access: FactoryAccess, @Query() query: unknown) {
    return this.lots.suggestions(access, parseLotSuggestionsQuery(query));
  }

  @Post()
  async create(@CurrentFactory() access: FactoryAccess, @Body() body: unknown) {
    const row = await this.lots.create(access, parseLotInput(body));
    if (!row) throw new BadRequestException('Pemasok tidak tersedia atau akses pabrik sudah berubah.');
    return row;
  }

  @Get(':lotId')
  async detail(@CurrentFactory() access: FactoryAccess, @Param('lotId') id: string, @Query() query: unknown) {
    const { synthetic } = parseStockQuery(object(query, ['synthetic']));
    return found(await this.lots.find(access, uuid(id, 'lotId'), synthetic));
  }

  @Patch(':lotId')
  async update(@CurrentFactory() access: FactoryAccess, @Param('lotId') id: string, @Body() body: unknown) {
    return found(await this.lots.update(access, uuid(id, 'lotId'), parseLotInput(body, true)));
  }

  @Get(':lotId/history')
  async events(@CurrentFactory() access: FactoryAccess, @Param('lotId') id: string, @Query() query: unknown) {
    id = uuid(id, 'lotId');
    const page = parsePage(query);
    found(await this.lots.find(access, id));
    return this.history.list(access, 'lot', id, page);
  }
}
