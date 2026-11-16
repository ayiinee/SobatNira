import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableCors({
    origin: (process.env.MOBILE_WEB_ORIGINS ?? 'http://127.0.0.1:8080,http://localhost:8080').split(',').map((origin) => origin.trim()),
  });
  app.enableShutdownHooks();
  await app.listen(Number(process.env.API_PORT ?? 3000), process.env.API_HOST ?? '127.0.0.1');
}

void bootstrap();
