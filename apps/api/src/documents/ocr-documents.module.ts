import { BadRequestException, Body, CanActivate, Controller, ExecutionContext, Get, Header, Headers,
  HttpCode, Injectable, Module, NotFoundException, Param, Patch, Post, Query, ServiceUnavailableException, StreamableFile,
  UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Public } from '../auth/auth.decorators';
import { MAX_IMAGE_BYTES, readInbound, requireServiceToken, requireUuid } from './contracts';
import { Database } from './database';
import { Intake } from './intake';
import { imageMime, MediaStorage } from './media';
import { DocumentProcessor } from './processing';
import { Review } from './review';
import { Notices } from './notices';
import { TruckIntake } from './truck-intake';

@Injectable()
class AdapterGuard implements CanActivate {
  canActivate(context: ExecutionContext) {
    requireServiceToken(context.switchToHttp().getRequest().headers['x-internal-service-token'], process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN);
    return true;
  }
}

// These routes use the adapter token instead of the factory access guard.
@Public()
@Controller('internal/v1/whatsapp')
@UseGuards(AdapterGuard)
class WhatsAppController {
  constructor(private readonly intake: Intake, private readonly notices: Notices, private readonly db: Database) {}

  @Get('ready')
  @Header('Cache-Control', 'private, no-store')
  async readiness() {
    if (process.env.DOCUMENT_WORKER_ENABLED !== 'true') throw new ServiceUnavailableException('Periksa DOCUMENT_WORKER_ENABLED');
    try { await this.db.assertMigrationsApplied(); }
    catch { throw new ServiceUnavailableException('Periksa DATABASE_URL dan jalankan db:migrate:ocr'); }
    return { status: 'ok', component: 'sobatnira-whatsapp-intake' };
  }

  @Post('notices/claim')
  @HttpCode(200)
  claimNotice() { return this.notices.claim(); }

  @Post('notices/:id/result')
  @HttpCode(200)
  finishNotice(@Param('id') id: string, @Body() body: Record<string, unknown>) {
    return this.notices.result(requireUuid(id), body);
  }

  @Post('inbound')
  @HttpCode(202)
  @UseInterceptors(FileInterceptor('media', { limits: { fileSize: MAX_IMAGE_BYTES, files: 1, fields: 1, fieldSize: 16 * 1024, parts: 3 } }))
  async photo(@Headers('idempotency-key') key: string, @Body('event') raw: string,
    @UploadedFile() file?: { buffer: Buffer; mimetype: string }) {
    if (!file || typeof raw !== 'string') throw new BadRequestException('Kirim satu foto dan metadata event');
    let event: unknown;
    try { event = JSON.parse(raw); }
    catch { throw new BadRequestException('Metadata event bukan JSON'); }
    const inbound = readInbound(event, 'IMAGE', key);
    const mime = imageMime(file.buffer, file.mimetype);
    if (inbound.media_mime_type && inbound.media_mime_type !== mime) throw new BadRequestException('Tipe media tidak cocok');
    return this.intake.photo(inbound, mime, file.buffer);
  }

  @Get('documents/:documentId/revisions/:revisionId')
  @Header('Cache-Control', 'private, no-store')
  status(@Param('documentId') id: string, @Param('revisionId') revision: string, @Headers('x-operator-phone') sender: string) {
    return this.intake.status(sender, requireUuid(id), requireUuid(revision));
  }

  @Get('quoted-context')
  @Header('Cache-Control', 'private, no-store')
  quotedContext(@Headers('x-operator-phone') phone: string, @Headers('x-chat-id') chat: string,
    @Headers('x-quoted-message-id') quote: string) {
    if (!/^\+[1-9][0-9]{7,14}$/.test(phone) || !chat || chat.length > 255 || !quote || quote.length > 255) {
      throw new BadRequestException('Rujukan percakapan tidak valid');
    }
    return this.intake.quotedContext(phone, chat, quote);
  }

  @Post('text-events')
  @HttpCode(200)
  reply(@Headers('idempotency-key') key: string, @Body() body: { event?: unknown; action?: Parameters<Intake['reply']>[1] }) {
    if (!body?.action) throw new BadRequestException('Aksi operator wajib');
    return this.intake.reply(readInbound(body.event, 'TEXT', key), body.action);
  }
}

