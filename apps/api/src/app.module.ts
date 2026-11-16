import { Controller, DynamicModule, Get, Inject, Module, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { Public } from './auth/auth.decorators';
import { AuthModule } from './auth/auth.module';
import { BACKEND_CONFIG, BackendConfig, ConfigOptions } from './config/backend.config';
import { BackendConfigModule } from './config/config.module';
import { ProductionModule } from './production/production.module';
import { DocumentsModule } from './documents/documents.module';
import { OcrDocumentsModule } from './documents/ocr-documents.module';
import { MillingModule } from './milling/milling.module';

@Controller()
class AppController {
  constructor(@Inject(BACKEND_CONFIG) private readonly config: BackendConfig) {}

  @Get('health')
  @Public()
  health() {
    return { status: 'ok', service: 'sobatnira-api' };
  }

  @Get('demo/draft')
  @Public()
  async draft() {
    if (this.config.environment === 'production') throw new NotFoundException();
    const aiUrl = this.config.aiBaseUrl;
    try {
      const response = await fetch(new URL('/demo/draft', aiUrl), {
        signal: AbortSignal.timeout(this.config.aiTimeoutMs),
        redirect: 'error',
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new Error('AI service request failed');
      }
      return await response.json();
    } catch {
      throw new ServiceUnavailableException('Layanan AI lokal belum tersedia');
    }
  }
}

@Module({})
export class AppModule {
  static register(options: ConfigOptions = {}): DynamicModule {
    return {
      module: AppModule,
      imports: [BackendConfigModule.register(options), AuthModule, ProductionModule, DocumentsModule, OcrDocumentsModule, MillingModule],
      controllers: [AppController],
    };
  }
}
