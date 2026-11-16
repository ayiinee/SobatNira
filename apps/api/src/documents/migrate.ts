import { Database } from './database';

const db = new Database();
void db.migrate().then(() => console.log('Migrasi SobatNira selesai')).catch(() => {
  console.error('Migrasi SobatNira gagal. Periksa konfigurasi dan log database.');
  process.exitCode = 1;
}).finally(() => db.onModuleDestroy());
