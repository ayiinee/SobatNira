import { Body, Controller, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { parseDocumentQuery, parseRevisionAction, parseStockQuery, parseSyntheticRequest } from '../documents/intake.dto';
import { found, object, parsePage, uuid } from '../production/production.dto';
import { parseMillingUpdate } from './milling.dto';
import { MillingRepository } from './milling.repository';
import { MillingService } from './milling.service';

// Logical milling projection of the second, combined note; it is not a third physical note.
@Controller('tenants/:tenantId/factories/:factoryId/production-result-documents')
@FactoryRoles('admin', 'owner')
export class MillingController {
  constructor(private readonly service: MillingService, private readonly repository: MillingRepository) {}
  @Post('synthetic')
  create(@CurrentFactory() access: FactoryAccess, @Body() body: unknown) {
    return this.service.createSynthetic(access, parseSyntheticRequest(body));
  }
  @Get()
  list(@CurrentFactory() access: FactoryAccess, @Query() query: unknown) {
    return this.repository.list(access, parseDocumentQuery(query));
  }
  @Get(':documentId')
  async detail(@CurrentFactory() access: FactoryAccess, @Param('documentId') id: string) {
    return found(await this.repository.find(access, uuid(id, 'documentId')));
  }
  @Patch(':documentId/draft')
  update(@CurrentFactory() access: FactoryAccess, @Param('documentId') id: string, @Body() body: unknown) {
    return this.service.update(access, uuid(id, 'documentId'), parseMillingUpdate(body));
  }
  @Post(':documentId/confirm-synthetic')
  @HttpCode(200)
  confirm(@CurrentFactory() access: FactoryAccess, @Param('documentId') id: string, @Body() body: unknown) {
    return this.service.confirmSynthetic(access, uuid(id, 'documentId'), parseRevisionAction(body));
  }
  @Post(':documentId/approve')
  @HttpCode(200)
  approve(@CurrentFactory() access: FactoryAccess, @Param('documentId') id: string, @Body() body: unknown) {
    return this.service.approve(access, uuid(id, 'documentId'), parseRevisionAction(body));
  }
  @Get(':documentId/revisions')
  async revisions(@CurrentFactory() access: FactoryAccess, @Param('documentId') id: string, @Query() query: unknown) {
    id = uuid(id, 'documentId');
    const page = parsePage(query);
    found(await this.repository.find(access, id));
    return this.repository.revisions(access, id, page);
  }
  @Get(':documentId/history')
  async history(@CurrentFactory() access: FactoryAccess, @Param('documentId') id: string, @Query() query: unknown) {
    id = uuid(id, 'documentId');
    const page = parsePage(query);
    found(await this.repository.find(access, id));
    return this.repository.history(access, id, page);
  }
}

@Controller('tenants/:tenantId/factories/:factoryId/stock')
@FactoryRoles('admin', 'owner')
export class JuiceStockController {
  constructor(private readonly repository: MillingRepository) {}
  @Get('juice')
  balance(@CurrentFactory() access: FactoryAccess, @Query() query: unknown) {
    const parsed = parseStockQuery(query);
    return this.repository.balance(access, parsed.synthetic, parsed.lotId);
  }
}

@Controller('tenants/:tenantId/factories/:factoryId/lots')
@FactoryRoles('admin', 'owner')
export class MillingSummaryController {
  constructor(private readonly repository: MillingRepository) {}
  @Get(':lotId/milling-summary')
  async summary(@CurrentFactory() access: FactoryAccess, @Param('lotId') lotId: string, @Query() query: unknown) {
    lotId = uuid(lotId, 'lotId');
    const parsed = parseStockQuery(object(query, ['synthetic']));
    return found(await this.repository.summary(access, lotId, parsed.synthetic));
  }
}
