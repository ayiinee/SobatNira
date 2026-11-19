import { Batches, BatchesController } from './batches';
import { JuiceRepository } from '../juice/juice.repository';
import { Module } from '@nestjs/common';
import { CaneTypesController } from '../cane-types/cane-types.controller';
import { CaneTypesRepository } from '../cane-types/cane-types.repository';
import { DatabaseModule } from '../database/database.module';
import { LotsController } from '../lots/lots.controller';
import { LotsRepository } from '../lots/lots.repository';
import { SuppliersController } from '../suppliers/suppliers.controller';
import { SuppliersRepository } from '../suppliers/suppliers.repository';
import { ProductionHistoryRepository } from './production.repository';
import { CalculationController } from './calculation.controller';

@Module({
  imports: [DatabaseModule],
  controllers: [SuppliersController, LotsController, CaneTypesController, CalculationController, BatchesController],
  providers: [SuppliersRepository, LotsRepository, CaneTypesRepository, ProductionHistoryRepository, Batches, JuiceRepository],
})
export class ProductionModule {}
