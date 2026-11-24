const test=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {mobileClosureFixture}=require('./mobile-closure-fixture.cjs');
const {ClosureCheckService}=require('../../dist/juice/closure-check.service');
const {DatabaseService}=require('../../dist/database/database.service');
const {BACKEND_CONFIG}=require('../../dist/config/backend.config');
const {IntakeService}=require('../../dist/documents/intake.service');
const {MillingService}=require('../../dist/milling/milling.service');
const {Batches}=require('../../dist/production/batches');
const {JuiceRepository}=require('../../dist/juice/juice.repository');
test('batch approval freezes costs, consumes once, isolates scope and produces an exact report',async()=>{
 const f=await mobileClosureFixture({consume:false});
 try{
  const root=f.root+'/production',batch=randomUUID();
  const body={id:batch,lotId:f.ids.lot,code:'BATCH-TEST',wokNumber:1,occurredAt:'2026-11-16T03:00:00Z',quantityMl:'100000',physicalWeightKg:'30',grades:[{code:'A',weightKg:'30',pricePerKgRupiah:'20000'}]};
  assert.equal((await f.request(root+'/batches','POST',body)).status,201);
  assert.equal((await f.request(root+'/batches','POST',body)).body.id,batch);
  assert.equal((await f.request(root+'/batches','POST',{...body,quantityMl:'200000'})).status,409);
  assert.equal((await f.request(root+'/lots/'+f.ids.lot+'/costs','POST',{caneCostRupiah:'100000',operationalCostRupiah:'20000',ingredientCostRupiah:'5000',otherCostRupiah:'0'})).status,200);
  assert.equal((await f.request(root+'/batches/'+batch+'/approve','POST')).status,409);
  const requestId=randomUUID();
  const reservations=f.root+'/lots/'+f.ids.lot+'/juice/reservations';
  const reservation={requestId,batchId:batch,quantityMl:'100000'};
  assert.equal((await f.request(reservations,'POST',reservation)).status,201);
  assert.equal((await f.request(reservations+'/'+requestId+'/consume','POST')).status,409);
  assert.equal((await f.request(reservations+'/'+requestId+'/release','POST')).status,409);
  const detail=await f.request(root+'/batches/'+batch,'GET',undefined,'fixture-owner');
  assert.equal(detail.status,200);
  assert.equal(detail.body.costSaved,true);
  assert.equal(detail.body.remainingMl,'0');
  assert.equal(detail.body.grades[0].weightKg,'30');
  assert.equal(detail.body.finalSugarKg,'30');
  assert.equal(detail.body.exactValueRupiah,'600000');
  assert.equal((await f.request(root+'/batches/'+batch+'/approve','POST',undefined,'fixture-owner')).status,403);
  const approved=await f.request(root+'/batches/'+batch+'/approve','POST');assert.equal(approved.status,200,JSON.stringify(approved.body));
  assert.equal(approved.body.output_snapshot.productionMarginRupiah,'475000');
  const replay=await f.request(root+'/batches/'+batch+'/approve','POST');assert.equal(replay.body.id,approved.body.id);
  assert.equal((await f.request(f.root+'/lots/'+f.ids.lot+'/juice/availability')).body.onHandMl,'150000');
  const report=await f.request(root+'/profit-report');assert.equal(report.body.totalMarginRupiah,'475000');assert.equal(report.body.items.length,1);
  const recap=await f.request(root+'/recap?from=2026-11-16T00:00:00Z&before=2026-11-17T00:00:00Z','GET',undefined,'fixture-owner');
  assert.equal(recap.status,200);
  assert.equal(recap.body.totalSugarKg,'30');
  assert.equal(recap.body.totalMarginRupiah,report.body.totalMarginRupiah);
  assert.equal(recap.body.items[0].snapshotId,approved.body.id);
  assert.equal(recap.body.items[0].closed,false);
  assert.deepEqual(recap.body.items[0].batches[0].grades.map(({code,weightKg})=>({code,weightKg})),[{code:'A',weightKg:'30'}]);
  assert.equal((await f.request(root+'/batches?lotId='+f.ids.lot+'&synthetic=false')).body.items[0].id,batch);
  assert.equal((await f.request(root+'/batches?lotId='+f.ids.secondLot)).body.items.length,0);
  assert.equal((await f.request(root+'/profit-report?from=2026-12-01T00:00:00Z')).body.total,0);
  const production=await f.request(root+'/production-report');
  assert.equal(production.status,200,JSON.stringify(production.body));
  const scopedReport=await f.request(root+'/production-report?lotId='+f.ids.lot);
  assert.deepEqual(scopedReport.body,production.body);
  assert.deepEqual((await f.request(root+'/production-report?lotId='+f.ids.secondLot)).body.items,[]);
  assert.deepEqual((await f.request(f.siblingRoot+'/production/production-report?lotId='+f.ids.lot)).body.items,[]);
  assert.deepEqual((await f.request(root+'/production-report?synthetic=true&lotId='+f.ids.lot)).body.items,[]);
  assert.equal((await f.request(root+'/production-report?lotId=invalid')).status,400);
  assert.equal(production.body.totals.lotCount,1);
  assert.equal(production.body.totals.batchCount,1);
  assert.equal(production.body.totals.finalSugarKg,'30');
  assert.equal(production.body.totals.productionMarginRupiah,'475000');
  assert.equal(production.body.items[0].batches[0].grades[0].code,'A');
  assert.equal(production.body.grades[0].exactValueRupiah,'600000');
  const capabilityPath = f.root + '/capabilities/query';
  const range = {from:'2026-11-16T00:00:00Z',before:'2026-11-17T00:00:00Z'};
  const tool = (operation, args, token = 'fixture-owner', path = capabilityPath) =>
    f.request(path,'POST',{operation,arguments:args},token);
  assert.equal((await tool('get_production_summary',range,'fixture-admin')).status,403);
  assert.equal((await tool('get_production_summary',{...range,userId:f.ids.admin})).status,400);
  const snapshot = await tool('get_report_snapshot',range);
  assert.equal(snapshot.status,200,JSON.stringify(snapshot.body));
  assert.deepEqual(snapshot.body.result.totals,production.body.totals);
  assert.deepEqual(snapshot.body.result.grades,production.body.grades);
  assert.deepEqual(snapshot.body.result.items,production.body.items);
  assert.equal(snapshot.body.sources[0].snapshotId,approved.body.id);
  assert.equal(snapshot.body.scope.factoryId,f.ids.factory);
  assert.equal((await tool('get_lot_traceability',{lotId:f.ids.lot})).body.result.id,f.ids.lot);
  assert.equal((await tool('get_grade_distribution',range)).body.result.grades[0].code,'A');
  assert.equal((await tool('get_production_metrics',range)).body.result.lotMetrics[0].productionMarginRupiah,'475000');
  const comparison = await tool('compare_production_periods',{first:range,
    second:{from:range.before,before:'2026-11-18T00:00:00Z'}});
  assert.equal(comparison.status,200,JSON.stringify(comparison.body));
  assert.equal(comparison.body.result.first.totals.finalSugarKg,'30');
  assert.equal(comparison.body.result.second.totals.lotCount,0);
  const traces = await tool('get_batch_traceability',{batchId:batch});
  const material = await tool('get_material_contributions',{batchId:batch});
  assert.equal(traces.status,200,JSON.stringify(traces.body));
  assert.deepEqual(traces.body.result.items,material.body.result.items);
  assert.deepEqual(material.body.result.items,[{reservationId:requestId,batchId:batch,
    originLotId:f.ids.lot,stockLotId:f.ids.lot,quantityMl:'100000'}]);
  assert.equal((await tool('get_lot_contribution_summary',{lotId:f.ids.lot})).body.result.pageConsumedQuantityMl,'100000');
  assert.equal((await tool('get_batch_traceability',{batchId:batch},'fixture-owner',
    f.siblingRoot+'/capabilities/query')).status,403);
  assert.equal((await f.request(root+'/production-report?synthetic=true')).body.totals.lotCount,0);
  assert.equal((await f.request(root+'/production-report?before=2026-11-16T01:00:00Z')).body.totals.lotCount,0);
  assert.equal((await f.request(root+'/production-report?from=2026-11-16T01:00:00Z')).body.totals.lotCount,1);
  assert.equal((await f.request(f.siblingRoot+'/production/production-report')).body.totals.lotCount,0);

  assert.equal((await f.request(root+'/lots/'+f.ids.lot+'/costs','POST',{caneCostRupiah:'1',operationalCostRupiah:'0',ingredientCostRupiah:'0',otherCostRupiah:'0'})).status,409);
  const local=new ClosureCheckService({});
  const session=f.app.get(DatabaseService);
  const access={tenantId:f.ids.tenant,factoryId:f.ids.factory,userId:f.ids.admin};
  await local.requireClear(session,access,f.ids.lot,false,'Bearer fixture-admin');

  const correctionPath = root+'/batches/'+batch+'/corrections/';
  const correction = correctionPath+randomUUID();
  const reason = {reason:'Berat hasil diverifikasi ulang.'};
  assert.equal((await f.request(correction,'POST',reason,'fixture-owner')).status,403);
  assert.equal((await f.request(correction.replace(f.root,f.siblingRoot),'POST',reason)).status,404);
  assert.equal((await f.request(correction,'POST',reason)).body.version,1);
  assert.equal((await f.request(correction,'POST',reason)).body.version,1);
  assert.equal((await f.request(correctionPath+randomUUID(),'POST',reason)).status,409);
  await assert.rejects(()=>local.requireClear(session,access,f.ids.lot,false,'Bearer fixture-admin'),e=>e.getStatus()===409);
  const changes = {version:1,physicalWeightKg:'29',grades:[{code:'B',weightKg:'29',pricePerKgRupiah:'18000'}]};
  assert.equal((await f.request(correction,'PATCH',{...changes,quantityMl:'99000'})).status,400);
  assert.equal((await f.request(correction,'PATCH',changes)).body.version,2);
  assert.equal((await f.request(correction,'PATCH',changes)).body.version,2);
  assert.equal((await f.request(correction+'/approve','POST',{version:1})).status,409);
  assert.equal((await f.request(root+'/production-report')).body.totals.finalSugarKg,'30');
  assert.equal((await f.request(root+'/batches/'+batch)).body.correction.proposed_data.physicalWeightKg,'29');
  await f.client.query(`CREATE FUNCTION pg_temp.reject_correction_snapshot() RETURNS trigger LANGUAGE plpgsql
    AS $$ BEGIN RAISE EXCEPTION 'fixture snapshot failure'; END $$;
    CREATE TRIGGER fixture_snapshot_failure BEFORE INSERT ON sobatnira.production_calculation_snapshots
    FOR EACH ROW WHEN (NEW.correction_id IS NOT NULL) EXECUTE FUNCTION pg_temp.reject_correction_snapshot()`);
  assert.equal((await f.request(correction+'/approve','POST',{version:2})).status,500);
  const afterFailure = await f.request(root+'/batches/'+batch);
  assert.equal(afterFailure.body.physical_weight_kg,'30');
  assert.equal(afterFailure.body.grades[0].code,'A');
  assert.equal(afterFailure.body.correction.version,2);
  assert.equal((await f.request(root+'/production-report')).body.totals.finalSugarKg,'30');
  await f.client.query('DROP TRIGGER fixture_snapshot_failure ON sobatnira.production_calculation_snapshots');
  const corrected = await f.request(correction+'/approve','POST',{version:2});
  assert.equal(corrected.status,200,JSON.stringify(corrected.body));
  assert.equal((await f.request(correction+'/approve','POST',{version:2})).body.id,corrected.body.id);
  const correctedReport = await f.request(root+'/production-report');
  assert.equal(correctedReport.body.totals.finalSugarKg,'29');
  assert.equal(correctedReport.body.totals.productionMarginRupiah,'397000');
  assert.equal(correctedReport.body.totals.batchCount,1);
  assert.equal((await f.request(root+'/recap')).body.items[0].batches.length,1);
  assert.equal((await f.request(f.root+'/lots/'+f.ids.lot+'/juice/availability')).body.onHandMl,'150000');
  const snapshots=await f.client.query('SELECT correction_id FROM sobatnira.production_calculation_snapshots WHERE batch_id=$1',[batch]);
  assert.equal(snapshots.rows.length,2);
  assert.equal(snapshots.rows.filter(row=>row.correction_id===null).length,1);
  assert.equal((await f.request(root+'/batches/'+batch+'/approve','POST')).body.id,approved.body.id);
  const nextCorrection = correctionPath+randomUUID();
  assert.equal((await f.request(nextCorrection,'POST',reason)).body.before_data.physicalWeightKg,'29');
  assert.equal((await f.request(nextCorrection+'/discard','POST',{version:1})).body.status,'discarded');
  assert.equal((await f.request(root+'/batches/'+batch)).body.correction,null);
  await local.requireClear(session,access,f.ids.lot,false,'Bearer fixture-admin');

  assert.equal((await f.request(root+'/batches','POST',{...body,id:randomUUID(),code:'DRAFT-BLOCKS-CLOSURE'})).status,201);
  await assert.rejects(()=>local.requireClear(session,access,f.ids.lot,false,'Bearer fixture-admin'),e=>e.getStatus()===409);
  assert.equal((await f.request(root+'/production-report')).body.totals.batchCount,1);
  assert.equal((await f.request(f.siblingRoot+'/production/batches/'+batch+'/approve','POST')).status,404);
  assert.equal((await f.request(f.siblingRoot+'/production/recap')).body.total,0);
 }finally{await f.close();}
});

