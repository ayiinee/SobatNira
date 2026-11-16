import { Controller, Get } from '@nestjs/common';
import { AccessRepository } from './access.repository';
import { CurrentUser, IdentityOnly } from './auth.decorators';
import { AuthUser } from './auth.types';

@Controller('auth')
export class AuthController {
  constructor(private readonly access: AccessRepository) {}

  @Get('me')
  @IdentityOnly()
  async me(@CurrentUser() user: AuthUser) {
    return { user, access: await this.access.listAccess(user.id) };
  }
}
