import { Module } from '@nestjs/common';
import { ProductionMastersController } from './production-masters.controller';
import { ProductionMastersService } from './production-masters.service';

@Module({ controllers: [ProductionMastersController], providers: [ProductionMastersService] })
export class ProductionMastersModule {}