test('production admins can correct an existing sample batch without changing official reports or stock', async () => {
 const f = await mobileClosureFixture({ consume: false });
 try {
  const { tenant: tenantId, factory: factoryId, admin: userId, secondLot: lotId } = f.ids;
  const access = { tenantId, factoryId, userId, role: 'admin' };
  const intake = f.app.get(IntakeService);
  const milling = f.app.get(MillingService);
  const batches = f.app.get(Batches);
  const juice = f.app.get(JuiceRepository);
  const reason = 'Fixture koreksi data contoh';
  const receipt = await intake.createSynthetic(access, { lotId, requestId: randomUUID() });
  const input = await intake.update(access, receipt.id, {
   expectedRevision: receipt.currentRevision, reason, changes: { netWeightKg: '1250' },
  });
  await intake.confirmSynthetic(access, input.id, input.currentRevision);
  await intake.approve(access, input.id, input.currentRevision);
  const millingDraft = await milling.createSynthetic(access, { lotId, requestId: randomUUID() });
  const milled = await milling.update(access, millingDraft.id, {
   expectedRevision: millingDraft.currentRevision, reason,
   changes: { occurredAt: '2026-11-16T02:00:00Z', juiceProducedLiters: '100', reportedBatches: [] },
  });
  await milling.confirmSynthetic(access, milled.id, milled.currentRevision);
  await milling.approve(access, milled.id, milled.currentRevision);
  const batchId = randomUUID();
  await batches.create(access, {
   id: batchId, lotId, code: 'CORRECTION-SAMPLE', wokNumber: 1, occurredAt: '2026-11-16T03:00:00Z',
   quantityMl: '50000', physicalWeightKg: '28', synthetic: true,
   grades: [{ code: 'A', weightKg: '28', pricePerKgRupiah: '20000' }],
  });
  await batches.costs(access, lotId, {
   caneCostRupiah: '100000', operationalCostRupiah: '20000', ingredientCostRupiah: '5000', otherCostRupiah: '0',
  });
  await juice.reserve(access, lotId, { requestId: randomUUID(), batchId, quantityMl: '50000', synthetic: true });
  await batches.approve(access, batchId);

  f.app.get(BACKEND_CONFIG).environment = 'production';
  const root = f.root + '/production';
  const detail = root + '/batches/' + batchId;
  const correction = detail + '/corrections/' + randomUUID();
  const sampleReport = root + '/production-report?synthetic=true';
  const officialReport = root + '/production-report';
  const stock = f.root + '/lots/' + lotId + '/juice/availability?synthetic=true';
  const before = (await f.request(officialReport)).body.totals;
  const stockBefore = (await f.request(stock)).body;
  assert.equal(stockBefore.onHandMl, '50000');
  assert.equal((await f.request(detail)).body.canCorrect, true);
  assert.equal((await f.request(detail, 'GET', undefined, 'fixture-owner')).body.canCorrect, false);
  assert.equal((await f.request(correction, 'POST', { reason }, 'fixture-owner')).status, 403);
  assert.equal((await f.request(correction, 'POST', { reason })).status, 201);
  assert.equal((await f.request(correction, 'PATCH', {
   version: 1, physicalWeightKg: '29', grades: [{ code: 'A', weightKg: '29', pricePerKgRupiah: '20000' }],
  })).status, 200);
  assert.equal((await f.request(sampleReport)).body.totals.finalSugarKg, '28');
  assert.equal((await f.request(correction + '/approve', 'POST', { version: 2 })).status, 200);
  assert.equal((await f.request(sampleReport)).body.totals.finalSugarKg, '29');
  assert.deepEqual((await f.request(officialReport)).body.totals, before);
  assert.deepEqual((await f.request(stock)).body, stockBefore);
 } finally { await f.close(); }
});

