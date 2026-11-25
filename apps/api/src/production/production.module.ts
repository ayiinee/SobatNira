import { SugarInventory, SugarInventoryController } from './sugar-inventory';
import { Batches, BatchesController } from './batches';
import { CostCorrections, CostCorrectionsController } from './cost-corrections';
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
import { Capabilities, CapabilitiesController } from './capabilities';
import { OcrDocumentsModule } from '../documents/ocr-documents.module';
import { AuthModule } from '../auth/auth.module';
import { OwnerAgentController, OwnerAgentSessionController, OwnerAgentSessions } from './owner-agent';
import { ReportExports, ReportExportsController } from './report-exports';
import { ReportDelivery } from './report-delivery';
import { CatalogCache } from '../cache/catalog-cache';

@Module({
  imports: [DatabaseModule, AuthModule, OcrDocumentsModule],
  controllers: [SugarInventoryController, CostCorrectionsController, SuppliersController, LotsController, CaneTypesController, CalculationController, BatchesController,
    CapabilitiesController, OwnerAgentController, OwnerAgentSessionController, ReportExportsController],
  providers: [SugarInventory, CostCorrections, SuppliersRepository, LotsRepository, CaneTypesRepository, ProductionHistoryRepository, Batches, JuiceRepository,
    Capabilities, OwnerAgentSessions, ReportExports, ReportDelivery, CatalogCache],
})
export class ProductionModule {}
