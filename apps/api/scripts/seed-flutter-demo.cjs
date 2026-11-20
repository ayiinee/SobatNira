// Import only to the existing SobatNira Uji tenant. No passwords or auth writes.
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { Client } = require('pg');
const { createApplication } = require('../dist/application');
const { loadConfiguration } = require('../dist/config/backend.config');
const { postgresClientOptions } = require('../dist/database/postgres.config');
const { DatabaseService } = require('../dist/database/database.service');
const { IntakeService } = require('../dist/documents/intake.service');
const { MillingService } = require('../dist/milling/milling.service');
const { Batches } = require('../dist/production/batches');
const { JuiceRepository } = require('../dist/juice/juice.repository');
const { LotClosureService } = require('../dist/juice/lot-closure.service');
const { useTransactionFixture } = require('../test/integration/database-fixture.cjs');

const dataset = 'sobatnira-flutter-demo-v1';
const fixturePath = resolve(__dirname, '../../../.tmp/mobile/flutter-demo-fixture.json');
const caneTypes = { BL: 'Bululawang', PS862: 'PS 862', PS864: 'PS 864' };
const suppliers = {
  B: ['Pemasok Banyu', 'Pemasok Teratai', 'Pemasok Waringin', 'Pemasok Kendal', 'Pemasok Melati'],
  C: ['Pemasok Lereng', 'Pemasok Pucuk', 'Pemasok Sumber', 'Pemasok Rawa', 'Pemasok Randu', 'Pemasok Jati'],
};

class SeedError extends Error {}

