import 'reflect-metadata';
import { LogLevel } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { BACKEND_CONFIG, BackendConfig, ConfigOptions } from './config/backend.config';

export async function createApplication(options: ConfigOptions = {}) {
  const app = await NestFactory.create(AppModule.register(options), { logger: false });
  const config = app.get<BackendConfig>(BACKEND_CONFIG);
  const levels: Record<BackendConfig['logLevel'], LogLevel[]> = {
    silent: [], error: ['error'], warn: ['error', 'warn'],
    info: ['error', 'warn', 'log'], debug: ['error', 'warn', 'log', 'debug', 'verbose'],
  };
  app.useLogger(levels[config.logLevel]);
  app.enableCors({ origin: config.corsOrigins });
  app.enableShutdownHooks();
  return app;
}
