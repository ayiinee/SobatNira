import { Controller, DynamicModule, Get, Inject, Module, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { Public } from './auth/auth.decorators';
import { AuthModule } from './auth/auth.module';
import { BACKEND_CONFIG, BackendConfig, ConfigOptions, loadConfiguration } from './config/backend.config';
import { BackendConfigModule } from './config/config.module';
import { ProductionModule } from './production/production.module';
import { BatchesModule } from './batches/batches.module';
import { ProductionMastersModule } from './production-masters/production-masters.module';
import { EconomicsModule } from './economics/economics.module';
import { ReportingModule } from './reporting/reporting.module';
import { DocumentsModule } from './documents/documents.module';
import { OcrDocumentsModule } from './documents/ocr-documents.module';
import { MillingModule } from './milling/milling.module';
import { JuiceModule } from './juice/juice.module';

let configuredBackendConfig: BackendConfig | undefined;

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

@Module({
  // Keep direct NestFactory.create(AppModule) useful for local fixture tests.
  imports: [
    { module: BackendConfigModule, providers: [{ provide: BACKEND_CONFIG, useFactory: () => configuredBackendConfig ?? loadConfiguration() }], exports: [BACKEND_CONFIG] } as DynamicModule,
    AuthModule, ProductionModule, DocumentsModule, OcrDocumentsModule, MillingModule, JuiceModule, BatchesModule, ProductionMastersModule, EconomicsModule, ReportingModule,
  ],
  controllers: [AppController],
})
export class AppModule {
  static register(options: ConfigOptions = {}): DynamicModule {
    configuredBackendConfig = loadConfiguration(options);
    return {
      module: AppModule,
      imports: [
        BackendConfigModule.register(options),
        AuthModule,
        ProductionModule,
        DocumentsModule,
        OcrDocumentsModule,
        MillingModule,
        JuiceModule,
        BatchesModule,
        ProductionMastersModule,
        EconomicsModule,
        ReportingModule,
      ],
      controllers: [AppController],
    };
  }
}
