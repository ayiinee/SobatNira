import { Inject, Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { BACKEND_CONFIG, BackendConfig } from '../config/backend.config';
import { AuthUser, UUID_PATTERN } from './auth.types';

@Injectable()
export class SupabaseAuthService {
  constructor(@Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  async verifyAccessToken(token: string): Promise<AuthUser> {
    const supabase = this.config.supabase;
    if (!supabase) throw new ServiceUnavailableException('Autentikasi belum dikonfigurasi.');
    try {
      // Supabase Auth validates the user token. Never trust a decoded JWT or client metadata.
      const response = await fetch(new URL('/auth/v1/user', supabase.url), {
        headers: { apikey: supabase.publishableKey, Authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(this.config.timeoutMs), redirect: 'error',
      });
      if (!response.ok) {
        await response.body?.cancel();
        if ([400, 401, 403].includes(response.status)) {
          throw new UnauthorizedException('Access token tidak valid atau kedaluwarsa.');
        }
        throw new ServiceUnavailableException('Layanan autentikasi belum tersedia.');
      }
      const user = await response.json() as Record<string, unknown> | null;
      if (!user || typeof user.id !== 'string' || !UUID_PATTERN.test(user.id) || user.aud !== 'authenticated') {
        throw new ServiceUnavailableException('Respons autentikasi tidak sesuai kontrak.');
      }
      return { id: user.id.toLowerCase(), ...(typeof user.email === 'string' ? { email: user.email } : {}) };
    } catch (error) {
      if (error instanceof UnauthorizedException || error instanceof ServiceUnavailableException) throw error;
      throw new ServiceUnavailableException('Layanan autentikasi belum tersedia.');
    }
  }
}
