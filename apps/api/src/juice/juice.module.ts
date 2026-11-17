import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { JuiceController } from './juice.controller';
import { JuiceRepository } from './juice.repository';
import { ClosureCheckService } from './closure-check.service';
import { LotClosureController } from './lot-closure.controller';
import { LotClosureService } from './lot-closure.service';

@Module({
  imports: [DatabaseModule],
  controllers: [JuiceController, LotClosureController],
  providers: [JuiceRepository, ClosureCheckService, LotClosureService],
  exports: [JuiceRepository, ClosureCheckService],
})
export class JuiceModule {}
