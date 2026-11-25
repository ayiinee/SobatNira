import { BadRequestException, Body, Controller, Get, Param, Patch, Post, ServiceUnavailableException } from '@nestjs/common';
import { object, text, uuid } from '../production/production.dto';
import { AccessRepository } from './access.repository';
import { CurrentFactory, FactoryRoles } from './auth.decorators';
import { FactoryAccess } from './auth.types';
import { SupabaseAuthService } from './supabase-auth.service';

@Controller('tenants/:tenantId/factories/:factoryId')
export class FactoryAccessController {
  constructor(private readonly access: AccessRepository, private readonly auth: SupabaseAuthService) {}

  @Get()
  @FactoryRoles('admin', 'owner')
  factory(@CurrentFactory() access: FactoryAccess) {
    return this.access.factoryProfile(access);
  }

  @Patch('profile')
  @FactoryRoles('owner')
  updateProfile(@CurrentFactory() access: FactoryAccess, @Body() input: unknown) {
    return this.access.editFactoryProfile(access, input);
  }

  @Get('memberships')
  @FactoryRoles('owner')
  async memberships(@CurrentFactory() access: FactoryAccess) {
    return { memberships: await this.access.listFactoryMembers(access) };
  }

  @Post('memberships/admin')
  @FactoryRoles('owner')
  async inviteAdmin(@CurrentFactory() access: FactoryAccess, @Body() input: unknown) {
    const body = object(input, ['email']);
    const email = text(body.email, 'Email', 254).toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new BadRequestException('Email tidak valid.');
    const existing = await this.access.authUserIdForEmail(email);
    if (existing) return { ...await this.access.addFactoryAdmin(access, existing), inviteSent: false };
    if (process.env.FACTORY_ADMIN_INVITES_ENABLED !== 'true')
      throw new ServiceUnavailableException('Pendaftaran akun baru belum diaktifkan. Gunakan akun Auth yang sudah ada.');
    const userId = await this.auth.inviteByEmail(email);
    return { ...await this.access.addFactoryAdmin(access, userId), inviteSent: true };
  }

  @Patch('memberships/:userId')
  @FactoryRoles('owner')
  setAdminActive(@CurrentFactory() access: FactoryAccess, @Param('userId') userId: string, @Body() input: unknown) {
    const { isActive } = object(input, ['isActive']);
    if (typeof isActive !== 'boolean') throw new BadRequestException('Status admin tidak valid.');
    return this.access.setFactoryAdminActive(access, uuid(userId, 'userId'), isActive);
  }
}
