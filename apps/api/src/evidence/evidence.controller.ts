import { Body, Controller, Get, Header, Param, Post, Query, StreamableFile, UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { IntakeRepository } from '../documents/intake.repository';
import { found, parsePage, uuid } from '../production/production.dto';
import { EvidenceRepository } from './evidence.repository';
import { EvidenceService } from './evidence.service';
import { EvidenceFile, MAX_EVIDENCE_BYTES } from './evidence.types';
import { parseEvidenceUpload } from './evidence.validation';
import { imageVariant } from './image-variant';

@Controller('tenants/:tenantId/factories/:factoryId/intake-documents/:documentId/evidence')
@FactoryRoles('admin', 'owner')
export class EvidenceController {
  constructor(private readonly service: EvidenceService, private readonly repository: EvidenceRepository,
    private readonly documents: IntakeRepository) {}

  @Post()
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_EVIDENCE_BYTES, files: 1, fields: 3, parts: 4, fieldSize: 2048, fieldNameSize: 50 } }))
  upload(@CurrentFactory() access: FactoryAccess, @Param('documentId') documentId: string,
    @Body() body: unknown, @UploadedFile() file?: EvidenceFile) {
    return this.service.upload(access, uuid(documentId, 'documentId'), parseEvidenceUpload(body), file);
  }

  @Get()
  async list(@CurrentFactory() access: FactoryAccess, @Param('documentId') documentId: string, @Query() query: unknown) {
    documentId = uuid(documentId, 'documentId');
    const page = parsePage(query);
    found(await this.documents.find(access, documentId));
    return this.repository.list(access, documentId, page);
  }

  @Get(':evidenceId/content')
  @Header('Cache-Control', 'private, no-store')
  @Header('X-Content-Type-Options', 'nosniff')
  async content(@CurrentFactory() access: FactoryAccess, @Param('documentId') documentId: string, @Param('evidenceId') id: string, @Query() query: unknown) {
    const result = await this.service.content(access, uuid(documentId, 'documentId'), uuid(id, 'evidenceId'), imageVariant(query));
    const extension = result.mime === 'image/jpeg' ? 'jpg' : result.mime.split('/')[1];
    return new StreamableFile(result.bytes, { type: result.mime, length: result.bytes.length,
      disposition: `inline; filename="receipt-${result.evidence.id}.${extension}"` });
  }
}
