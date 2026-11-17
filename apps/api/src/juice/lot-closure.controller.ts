import { Body, Controller, Get, Headers, HttpCode, Param, Post, Query } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { uuid } from '../production/production.dto';
import { parseAvailability, parseClosure, parseClosureHistory, parseReopen } from './juice.dto';
import { LotClosureService } from './lot-closure.service';

@Controller('tenants/:tenantId/factories/:factoryId/lots/:lotId/closure')
@FactoryRoles('admin', 'owner')
export class LotClosureController {
  constructor(private readonly closure: LotClosureService) {}

  @Get()
  status(@CurrentFactory() access: FactoryAccess, @Param('lotId') lotId: string, @Query() query: unknown) {
    return this.closure.status(access, uuid(lotId, 'lotId'), parseAvailability(query));
  }

  @Get('history')
  history(@CurrentFactory() access: FactoryAccess, @Param('lotId') lotId: string, @Query() query: unknown) {
    return this.closure.history(access, uuid(lotId, 'lotId'), parseClosureHistory(query));
  }

  @Post()
  @HttpCode(200)
  close(@CurrentFactory() access: FactoryAccess, @Param('lotId') lotId: string,
    @Headers('authorization') authorization: string, @Body() body: unknown) {
    return this.closure.close(access, uuid(lotId, 'lotId'), parseClosure(body), authorization);
  }

  @Post('reopen')
  @HttpCode(200)
  reopen(@CurrentFactory() access: FactoryAccess, @Param('lotId') lotId: string, @Body() body: unknown) {
    return this.closure.reopen(access, uuid(lotId, 'lotId'), parseReopen(body));
  }
}
