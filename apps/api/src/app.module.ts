import { Controller, Get, Module, ServiceUnavailableException } from '@nestjs/common';
import { BatchesModule } from './batches/batches.module';
import { ProductionMastersModule } from './production-masters/production-masters.module';
import { EconomicsModule } from './economics/economics.module';
import { ReportingModule } from './reporting/reporting.module';
import { DocumentsModule } from './documents/documents.module';

@Controller()
class AppController {
  @Get('health')
  health() {
    return { status: 'ok', service: 'sobatnira-api' };
  }

  @Get('demo/draft')
  async draft() {
    const aiUrl = process.env.AI_BASE_URL ?? 'http://127.0.0.1:8000';
    try {
      const response = await fetch(new URL('/demo/draft', aiUrl), {
        signal: AbortSignal.timeout(3_000),
      });
      if (!response.ok) {
        throw new Error('AI service request failed');
      }
      return await response.json();
    } catch {
      throw new ServiceUnavailableException('Layanan AI lokal belum tersedia');
    }
  }
}

@Module({ controllers: [AppController], imports: [BatchesModule, ProductionMastersModule, EconomicsModule, ReportingModule, DocumentsModule] })
export class AppModule {}
