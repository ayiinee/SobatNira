import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { DatabaseModule } from '../database/database.module';
import { AccessGuard } from './access.guard';
import { AccessRepository } from './access.repository';
import { AuthController } from './auth.controller';
import { FactoryAccessController } from './factory-access.controller';
import { SupabaseAuthService } from './supabase-auth.service';

@Module({
  imports: [DatabaseModule],
  controllers: [AuthController, FactoryAccessController],
  providers: [
    SupabaseAuthService, AccessRepository,
    { provide: APP_GUARD, useClass: AccessGuard },
  ],
  exports: [AccessRepository],
})
export class AuthModule {}
