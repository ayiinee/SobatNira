import { Module } from '@nestjs/common';
import { BatchesModule } from '../batches/batches.module';
import { EconomicsController } from './economics.controller';
import { EconomicsService } from './economics.service';

@Module({ imports: [BatchesModule], controllers: [EconomicsController], providers: [EconomicsService] })
export class EconomicsModule {}
