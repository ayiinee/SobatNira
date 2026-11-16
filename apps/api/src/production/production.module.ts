import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { LotsController } from '../lots/lots.controller';
import { LotsRepository } from '../lots/lots.repository';
import { SuppliersController } from '../suppliers/suppliers.controller';
import { SuppliersRepository } from '../suppliers/suppliers.repository';
import { ProductionHistoryRepository } from './production.repository';

@Module({
  imports: [DatabaseModule],
  controllers: [SuppliersController, LotsController],
  providers: [SuppliersRepository, LotsRepository, ProductionHistoryRepository],
})
export class ProductionModule {}
