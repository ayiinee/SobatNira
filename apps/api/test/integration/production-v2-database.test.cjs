const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const test=require('node:test');
const {mobileClosureFixture}=require('./mobile-closure-fixture.cjs');
const {TruckIntake}=require('../../dist/documents/truck-intake');
const {MillingRepository}=require('../../dist/milling/milling.repository');
const {intakeFixture}=require('./intake-fixture.cjs');

test('lot costs protect concurrent creation and reject stale or versionless edits after cutover', async () => {
 const f = await intakeFixture(true);
 const previous = process.env.LOT_COST_REQUIRE_VERSION;
 const path = f.root + '/production/lots/' + f.ids.lot;
 const costs = caneCostRupiah => ({
  caneCostRupiah, operationalCostRupiah: '0', ingredientCostRupiah: '0', otherCostRupiah: '0',
 });
 const save = data => f.request(path + '/costs', 'POST', data);
 try {
  process.env.LOT_COST_REQUIRE_VERSION = 'false';
  assert.equal((await f.request(path + '/cost-corrections')).status, 404);
  const concurrent = await Promise.all([
   save({ ...costs('100'), version: 0 }), save({ ...costs('200'), version: 0 }),
  ]);
  assert.deepEqual(concurrent.map(result => result.status).sort(), [200, 409]);
  assert.equal((await save(costs('250'))).status, 200);
  const first = await f.request(path + '/cost-corrections');
  const second = await f.request(path + '/cost-corrections');
  assert.equal(first.body.version, 2);
  assert.equal(second.body.version, first.body.version);
  process.env.LOT_COST_REQUIRE_VERSION = 'true';
  assert.equal((await save({ ...costs('300'), version: first.body.version })).status, 200);
  for (const input of [{ ...costs('400'), version: second.body.version }, costs('450')]) {
   const conflict = await save(input);
   assert.equal(conflict.status, 409);
   assert.equal(conflict.body.code, 'LOT_COST_VERSION_CONFLICT');
  }
  const latest = await f.request(path + '/cost-corrections');
  assert.equal(latest.body.version, 3);
  assert.equal(latest.body.cane_rupiah, '300');
  assert.equal(latest.body.frozen, false);
 } finally {
  if (previous === undefined) delete process.env.LOT_COST_REQUIRE_VERSION;
  else process.env.LOT_COST_REQUIRE_VERSION = previous;
  try {
   await f.client.query('DELETE FROM sobatnira.lot_production_costs WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3',
    [f.ids.tenant, f.ids.factory, f.ids.lot]);
  } finally { await f.close(); }
 }
});