// Media reads verify the OCR service token before querying storage.
@Public()
@Controller('internal/v1/ocr/media')
class OcrMediaController {
  constructor(private readonly db: Database, private readonly media: MediaStorage) {}

  @Get(':key')
  @Header('Cache-Control', 'private, no-store')
  @Header('X-Content-Type-Options', 'nosniff')
  async get(@Headers('x-internal-service-token') token: string, @Param('key') key: string) {
    requireServiceToken(token, process.env.AI_SERVICE_INTERNAL_TOKEN);
    if (!/^[a-f0-9]{64}$/.test(key)) throw new NotFoundException();
    const { rows: [asset] } = await this.db.query('SELECT mime_type FROM media_assets WHERE object_key=$1', [key]);
    if (!asset) throw new NotFoundException();
    return new StreamableFile(await this.media.read(key), { type: asset.mime_type });
  }
}

// Review validates the Supabase token and its own review membership.
@Public()
@Controller('api/v1/mobile')
class MobileReviewController {
  constructor(private readonly review: Review, private readonly media: MediaStorage) {}

  @Get('review-notifications')
  @Header('Cache-Control', 'private, no-store')
  async notifications(@Headers('authorization') token: string) {
    return this.review.unreadNotifications(await this.review.user(token));
  }

  @Patch('review-notifications/:id/read')
  async markRead(@Headers('authorization') token: string, @Param('id') id: string) {
    return this.review.markNotificationRead(await this.review.user(token), requireUuid(id));
  }

  @Get('review-tasks')
  @Header('Cache-Control', 'private, no-store')
  async list(@Headers('authorization') token: string, @Query('status') status = 'PENDING_VALIDATION',
    @Query('page') page = '1', @Query('page_size') limit = '20') {
    return this.review.list(await this.review.user(token), status, Number(page), Number(limit));
  }

  @Get('review-tasks/:id')
  @Header('Cache-Control', 'private, no-store')
  async detail(@Headers('authorization') token: string, @Param('id') id: string) {
    return this.review.detail(await this.review.user(token), requireUuid(id));
  }

  @Get('review-tasks/:id/intake-lots')
  @Header('Cache-Control', 'private, no-store')
  async intakeLots(@Headers('authorization') token: string, @Param('id') id: string, @Query() query: unknown) {
    return this.review.intakeLots(await this.review.user(token), requireUuid(id), query);
  }

  @Get('review-tasks/:id/assets/:asset')
  @Header('Cache-Control', 'private, no-store')
  @Header('X-Content-Type-Options', 'nosniff')
  async asset(@Headers('authorization') token: string, @Param('id') id: string, @Param('asset') asset: string) {
    const media = await this.review.asset(await this.review.user(token), requireUuid(id), requireUuid(asset));
    return new StreamableFile(await this.media.read(media.object_key), { type: media.mime_type, disposition: 'inline' });
  }

  @Patch('documents/:id/draft')
  async correct(@Headers('authorization') token: string, @Headers('idempotency-key') key: string,
    @Param('id') id: string, @Body() body: Record<string, unknown>) {
    return this.review.change(await this.review.user(token), requireUuid(id), 'CORRECT', key, body);
  }

  @Post('documents/:id/validate')
  @HttpCode(200)
  async validate(@Headers('authorization') token: string, @Headers('idempotency-key') key: string,
    @Param('id') id: string, @Body() body: Record<string, unknown>) {
    return this.review.change(await this.review.user(token), requireUuid(id), 'VALIDATE', key, body);
  }

  @Post('documents/:id/manual-draft')
  @HttpCode(200)
  async manualDraft(@Headers('authorization') token: string, @Headers('idempotency-key') key: string,
    @Param('id') id: string, @Body() body: Record<string, unknown>) {
    return this.review.change(await this.review.user(token), requireUuid(id), 'MANUAL_ENTRY', key, body);
  }

  @Post('documents/:id/return')
  @HttpCode(200)
  async return(@Headers('authorization') token: string, @Headers('idempotency-key') key: string,
    @Param('id') id: string, @Body() body: Record<string, unknown>) {
    return this.review.change(await this.review.user(token), requireUuid(id), 'RETURN', key, body);
  }
}

@Module({ controllers: [WhatsAppController, OcrMediaController, MobileReviewController],
  providers: [AdapterGuard, Database, DocumentProcessor, Intake, MediaStorage, Notices, Review, TruckIntake] })
export class OcrDocumentsModule {}
