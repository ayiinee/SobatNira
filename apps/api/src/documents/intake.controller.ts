import { Body, Controller, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { found, parsePage, uuid } from '../production/production.dto';
import { parseDocumentQuery, parseDraftUpdate, parseRevisionAction, parseStockQuery, parseSyntheticRequest } from './intake.dto';
import { IntakeRepository } from './intake.repository';
import { IntakeService } from './intake.service';

@Controller('tenants/:tenantId/factories/:factoryId/intake-documents')
@FactoryRoles('admin', 'owner')
export class IntakeController {
  constructor(private readonly service: IntakeService, private readonly repository: IntakeRepository) {}

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
    return this.service.update(access, uuid(id, 'documentId'), parseDraftUpdate(body));
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
export class SugarcaneStockController {
  constructor(private readonly repository: IntakeRepository) {}

  @Get('sugarcane')
  balance(@CurrentFactory() access: FactoryAccess, @Query() query: unknown) {
    const parsed = parseStockQuery(query);
    return this.repository.balance(access, parsed.synthetic, parsed.lotId);
  }
}