test('mixed origins conserve output, allocate cooking costs, and owner corrections preserve history',async()=>{
 const f=await mobileClosureFixture({consume:false});
 try{
  const a=f.ids.lot,b=f.ids.secondLot,root=f.root+'/production';
  const access={tenantId:f.ids.tenant,factoryId:f.ids.factory,userId:f.ids.admin,role:'admin'};
  const milling=f.app.get(MillingRepository);
  await milling.mutate(access,async tx=>{
   await f.app.get(TruckIntake).post(tx,{userId:f.ids.admin,factoryId:f.ids.factory,lotId:b,supplierId:f.ids.supplier,
    documentId:randomUUID(),revisionId:randomUUID(),note:{document_type:'TRUCK_ARRIVAL_NOTE',header:{
     cane_type:{status:'READ',normalized_value:'DEMO'},net_weight_kg:{status:'READ',unit:'kg',normalized_value:'1000'}}}});
   const receipt=await milling.intakeAndBalance(tx,access,b,false);
   await milling.postMilling(tx,access,{lotId:b,occurredAt:'2026-11-16T02:00:00Z',juiceProducedLiters:'100',reportedBatches:[]},receipt,
    {synthetic:false,ocrDocumentId:randomUUID(),ocrRevisionId:randomUUID(),caneLabel:'DEMO'});
  });
  for(const [lot,cane,op] of [[a,'100','0'],[b,'200','1000']]){
   const r=await f.request(root+'/lots/'+lot+'/costs','POST',{caneCostRupiah:cane,operationalCostRupiah:op,ingredientCostRupiah:'0',otherCostRupiah:'0'});
   assert.equal(r.status,200,JSON.stringify(r.body));
  }
  const transfer=await f.request(f.root+'/lots/'+a+'/juice/transfers','POST',{requestId:randomUUID(),toLotId:b,originLotId:a,quantityMl:'80000'});
  assert.equal(transfer.status,201,JSON.stringify(transfer.body));
  const id=randomUUID();
  assert.equal((await f.request(root+'/batches','POST',{id,lotId:b,code:'MIXED-V2',wokNumber:1,occurredAt:'2026-11-16T03:00:00Z',quantityMl:'100000',physicalWeightKg:'10',grades:[{code:'A',weightKg:'10',pricePerKgRupiah:'100'}]})).status,201);
  for(const [origin,quantity]of [[a,'80000'],[b,'20000']]){
   const r=await f.request(f.root+'/lots/'+b+'/juice/reservations','POST',{requestId:randomUUID(),batchId:id,originLotId:origin,quantityMl:quantity});
   assert.equal(r.status,201,JSON.stringify(r.body));
  }
  await f.client.query('UPDATE sobatnira.production_batches SET physical_weight_kg=9.999999 WHERE id=$1',[id]);
  assert.equal((await f.request(root+'/batches/'+id+'/approve','POST')).status,400);
  assert.equal((await f.client.query("SELECT count(*)::int AS n FROM sobatnira.juice_reservations WHERE batch_id=$1 AND state='consumed'",[id])).rows[0].n,0);
  await f.client.query('UPDATE sobatnira.production_batches SET physical_weight_kg=10 WHERE id=$1',[id]);
  const approval=await f.request(root+'/batches/'+id+'/approve','POST'); assert.equal(approval.status,200,JSON.stringify(approval.body));
  assert.equal((await f.request(root+'/batches/'+id+'/approve','POST')).body.id,approval.body.id);
  const report=(await f.request(root+'/production-report')).body;
  assert.equal(report.totals.batchCount,1);assert.equal(report.totals.finalSugarKg,'10');assert.equal(report.totals.totalCostRupiah,'1300');
  const summary=await f.request(root+'/production-report?view=summary');
  assert.equal(summary.status,200,JSON.stringify(summary.body));
  assert.deepEqual(summary.body.totals,report.totals);
  assert.deepEqual(summary.body.grades,report.grades);
  for(const [lot,weight] of [[a,'8'],[b,'2']]) {
   const scoped=await f.request(root+'/production-report?view=summary&lotId='+lot);
   assert.equal(scoped.status,200,JSON.stringify(scoped.body));
   assert.equal(scoped.body.totals.batchCount,1);
   assert.equal(scoped.body.grades[0].weightKg,weight);
   const page=await f.request(root+'/production-report?view=page&limit=1&lotId='+lot);
   assert.equal(page.status,200,JSON.stringify(page.body));
   assert.deepEqual(page.body.totals,scoped.body.totals);
  }
  for(const [lot,kg,op]of [[a,'8','800'],[b,'2','200']]){
   const item=report.items.find(x=>x.lotId===lot);assert.equal(item.calculation.finalSugarKg,kg);assert.equal(item.calculation.costs.operationalRupiah,op);
   assert.equal(item.calculation.costs.caneRupiah,lot===a?'100':'200');
  }
  const path=root+'/lots/'+b+'/cost-corrections', correction=path+'/'+randomUUID();
  const proposed={version:1,reason:'Biaya memasak diverifikasi',caneCostRupiah:'200',operationalCostRupiah:'2000',ingredientCostRupiah:'0',otherCostRupiah:'0'};
  assert.equal((await f.request(path)).body.version,1);
  assert.equal((await f.request(correction,'POST',proposed)).status,201);
  assert.equal((await f.request(correction,'POST',proposed)).status,201);
  const ownerDraft = await f.request(path + '/' + randomUUID(),'POST',proposed,'fixture-owner');
  assert.equal(ownerDraft.status,201);
  const inbox = root + '/cost-corrections';
  assert.equal((await f.request(inbox)).body.items.length,1);
  const ownerInbox = await f.request(inbox+'?limit=1','GET',undefined,'fixture-owner');
  assert.equal(ownerInbox.body.nextOffset,1);
  assert.equal(ownerInbox.body.items[0].status,'pending');
  assert.equal((await f.request(inbox+'?limit=1&offset=1','GET',undefined,'fixture-owner')).body.items.length,1);
  assert.deepEqual((await f.request(f.siblingRoot+'/production/cost-corrections')).body.items,[]);
  assert.equal((await f.request(correction,'POST',{...proposed,reason:'Berbeda'})).status,409);
  assert.equal((await f.request(correction+'/approve','POST')).status,403);
  const approved=await f.request(correction+'/approve','POST',undefined,'fixture-owner');assert.equal(approved.status,201,JSON.stringify(approved.body));
  assert.equal((await f.request(correction+'/approve','POST',undefined,'fixture-owner')).body.id,approved.body.id);
  const afterApproval = (await f.request(inbox,'GET',undefined,'fixture-owner')).body.items;
  assert.equal(afterApproval.find(item => item.id===approved.body.id).status,'approved');
  assert.equal(afterApproval.find(item => item.id===ownerDraft.body.id).status,'stale');
  assert.equal((await f.request(path)).body.version,2);
  assert.equal((await f.request(path+'/'+randomUUID(),'POST',proposed)).status,409);
  const updated=(await f.request(root+'/production-report')).body;
  assert.equal(updated.items.find(x=>x.lotId===a).calculation.costs.operationalRupiah,'1600');
  assert.equal(updated.items.find(x=>x.lotId===b).calculation.costs.operationalRupiah,'400');
  const original=(await f.client.query('SELECT output_snapshot FROM sobatnira.production_calculation_snapshots WHERE id=$1',[approval.body.id])).rows[0];
  assert.equal(original.output_snapshot.costs.operationalRupiah,'200');
  const events=(await f.client.query("SELECT * FROM sobatnira.production_audit_events WHERE entity_type='lot_costs' AND entity_id=$1 ORDER BY occurred_at",[b])).rows;
  assert.equal(events.length,2);assert.equal(events[1].before_data.version,1);assert.equal(events[1].after_data.version,2);
  // A mixed correction updates both origin snapshots, keeps stock consumption unchanged,
  // and rolls back all origins when any snapshot insert fails.
  const batchCorrection=root+'/batches/'+id+'/corrections/'+randomUUID();
  assert.equal((await f.request(batchCorrection,'POST',{reason:'Hasil timbang ulang'})).status,201);
  assert.equal((await f.request(batchCorrection,'PATCH',{version:1,physicalWeightKg:'12',grades:[
   {code:'A',weightKg:'8',pricePerKgRupiah:'100'},{code:'B',weightKg:'4',pricePerKgRupiah:'200'}]})).status,200);
  await f.client.query(`CREATE FUNCTION pg_temp.reject_mixed_snapshot() RETURNS trigger LANGUAGE plpgsql
   AS $$ BEGIN RAISE EXCEPTION 'synthetic mixed rollback'; END $$;
   CREATE TRIGGER reject_mixed_snapshot BEFORE INSERT ON sobatnira.production_calculation_snapshots
   FOR EACH ROW WHEN (NEW.correction_id IS NOT NULL) EXECUTE FUNCTION pg_temp.reject_mixed_snapshot()`);
  assert.equal((await f.request(batchCorrection+'/approve','POST',{version:2})).status,500);
  assert.equal((await f.request(root+'/production-report')).body.totals.finalSugarKg,'10');
  await f.client.query('DROP TRIGGER reject_mixed_snapshot ON sobatnira.production_calculation_snapshots');
  assert.equal((await f.request(batchCorrection+'/approve','POST',{version:2})).status,200);
  const corrected=(await f.request(root+'/production-report')).body;
  assert.equal(corrected.totals.finalSugarKg,'12');assert.equal(corrected.totals.batchCount,1);
  assert.equal(corrected.items.find(x=>x.lotId===a).calculation.finalSugarKg,'9.6');
  assert.equal(corrected.items.find(x=>x.lotId===b).calculation.finalSugarKg,'2.4');
  assert.equal(corrected.totals.productionValueRupiah,'1600');
  const stock=(await f.client.query("SELECT sum(quantity_ml)::text AS used FROM sobatnira.juice_reservations WHERE batch_id=$1 AND state='consumed'",[id])).rows[0];
  assert.equal(stock.used,'100000');
  // Unscoped B1 routes remain unavailable even with valid identity and forged dev headers.
  const {BACKEND_CONFIG}=require('../../dist/config/backend.config');
  f.app.get(BACKEND_CONFIG).environment='production';
  const previousMode=process.env.SOBATNIRA_MODE;process.env.SOBATNIRA_MODE='connected';
  try{
   for(const path of ['/production-masters/grades','/stock/sugar','/batches']){
    assert.equal((await f.request(path)).status,403);
    const response=await fetch(f.base+path,{headers:{Authorization:'Bearer fixture-admin',
     'x-dev-user-id':f.ids.admin,'x-dev-tenant-id':f.ids.tenant,'x-dev-factory-id':f.ids.factory,'x-dev-role':'admin'}});
    assert.equal(response.status,403);
   }
  }finally{if(previousMode===undefined)delete process.env.SOBATNIRA_MODE;else process.env.SOBATNIRA_MODE=previousMode;}
 }finally{await f.close();}
});

