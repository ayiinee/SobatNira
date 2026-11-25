import { Inject, Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { BACKEND_CONFIG, BackendConfig, isLoopback } from '../config/backend.config';
import { AuthUser, UUID_PATTERN } from './auth.types';

@Injectable()
export class SupabaseAuthService {
  constructor(@Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  async inviteByEmail(email: string) {
    const supabase = this.config.supabase;
    const redirectTo = process.env.SUPABASE_ADMIN_INVITE_REDIRECT_URL;
    if (!supabase?.secretKey || !redirectTo)
      throw new ServiceUnavailableException('Undangan akun belum dikonfigurasi.');
    try {
      const redirect = new URL(redirectTo);
      if (redirect.username || redirect.password || redirect.hash || redirect.searchParams.get('acceptInvite') !== '1' ||
          (redirect.protocol !== 'https:' && !(redirect.protocol === 'http:' && isLoopback(redirect.hostname))))
        throw new Error('Invalid invitation redirect');
      const endpoint = new URL('/auth/v1/invite', supabase.url);
      endpoint.searchParams.set('redirect_to', redirect.href);
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          apikey: supabase.secretKey, 'content-type': 'application/json',
          ...(supabase.secretKey.startsWith('sb_secret_') ? {} : { Authorization: 'Bearer ' + supabase.secretKey }),
        },
        body: JSON.stringify({ email }),
        signal: AbortSignal.timeout(this.config.timeoutMs), redirect: 'error',
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new Error('Invitation provider did not accept request');
      }
      const user = await response.json() as { id?: unknown; email?: unknown };
      if (typeof user.id !== 'string' || !UUID_PATTERN.test(user.id) ||
          typeof user.email !== 'string' || user.email.toLowerCase() !== email)
        throw new Error('Unexpected invitation identity');
      return user.id.toLowerCase();
    } catch {
      throw new ServiceUnavailableException('Undangan belum terkonfirmasi. Periksa akun dan coba lagi.');
    }
  }

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