test('cancelling a batch releases its reservation once and excludes it from official reports', async () => {
 const f = await mobileClosureFixture({ consume: false });
 try {
  const batches = f.root + '/production/batches';
  const lot = f.root + '/lots/' + f.ids.lot;
  const reservations = lot + '/juice/reservations';
  const id = randomUUID();
  const grade = {code:'A',weightKg:'30',pricePerKgRupiah:'20000'};
  const draft = {id,lotId:f.ids.lot,code:'CANCEL-TEST',wokNumber:1,occurredAt:'2026-11-16T03:00:00Z',
   quantityMl:'100000',physicalWeightKg:'30',grades:[grade]};
  assert.equal((await f.request(batches,'POST',{...draft,grades:[grade,{...grade,code:'B'}]})).status,400);
  assert.equal((await f.request(batches,'POST',draft)).status,201);
  const input = {requestId:id,batchId:id,quantityMl:'100000'};
  assert.equal((await f.request(reservations,'POST',{...input,quantityMl:'100001'})).status,409);
  assert.equal((await f.request(reservations,'POST',input)).status,201);
  assert.equal((await f.request(reservations,'POST',input)).body.requestId,id);
  assert.equal((await f.request(lot+'/juice/availability')).body.availableMl,'150000');
  assert.equal((await f.request(batches+'/'+id+'/cancel','POST',undefined,'fixture-owner')).status,403);
  assert.equal((await f.request(batches+'/'+id+'/cancel','POST')).body.status,'cancelled');
  assert.equal((await f.request(batches+'/'+id+'/cancel','POST')).body.status,'cancelled');
  assert.equal((await f.request(reservations,'POST',{...input,requestId:randomUUID()})).status,409);
  assert.equal((await f.request(batches+'/'+id+'/approve','POST')).status,409);
  assert.equal((await f.request(lot+'/juice/availability')).body.availableMl,'250000');
  assert.equal((await f.request(f.root+'/production/recap')).body.total,0);
  const events = await f.client.query(`SELECT action FROM sobatnira.production_batch_events WHERE batch_id=$1 ORDER BY id`,[id]);
  assert.deepEqual(events.rows.map(row=>row.action).sort(),['cancelled','created']);
 } finally { await f.close(); }
});

