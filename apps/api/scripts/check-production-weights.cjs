// Read-only inspection. Does not rewrite historical batches.
const { Client } = require('pg');
const { loadConfiguration } = require('../dist/config/backend.config');
const { postgresClientOptions } = require('../dist/database/postgres.config');
(async () => {
  const db = new Client(postgresClientOptions(loadConfiguration()));
  try {
    await db.connect();
    await db.query('BEGIN READ ONLY');
    const result = await db.query(`SELECT b.id,b.tenant_id,b.factory_id,b.lot_id,b.is_synthetic,
      b.physical_weight_kg::text,sum(g.weight_kg)::text AS grade_weight_kg
      FROM sobatnira.production_batches b LEFT JOIN sobatnira.batch_grade_results g ON g.batch_id=b.id
      WHERE b.status='approved' GROUP BY b.id
      HAVING b.physical_weight_kg IS DISTINCT FROM sum(g.weight_kg)`);
    console.log(JSON.stringify(result.rows));
    await db.query('ROLLBACK');
  } finally { await db.end(); }
})().catch(() => { console.error('Pemeriksaan berat gagal. Periksa konfigurasi database.'); process.exitCode = 1; });
