import { Module } from '@nestjs/common';
import { BatchesModule } from '../batches/batches.module';
import { ReportingController } from './reporting.controller';
import { ReportingService } from './reporting.service';

@Module({ imports: [BatchesModule], controllers: [ReportingController], providers: [ReportingService] })
export class ReportingModule {}