test('OCR migration checks reject drift and require explicit baseline for old history',async()=>{
 const {Client}=require('pg');const {Database}=require('../../dist/documents/database');
 const schema='ocr_checksum_'+randomUUID().replaceAll('-','');
 const admin=new Client({connectionString:process.env.DATABASE_URL});
 const previous=process.env.DATABASE_URL;let db;
 try{
  await admin.connect();await admin.query('CREATE SCHEMA '+schema);
  const url=new URL(previous);url.searchParams.set('options','-c search_path='+schema);
  process.env.DATABASE_URL=url.toString();db=new Database();
  await db.migrate();await db.assertMigrationsApplied();await db.migrate();
  await db.query("UPDATE sobatnira_migrations SET checksum='wrong' WHERE name='001_document_intake.sql'");
  await assert.rejects(()=>db.assertMigrationsApplied());await assert.rejects(()=>db.migrate());
  await db.query("UPDATE sobatnira_migrations SET checksum=NULL WHERE name='001_document_intake.sql'");
  await assert.rejects(()=>db.migrate());await db.migrate(true);await db.assertMigrationsApplied();
 }finally{
  process.env.DATABASE_URL=previous;await db?.onModuleDestroy();
  await admin.query('DROP SCHEMA IF EXISTS '+schema+' CASCADE');await admin.end();
 }
});