function id(tenant, label) {
  const hex = createHash('sha256').update(`${dataset}:${tenant}:${label}`).digest('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

const total = (rows, value) => rows.reduce((sum, row) => sum + value(row), 0);
const revenue = (batches) => total(batches, batch => batch.gradeKg * batch.priceRupiah);

function makeVariant(letter, count, source) {
  const factory = letter === 'B' ? 1 : 2;
  return Array.from({ length: count }, (_, index) => {
    const base = source[index % source.length];
    const variety = index + factory;
    const closed = index % 2 === 0 || index === count - 1;
    const batches = Array.from({ length: 2 + variety % 6 }, (_, number) => ({
      number: number + 1,
      wok: number % 3 + 1,
      time: `${String(10 + number).padStart(2, '0')}:${number % 2 === 0 ? '15' : '40'}`,
      juiceLiters: 76 + (index * 7 + number * 5 + factory * 9) % 39,
      physicalKg: 19 + (index * 2 + number + factory) % 18 + number % 3,
      grade: ['A', 'B', 'C'][(variety + number) % 3],
      gradeKg: 17 + (index * 2 + number + factory) % 18,
      priceRupiah: [20500, 17750, 14500][(variety + number) % 3] + factory * 750 + index % 3 * 250,
      approved: closed || number < 1 + variety % 6,
    }));
    return {
      code: `DEMO-${letter}-${String(index + 1).padStart(3, '0')}`,
      supplier: suppliers[letter][index % suppliers[letter].length],
      date: new Date(Date.UTC(2026, 8 + factory, 1 + index * (3 - factory))).toISOString().slice(0, 10),
      caneKg: base.caneKg + factory * 95 + index * 13,
      brix: ((158 + variety * 7 % 83) / 10).toString(),
      caneType: Object.keys(caneTypes)[variety % 3],
      closed,
      targetMarginRupiah: (index % 5 === 0 ? -1 : 1) * (95000 + index * 27000 + factory * 13500),
      fullSugarKg: total(batches, batch => batch.gradeKg),
      batches,
    };
  });
}

function validateLots(lots) {
  if (!Array.isArray(lots) || !lots.length || new Set(lots.map(lot => lot.code)).size !== lots.length) {
    throw new SeedError('Fixture kloter kosong atau kode kloter duplikat.');
  }
  for (const lot of lots) {
    if (!lot.batches.length || total(lot.batches, batch => batch.gradeKg) !== lot.fullSugarKg ||
        revenue(lot.batches) < lot.targetMarginRupiah ||
        lot.batches.some(batch => batch.gradeKg > batch.physicalKg || batch.juiceLiters > 115) ||
        (lot.closed && lot.batches.some(batch => !batch.approved))) {
      throw new SeedError(`Fixture tidak konsisten untuk ${lot.code}.`);
    }
  }
}

function costs(lot) {
  // The frontend fixture stores total cost only. Split it into test categories.
  const combined = revenue(lot.batches) - lot.targetMarginRupiah;
  const operational = Math.floor(combined * 0.16);
  const ingredient = Math.floor(combined * 0.05);
  const other = Math.floor(combined * 0.03);
  return {
    caneCostRupiah: String(combined - operational - ingredient - other),
    operationalCostRupiah: String(operational),
    ingredientCostRupiah: String(ingredient),
    otherCostRupiah: String(other),
  };
}

async function ensureFactory(client, actor, letter, readOnly) {
  if (letter === 'A') return actor.factory_id;
  const name = `Pabrik ${letter}`;
  const factory = id(actor.tenant_id, `factory:${letter}`);
  const { rows } = await client.query(`SELECT id FROM sobatnira.factories
    WHERE tenant_id = $1 AND lower(trim(name)) = lower($2)`, [actor.tenant_id, name]);
  if (rows.some(row => row.id !== factory)) throw new SeedError(`${name} sudah ada dengan identitas lain.`);
  if (!readOnly) {
    await client.query(`INSERT INTO sobatnira.factories (id, tenant_id, name)
      VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`, [factory, actor.tenant_id, name]);
    await client.query(`INSERT INTO sobatnira.factory_memberships (tenant_id, factory_id, user_id, role)
      VALUES ($1, $2, $3, 'admin') ON CONFLICT DO NOTHING`, [actor.tenant_id, factory, actor.user_id]);
  }
  const { rowCount } = await client.query(`SELECT 1 FROM sobatnira.factories f
    JOIN sobatnira.factory_memberships m ON m.tenant_id=f.tenant_id AND m.factory_id=f.id
    WHERE f.id=$1 AND f.tenant_id=$2 AND m.user_id=$3 AND f.name=$4 AND f.is_active AND m.is_active AND m.role='admin'`,
  [factory, actor.tenant_id, actor.user_id, name]);
  if (rowCount !== 1) throw new SeedError(`Akses admin aktif ${name} tidak tersedia.`);
  return factory;
}

async function seedLot(client, services, access, lot) {
  const lotId = id(access.tenantId, `lot:${access.factoryId}:${lot.code}`);
  const supplierId = id(access.tenantId, `supplier:${lot.supplier}`);
  const { rows } = await client.query(`SELECT id FROM sobatnira.lots
    WHERE tenant_id=$1 AND factory_id=$2 AND display_code=$3`, [access.tenantId, access.factoryId, lot.code]);
  if (rows.some(row => row.id !== lotId)) throw new SeedError(`Kode ${lot.code} sudah dipakai kloter lain.`);
  if (rows.length) return completeSeededLot(client, services, access, lotId, lot);
  await client.query(`INSERT INTO sobatnira.suppliers (id, tenant_id, name)
    VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`, [supplierId, access.tenantId, lot.supplier]);
  await client.query(`INSERT INTO sobatnira.lots (id, tenant_id, factory_id, supplier_id, display_code, received_at)
    VALUES ($1, $2, $3, $4, $5, $6)`, [lotId, access.tenantId, access.factoryId, supplierId, lot.code, `${lot.date}T06:00:00+07:00`]);

  const reason = 'Impor fixture Flutter sintetis';
  const { intake, milling, batches, juice, closure } = services;
  let receipt = await intake.createSynthetic(access, { lotId, requestId: id(access.tenantId, `intake:${lotId}`) });
  receipt = await intake.update(access, receipt.id, {
    expectedRevision: receipt.currentRevision, reason,
    changes: { netWeightKg: String(lot.caneKg), caneTypeCode: lot.caneType, brix: lot.brix },
  });
  await intake.confirmSynthetic(access, receipt.id, receipt.currentRevision);
  await intake.approve(access, receipt.id, receipt.currentRevision);

  let milled = await milling.createSynthetic(access, { lotId, requestId: id(access.tenantId, `milling:${lotId}`) });
  milled = await milling.update(access, milled.id, {
    expectedRevision: milled.currentRevision, reason,
    changes: {
      juiceProducedLiters: String(total(lot.batches, batch => batch.juiceLiters)),
      reportedBatches: lot.batches.map(batch => ({
        batchReference: `${lot.code}-B${batch.number}`, wokNumber: batch.wok,
        totalJuiceLiters: String(batch.juiceLiters), sourceJuiceLiters: String(batch.juiceLiters),
      })),
    },
  });
  await milling.confirmSynthetic(access, milled.id, milled.currentRevision);
  await milling.approve(access, milled.id, milled.currentRevision);
  await batches.costs(access, lotId, costs(lot));

  for (const batch of lot.batches) {
    const batchId = id(access.tenantId, `batch:${lotId}:${batch.number}`);
    const quantityMl = String(batch.juiceLiters * 1000);
    await batches.create(access, {
      id: batchId, lotId, code: `${lot.code}-B${batch.number}`, wokNumber: batch.wok,
      occurredAt: `${lot.date}T${batch.time}:00+07:00`, quantityMl,
      physicalWeightKg: String(batch.physicalKg), synthetic: true,
      grades: [{ code: batch.grade, weightKg: String(batch.gradeKg), pricePerKgRupiah: String(batch.priceRupiah) }],
    });
    await juice.reserve(access, lotId, {
      requestId: id(access.tenantId, `reservation:${batchId}`), batchId, originLotId: lotId, quantityMl, synthetic: true,
    });
    if (batch.approved) await batches.approve(access, batchId);
  }
  if (lot.closed) await closure.close(access, lotId, true, '');
  return true;
}

async function completeSeededLot(client, services, access, lotId, lot) {
  if (!lot.closed) return false;
  const { rows } = await client.query(`SELECT id, status FROM sobatnira.production_batches
    WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic`, [access.tenantId, access.factoryId, lotId]);
  const statuses = new Map(rows.map(row => [row.id, row.status]));
  const batchIds = lot.batches.map(batch => id(access.tenantId, `batch:${lotId}:${batch.number}`));
  if (rows.length !== batchIds.length || batchIds.some(batchId => !['draft', 'approved'].includes(statuses.get(batchId)))) {
    throw new SeedError(`Batch sintetis ${lot.code} tidak cocok dengan data seeder.`);
  }
  const current = await services.closure.status(access, lotId, true);
  if (current.status === 'closed') return false;
  for (const batchId of batchIds) {
    if (statuses.get(batchId) === 'draft') await services.batches.approve(access, batchId);
  }
  await services.closure.close(access, lotId, true, '');
  return true;
}

async function verifyFactory(client, batches, access, lots) {
  const { items } = await batches.productionReport(access, { synthetic: 'true' });
  const report = new Map(items.map(item => [item.lotId, item]));
  const lotIds = lots.map(lot => id(access.tenantId, `lot:${access.factoryId}:${lot.code}`));
  const { rows: stored } = await client.query(`SELECT b.id, b.status, b.is_synthetic, b.code, b.wok_number, b.occurred_at,
      b.quantity_ml::text, b.physical_weight_kg::text, g.code AS grade, g.weight_kg::text, g.price_per_kg_rupiah::text
    FROM sobatnira.production_batches b JOIN sobatnira.batch_grade_results g ON g.batch_id=b.id
    WHERE b.tenant_id=$1 AND b.factory_id=$2 AND b.lot_id=ANY($3::uuid[])`, [access.tenantId, access.factoryId, lotIds]);
  const storedById = new Map(stored.map(row => [row.id, row]));
  const { rows: closures } = await client.query(`SELECT lot_id FROM sobatnira.lot_closures
    WHERE tenant_id=$1 AND factory_id=$2 AND is_synthetic AND reopened_at IS NULL AND lot_id=ANY($3::uuid[])`,
  [access.tenantId, access.factoryId, lotIds]);
  const closed = new Set(closures.map(row => row.lot_id));
  for (const lot of lots) {
    const lotId = id(access.tenantId, `lot:${access.factoryId}:${lot.code}`);
    const item = report.get(lotId);
    const approved = lot.batches.filter(batch => batch.approved);
    const margin = lot.targetMarginRupiah - revenue(lot.batches) + revenue(approved);
    if (!item || item.code !== lot.code || item.supplier !== lot.supplier || closed.has(lotId) !== lot.closed ||
        Number(item.caneNetKg) !== lot.caneKg || item.batches.length !== approved.length ||
        Number(item.calculation?.finalSugarKg) !== total(approved, batch => batch.gradeKg) ||
        item.calculation?.productionMarginRupiah !== String(margin)) {
      throw new SeedError(`Hasil laporan tidak cocok untuk ${lot.code}.`);
    }
    for (const batch of lot.batches) {
      const row = storedById.get(id(access.tenantId, `batch:${lotId}:${batch.number}`));
      if (!row || !row.is_synthetic || row.status !== (batch.approved ? 'approved' : 'draft') ||
          row.code !== `${lot.code}-B${batch.number}` || row.wok_number !== batch.wok ||
          row.occurred_at.getTime() !== Date.parse(`${lot.date}T${batch.time}:00+07:00`) ||
          Number(row.quantity_ml) !== batch.juiceLiters * 1000 || Number(row.physical_weight_kg) !== batch.physicalKg ||
          row.grade !== batch.grade || Number(row.weight_kg) !== batch.gradeKg ||
          row.price_per_kg_rupiah !== String(batch.priceRupiah)) {
        throw new SeedError(`Batch ${lot.code}-B${batch.number} tidak cocok dengan fixture.`);
      }
    }
  }
  const batchCount = total(lots, lot => lot.batches.length);
  if (stored.length !== batchCount) throw new SeedError(`Jumlah batch tidak cocok untuk ${access.factoryName}.`);
  return {
    lots: lots.length,
    batches: stored.length,
    approved: stored.filter(row => row.status === 'approved').length,
    closed: closed.size,
    caneKg: total(lots, lot => lot.caneKg),
    approvedSugarKg: total(lots, lot => Number(report.get(id(access.tenantId, `lot:${access.factoryId}:${lot.code}`)).calculation.finalSugarKg)),
    approvedMarginRupiah: total(lots, lot => Number(report.get(id(access.tenantId, `lot:${access.factoryId}:${lot.code}`)).calculation.productionMarginRupiah)),
  };
}

async function servicesFor(client, env) {
  const app = await createApplication({ envFile: false, env });
  useTransactionFixture(app.get(DatabaseService), client);
  return { app, intake: app.get(IntakeService), milling: app.get(MillingService), batches: app.get(Batches),
    juice: app.get(JuiceRepository), closure: app.get(LotClosureService) };
}

async function writeLots(config, env, factories) {
  const jobs = factories.flatMap(({ access, lots }) => lots.map(lot => ({ access, lot })));
  let index = 0;
  let aborted = false;
  async function worker() {
    const client = new Client(postgresClientOptions(config));
    let services;
    try {
      await client.connect();
      services = await servicesFor(client, env);
      while (!aborted && index < jobs.length) {
        const { access, lot } = jobs[index++];
        await client.query('BEGIN');
        await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`${dataset}:${access.factoryId}:${lot.code}`]);
        const changed = await seedLot(client, services, access, lot);
        if (changed) await verifyFactory(client, services.batches, access, [lot]);
        await client.query('COMMIT');
        if (changed) console.log(`${access.factoryName} · ${lot.code} tersimpan.`);
      }
    } catch (error) {
      aborted = true;
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      await services?.app.close();
      await client.end();
    }
  }
  // Wait for every active transaction to finish before reporting an error.
  const results = await Promise.allSettled(Array.from({ length: 5 }, worker));
  const failure = results.find(result => result.status === 'rejected');
  if (failure) throw failure.reason;
}

