import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { JuiceStockController, MillingController, MillingSummaryController } from './milling.controller';
import { MillingRepository } from './milling.repository';
import { MillingService } from './milling.service';

@Module({ imports: [DatabaseModule], controllers: [MillingController, JuiceStockController, MillingSummaryController], providers: [MillingRepository, MillingService] })
export class MillingModule {}