test('approval can extend a cumulative snapshot beyond 100 grade/price groups',async()=>{
 const f=await mobileClosureFixture({consume:false});
 try{
  const root=f.root+'/production',lot=f.ids.lot;
  assert.equal((await f.request(root+'/lots/'+lot+'/costs','POST',{
   caneCostRupiah:'0',operationalCostRupiah:'0',ingredientCostRupiah:'0',otherCostRupiah:'0'})).status,200);
  assert.equal((await f.request(root+'/lots/'+lot+'/costs','POST',{
   version:999,caneCostRupiah:'0',operationalCostRupiah:'0',ingredientCostRupiah:'0',otherCostRupiah:'0'})).status,409);
  const create=async(code,grade)=>{
   const id=randomUUID();
   assert.equal((await f.request(root+'/batches','POST',{id,lotId:lot,code,wokNumber:1,occurredAt:'2026-11-16T03:00:00Z',
    quantityMl:'1000',physicalWeightKg:'1',grades:[{code:grade,weightKg:'1',pricePerKgRupiah:'1'}]})).status,201);
   assert.equal((await f.request(f.root+'/lots/'+lot+'/juice/reservations','POST',{
    requestId:randomUUID(),batchId:id,quantityMl:'1000'})).status,201);
   const r=await f.request(root+'/batches/'+id+'/approve','POST');assert.equal(r.status,200,JSON.stringify(r.body));
   return id;
  };
  const first=await create('GROUPS-INITIAL','A');
  const path=root+'/batches/'+first+'/corrections/'+randomUUID();
  assert.equal((await f.request(path,'POST',{reason:'Synthetic 100 grade boundary'})).status,201);
  assert.equal((await f.request(path,'PATCH',{version:1,physicalWeightKg:'100',
   grades:Array.from({length:100},(_,i)=>({code:'C'+i,weightKg:'1',pricePerKgRupiah:'1'}))})).status,200);
  assert.equal((await f.request(path+'/approve','POST',{version:2})).status,200);
  await create('GROUPS-NEXT','Z');
  const report=(await f.request(root+'/production-report')).body;
  assert.equal(report.grades.length,101);assert.equal(report.totals.finalSugarKg,'101');
  assert.equal(report.totals.productionValueRupiah,'101');
 }finally{await f.close();}
});
