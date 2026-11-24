import { Database } from './database';

const db = new Database();
const baseline = process.argv.includes('--baseline-reviewed');
if (baseline && process.env.OCR_MIGRATION_BASELINE_REVIEWED !== 'true')
  throw new Error('Baseline memerlukan review schema dan OCR_MIGRATION_BASELINE_REVIEWED=true.');
void db.migrate(baseline).then(() => console.log('Migrasi SobatNira selesai')).catch(() => {
  console.error('Migrasi SobatNira gagal. Periksa konfigurasi dan log database.');
  process.exitCode = 1;
}).finally(() => db.onModuleDestroy());
