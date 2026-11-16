import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { IntakeController, SugarcaneStockController } from './intake.controller';
import { IntakeRepository } from './intake.repository';
import { IntakeService } from './intake.service';
import { EvidenceController } from '../evidence/evidence.controller';
import { EvidenceRepository } from '../evidence/evidence.repository';
import { EvidenceService } from '../evidence/evidence.service';
import { R2EvidenceStorage } from '../evidence/r2-evidence.storage';

@Module({
  imports: [DatabaseModule],
  controllers: [IntakeController, SugarcaneStockController, EvidenceController],
  providers: [IntakeRepository, IntakeService, EvidenceRepository, EvidenceService, R2EvidenceStorage],
})
export class DocumentsModule {}
