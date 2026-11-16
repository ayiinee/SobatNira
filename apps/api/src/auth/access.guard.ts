import { CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AccessRepository } from './access.repository';
import { ACCESS_POLICY, AccessPolicy } from './auth.decorators';
import { SecurityRequest, UUID_PATTERN } from './auth.types';
import { SupabaseAuthService } from './supabase-auth.service';

@Injectable()
export class AccessGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly auth: SupabaseAuthService,
    private readonly access: AccessRepository,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const policy = this.reflector.getAllAndOverride<AccessPolicy>(ACCESS_POLICY, [
      context.getHandler(), context.getClass(),
    ]);
    if (policy?.kind === 'public') return true;
    const request = context.switchToHttp().getRequest<SecurityRequest>();
    const authorization = request.headers.authorization;
    const match = typeof authorization === 'string' ? /^Bearer ([^\s,]+)$/i.exec(authorization) : null;
    if (!match) throw new UnauthorizedException('Gunakan Authorization: Bearer <access_token>.');
    request.authUser = await this.auth.verifyAccessToken(match[1]);
    if (policy?.kind === 'identity') return true;
    // Fail closed for new routes until their access policy is explicitly declared.
    if (policy?.kind !== 'factory' || policy.roles.length === 0) {
      throw new ForbiddenException('Kebijakan akses endpoint belum ditetapkan.');
    }
    const { tenantId, factoryId } = request.params;
    if (!tenantId || !factoryId || !UUID_PATTERN.test(tenantId) || !UUID_PATTERN.test(factoryId)) {
      throw new ForbiddenException('Akses tenant atau pabrik tidak diizinkan.');
    }
    const membership = await this.access.findFactoryAccess(request.authUser.id, tenantId, factoryId);
    if (!membership || !policy.roles.includes(membership.role)) {
      throw new ForbiddenException('Akses tenant, pabrik atau role tidak diizinkan.');
    }
    request.factoryAccess = membership;
    return true;
  }
}
