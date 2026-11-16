import { DynamicModule, Global, Module } from '@nestjs/common';
import { BACKEND_CONFIG, ConfigOptions, loadConfiguration } from './backend.config';

@Global()
@Module({})
export class BackendConfigModule {
  static register(options: ConfigOptions = {}): DynamicModule {
    return {
      module: BackendConfigModule,
      providers: [{ provide: BACKEND_CONFIG, useValue: loadConfiguration(options) }],
      exports: [BACKEND_CONFIG],
    };
  }
}
