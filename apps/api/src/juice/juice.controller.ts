import { Body, Controller, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { uuid } from '../production/production.dto';
import { parseAvailability, parseReservation } from './juice.dto';
import { JuiceRepository } from './juice.repository';

@Controller('tenants/:tenantId/factories/:factoryId/lots/:lotId/juice')
@FactoryRoles('admin', 'owner')
export class JuiceController {
  constructor(private readonly juice: JuiceRepository) {}

  @Get('availability')
  availability(@CurrentFactory() access: FactoryAccess, @Param('lotId') lotId: string, @Query() query: unknown) {
    return this.juice.availability(access, uuid(lotId, 'lotId'), parseAvailability(query));
  }

  @Post('reservations')
  reserve(@CurrentFactory() access: FactoryAccess, @Param('lotId') lotId: string, @Body() body: unknown) {
    return this.juice.reserve(access, uuid(lotId, 'lotId'), parseReservation(body));
  }

  @Post('reservations/:requestId/consume')
  @HttpCode(200)
  consume(@CurrentFactory() access: FactoryAccess, @Param('lotId') lotId: string, @Param('requestId') requestId: string) {
    return this.juice.finalize(access, uuid(lotId, 'lotId'), uuid(requestId, 'requestId'), 'consumed');
  }

  @Post('reservations/:requestId/release')
  @HttpCode(200)
  release(@CurrentFactory() access: FactoryAccess, @Param('lotId') lotId: string, @Param('requestId') requestId: string) {
    return this.juice.finalize(access, uuid(lotId, 'lotId'), uuid(requestId, 'requestId'), 'released');
  }
}
