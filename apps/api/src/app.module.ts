import { Controller, Get, Module, ServiceUnavailableException } from '@nestjs/common';
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

@Module({ imports: [DocumentsModule], controllers: [AppController] })
export class AppModule {}
