import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { JuiceController } from './juice.controller';
import { JuiceRepository } from './juice.repository';

@Module({ imports: [DatabaseModule], controllers: [JuiceController], providers: [JuiceRepository] })
export class JuiceModule {}