async function seed() {
  const commit = process.argv.includes('--commit');
  const verify = process.argv.includes('--verify');
  const sample = process.argv.includes('--sample');
  if ((commit && verify) || (sample && (commit || verify))) {
    throw new SeedError('Gunakan salah satu dari --commit, --verify, atau --sample.');
  }
  const tenant = process.env.SOBATNIRA_SEED_TENANT_ID;
  const email = process.env.SOBATNIRA_SEED_ACTOR_EMAIL?.trim().toLowerCase();
  if (!tenant || !email) throw new SeedError('Isi SOBATNIRA_SEED_TENANT_ID dan SOBATNIRA_SEED_ACTOR_EMAIL.');
  const source = JSON.parse(readFileSync(fixturePath, 'utf8'));
  validateLots(source);
  const sets = { A: source, B: makeVariant('B', 18, source), C: makeVariant('C', 23, source) };
  Object.values(sets).forEach(validateLots);

  // Local application services run development fixtures; Railway runtime is unchanged.
  const env = { ...process.env, NODE_ENV: 'development', BATCH_API_BASE_URL: '' };
  const config = loadConfiguration({ envFile: false, env });
  if (!config.postgres || !config.supabase) throw new SeedError('Konfigurasi Railway untuk Supabase belum tersedia.');
  const projectHost = new URL(config.supabase.url).hostname;
  const database = new URL(config.postgres.url);
  if (!projectHost.endsWith('.supabase.co') || !(database.hostname === `db.${projectHost}` ||
      (database.hostname.endsWith('.pooler.supabase.com') && database.username.endsWith(`.${projectHost.split('.')[0]}`)))) {
    throw new SeedError('DATABASE_URL dan SUPABASE_URL menunjuk proyek berbeda.');
  }

  const client = new Client(postgresClientOptions(config));
  let services;
  try {
    await client.connect();
    await client.query(verify ? 'BEGIN READ ONLY' : 'BEGIN');
    if (!verify) await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`${dataset}:${tenant}`]);
    const { rows } = await client.query(`SELECT fm.tenant_id, fm.factory_id, fm.user_id FROM sobatnira.factory_memberships fm
      JOIN auth.users u ON u.id=fm.user_id
      JOIN sobatnira.tenant_memberships tm ON tm.tenant_id=fm.tenant_id AND tm.user_id=fm.user_id
      JOIN sobatnira.factories f ON f.tenant_id=fm.tenant_id AND f.id=fm.factory_id
      JOIN sobatnira.tenants t ON t.id=fm.tenant_id
      WHERE t.id=$1 AND t.name='SobatNira Uji' AND t.is_active AND f.name='Pabrik A' AND f.is_active
        AND fm.role='admin' AND fm.is_active AND tm.is_active AND lower(u.email)=$2 AND u.email_confirmed_at IS NOT NULL`, [tenant, email]);
    if (rows.length !== 1) throw new SeedError('Akun admin dan Pabrik A pada SobatNira Uji tidak cocok.');
    const actor = rows[0];
    services = await servicesFor(client, env);
    if (!verify) {
      for (const [code, name] of Object.entries(caneTypes)) {
        await client.query(`INSERT INTO sobatnira.cane_types (tenant_id, code, name)
          VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`, [tenant, code, name]);
      }
    }
    const factories = [];
    for (const [letter, allLots] of Object.entries(sets)) {
      const lots = sample ? [allLots[0], allLots[2]] : allLots;
      const factoryId = await ensureFactory(client, actor, letter, verify);
      const access = { tenantId: tenant, factoryId, userId: actor.user_id, role: 'admin',
        tenantName: 'SobatNira Uji', factoryName: `Pabrik ${letter}` };
      if (!verify) {
        for (const name of new Set(lots.map(lot => lot.supplier))) {
          await client.query(`INSERT INTO sobatnira.suppliers (id, tenant_id, name)
            VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`, [id(tenant, `supplier:${name}`), tenant, name]);
        }
      }
      factories.push({ access, lots });
    }
    if (commit) {
      await client.query('COMMIT');
      await writeLots(config, env, factories);
      await client.query('BEGIN READ ONLY');
    }
    for (const { access, lots } of factories) {
      let changed = 0;
      if (!commit && !verify) {
        for (const lot of lots) if (await seedLot(client, services, access, lot)) changed++;
      }
      const verified = await verifyFactory(client, services.batches, access, lots);
      console.log(JSON.stringify({ factory: access.factoryName, ...(!commit && !verify && { changed }), ...verified }));
    }
    await client.query(commit ? 'COMMIT' : 'ROLLBACK');
    console.log(commit ? 'Data sintetis tersimpan.' : verify ? 'Verifikasi hanya baca selesai.' : 'Uji selesai. Semua perubahan di-rollback.');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    await services?.app.close();
    await client.end();
  }
}

seed().catch(error => {
  const code = /^[A-Z0-9_]{1,60}$/.test(error.code ?? '') ? ` (${error.code})` : '';
  console.error(error instanceof SeedError || error.getStatus ? error.message : `Seed dibatalkan${code}. Periksa koneksi, skema, dan fixture.`);
  process.exitCode = 1;
});
