import { Module } from '@nestjs/common';
import { BatchesController } from './batches.controller';
import { BatchesService } from './batches.service';
import { JuiceModule } from '../juice/juice.module';

@Module({ imports: [JuiceModule], controllers: [BatchesController], providers: [BatchesService], exports: [BatchesService] })
export class BatchesModule {}
