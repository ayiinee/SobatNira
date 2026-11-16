import { IncomingHttpHeaders } from 'node:http';

export type FactoryRole = 'admin' | 'owner';
export const UUID_PATTERN = /^[a-f\d]{8}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{12}$/i;

export interface AuthUser {
  id: string;
  email?: string;
}

export interface FactoryAccess {
  userId: string;
  tenantId: string;
  tenantName: string;
  factoryId: string;
  factoryName: string;
  role: FactoryRole;
}

export interface SecurityRequest {
  headers: IncomingHttpHeaders;
  params: Record<string, string | undefined>;
  authUser?: AuthUser;
  factoryAccess?: FactoryAccess;
}
