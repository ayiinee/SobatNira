import { createParamDecorator, ExecutionContext, ForbiddenException, SetMetadata, UnauthorizedException } from '@nestjs/common';
import { FactoryRole, SecurityRequest } from './auth.types';

export const ACCESS_POLICY = Symbol('ACCESS_POLICY');
export type AccessPolicy =
  | { kind: 'public' }
  | { kind: 'identity' }
  | { kind: 'factory'; roles: readonly FactoryRole[] };

export const Public = () => SetMetadata(ACCESS_POLICY, { kind: 'public' } satisfies AccessPolicy);
export const IdentityOnly = () => SetMetadata(ACCESS_POLICY, { kind: 'identity' } satisfies AccessPolicy);
export const FactoryRoles = (...roles: FactoryRole[]) =>
  SetMetadata(ACCESS_POLICY, { kind: 'factory', roles } satisfies AccessPolicy);

export const CurrentUser = createParamDecorator((_data: unknown, context: ExecutionContext) => {
  const user = context.switchToHttp().getRequest<SecurityRequest>().authUser;
  if (!user) throw new UnauthorizedException('Autentikasi diperlukan.');
  return user;
});

export const CurrentFactory = createParamDecorator((_data: unknown, context: ExecutionContext) => {
  const access = context.switchToHttp().getRequest<SecurityRequest>().factoryAccess;
  if (!access) throw new ForbiddenException('Akses pabrik diperlukan.');
  return access;
});
