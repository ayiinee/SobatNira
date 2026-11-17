import { Module } from '@nestjs/common';
import { CaneTypesController } from '../cane-types/cane-types.controller';
import { CaneTypesRepository } from '../cane-types/cane-types.repository';
import { DatabaseModule } from '../database/database.module';
import { LotsController } from '../lots/lots.controller';
import { LotsRepository } from '../lots/lots.repository';
import { SuppliersController } from '../suppliers/suppliers.controller';
import { SuppliersRepository } from '../suppliers/suppliers.repository';
import { ProductionHistoryRepository } from './production.repository';

@Module({
  imports: [DatabaseModule],
  controllers: [SuppliersController, LotsController, CaneTypesController],
  providers: [SuppliersRepository, LotsRepository, CaneTypesRepository, ProductionHistoryRepository],
})
export class ProductionModule {}