test('batch correction reopens the confirmed closure atomically and keeps the approved report', async () => {
 const f = await mobileClosureFixture();
 try {
  const closure = await f.request(f.root + '/lots/' + f.closureLotId + '/closure', 'POST', {synthetic:false});
  assert.equal(closure.status,200,JSON.stringify(closure.body));
  assert.equal(closure.body.status,'closed');
  const report = await f.request(f.root + '/production/recap');
  assert.equal(report.body.items[0].closed,true);
  const batchId = report.body.items[0].batches[0].id;
  const detail = f.root+'/production/batches/'+batchId;
  const correction = detail+'/corrections/'+randomUUID();
  const lot = f.root+'/lots/'+f.closureLotId;
  const reason = 'Uji kloter tertutup';
  assert.equal((await f.request(detail)).body.canCorrect,true);
  assert.equal((await f.request(detail)).body.lotClosureId,closure.body.closureId);
  assert.equal((await f.request(correction,'POST',{reason})).status,409);
  assert.equal((await f.request(correction,'POST',{reason,reopenClosureId:randomUUID()})).status,409);
  const consent = {reason,reopenClosureId:closure.body.closureId};
  assert.equal((await f.request(correction,'POST',consent,'fixture-owner')).status,403);
  await f.client.query(`CREATE FUNCTION pg_temp.reject_reopening() RETURNS trigger LANGUAGE plpgsql
    AS $$ BEGIN RAISE EXCEPTION 'synthetic reopening failure'; END $$;
    CREATE TRIGGER reject_reopening BEFORE UPDATE ON sobatnira.lot_closures
    FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_reopening()`);
  assert.equal((await f.request(correction,'POST',consent)).status,500);
  await f.client.query('DROP TRIGGER reject_reopening ON sobatnira.lot_closures');
  assert.equal((await f.request(lot)).body.status,'closed');
  assert.equal((await f.request(detail)).body.correction,null);

  const opened = await f.request(correction,'POST',consent);
  assert.equal(opened.status,201,JSON.stringify(opened.body));
  assert.equal((await f.request(correction,'POST',consent)).body.id,opened.body.id);
  assert.equal((await f.request(lot)).body.status,'open');
  const history = (await f.request(lot+'/closure/history')).body;
  assert.equal(history.total,1);
  assert.equal(history.items[0].reason,'Koreksi batch CLOSURE-FIXTURE.');
  assert.equal(history.items[0].reopenedBy,f.ids.admin);
  const batchPage = (await f.request(f.root+'/production/batches?lotId='+f.closureLotId)).body;
  assert.equal(batchPage.items[0].hasCorrection,true);
  assert.equal(batchPage.items[0].status,'approved');
  const whileOpen = (await f.request(f.root+'/production/recap')).body;
  assert.equal(whileOpen.totalMarginRupiah,report.body.totalMarginRupiah);
  assert.equal(whileOpen.items[0].closed,false);
  assert.equal((await f.request(lot+'/closure','POST',{synthetic:false})).status,409);
  assert.equal((await f.request(correction+'/approve','POST',{version:1})).status,200);
  const closedAgain = await f.request(lot+'/closure','POST',{synthetic:false});
  assert.equal(closedAgain.body.status,'closed');
  assert.notEqual(closedAgain.body.closureId,closure.body.closureId);
  assert.equal((await f.request(correction,'POST',consent)).body.id,opened.body.id);
  assert.equal((await f.request(lot)).body.status,'closed');
 } finally { await f.close(); }
});
