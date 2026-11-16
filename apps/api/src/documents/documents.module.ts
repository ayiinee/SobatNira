import { BadRequestException, Body, CanActivate, Controller, ExecutionContext, Get, Header, Headers,
  HttpCode, Injectable, Module, NotFoundException, Param, Patch, Post, Query, StreamableFile,
  UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { MAX_IMAGE_BYTES, readInbound, requireServiceToken, requireUuid } from './contracts';
import { Database } from './database';
import { Intake } from './intake';
import { imageMime, MediaStorage } from './media';
import { DocumentProcessor } from './processing';
import { Review } from './review';

@Injectable()
class AdapterGuard implements CanActivate {
  canActivate(context: ExecutionContext) {
    requireServiceToken(context.switchToHttp().getRequest().headers['x-internal-service-token'], process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN);
    return true;
  }
}

@Controller('internal/v1/whatsapp')
@UseGuards(AdapterGuard)
class WhatsAppController {
  constructor(private readonly intake: Intake) {}

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
  status(@Param('documentId') id: string, @Param('revisionId') revision: string, @Headers('x-operator-phone') sender: string) {
    return this.intake.status(sender, requireUuid(id), requireUuid(revision));
  }

  @Post('text-events')
  @HttpCode(200)
  reply(@Headers('idempotency-key') key: string, @Body() body: { event?: unknown; action?: Parameters<Intake['reply']>[1] }) {
    if (!body?.action) throw new BadRequestException('Aksi operator wajib');
    return this.intake.reply(readInbound(body.event, 'TEXT', key), body.action);
  }
}

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

@Controller('api/v1/mobile')
class MobileReviewController {
  constructor(private readonly review: Review, private readonly media: MediaStorage) {}

  @Get('review-tasks')
  async list(@Headers('authorization') token: string, @Query('status') status = 'PENDING_VALIDATION',
    @Query('page') page = '1', @Query('page_size') limit = '20') {
    return this.review.list(await this.review.user(token), status, Number(page), Number(limit));
  }

  @Get('review-tasks/:id')
  async detail(@Headers('authorization') token: string, @Param('id') id: string) {
    return this.review.detail(await this.review.user(token), requireUuid(id));
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

  @Post('documents/:id/return')
  @HttpCode(200)
  async return(@Headers('authorization') token: string, @Headers('idempotency-key') key: string,
    @Param('id') id: string, @Body() body: Record<string, unknown>) {
    return this.review.change(await this.review.user(token), requireUuid(id), 'RETURN', key, body);
  }
}

@Module({ controllers: [WhatsAppController, OcrMediaController, MobileReviewController],
  providers: [AdapterGuard, Database, DocumentProcessor, Intake, MediaStorage, Review] })
export class DocumentsModule {}
