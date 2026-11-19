const test=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {mobileClosureFixture}=require('./mobile-closure-fixture.cjs');
const {ClosureCheckService}=require('../../dist/juice/closure-check.service');
const {DatabaseService}=require('../../dist/database/database.service');
test('batch approval freezes costs, consumes once, isolates scope and produces an exact report',async()=>{
 const f=await mobileClosureFixture({consume:false});
 try{
  const root=f.root+'/production',batch=randomUUID();
  const body={id:batch,lotId:f.ids.lot,code:'BATCH-TEST',wokNumber:1,occurredAt:'2026-11-16T03:00:00Z',quantityMl:'100000',physicalWeightKg:'32',grades:[{code:'A',weightKg:'30',pricePerKgRupiah:'20000'}]};
  assert.equal((await f.request(root+'/batches','POST',body)).status,201);
  assert.equal((await f.request(root+'/batches','POST',body)).body.id,batch);
  assert.equal((await f.request(root+'/batches','POST',{...body,quantityMl:'200000'})).status,409);
  assert.equal((await f.request(root+'/lots/'+f.ids.lot+'/costs','POST',{caneCostRupiah:'100000',operationalCostRupiah:'20000',ingredientCostRupiah:'5000',otherCostRupiah:'0'})).status,200);
  assert.equal((await f.request(root+'/batches/'+batch+'/approve','POST')).status,409);
  const requestId=randomUUID();
  assert.equal((await f.request(f.root+'/lots/'+f.ids.lot+'/juice/reservations','POST',{requestId,batchId:batch,quantityMl:'100000'})).status,201);
  const approved=await f.request(root+'/batches/'+batch+'/approve','POST');assert.equal(approved.status,200,JSON.stringify(approved.body));
  assert.equal(approved.body.output_snapshot.productionMarginRupiah,'475000');
  const replay=await f.request(root+'/batches/'+batch+'/approve','POST');assert.equal(replay.body.id,approved.body.id);
  assert.equal((await f.request(f.root+'/lots/'+f.ids.lot+'/juice/availability')).body.onHandMl,'150000');
  const report=await f.request(root+'/profit-report');assert.equal(report.body.totalMarginRupiah,'475000');assert.equal(report.body.items.length,1);
  assert.equal((await f.request(root+'/profit-report?from=2026-12-01T00:00:00Z')).body.total,0);
  const production=await f.request(root+'/production-report');
  assert.equal(production.status,200,JSON.stringify(production.body));
  assert.equal(production.body.totals.lotCount,1);
  assert.equal(production.body.totals.batchCount,1);
  assert.equal(production.body.totals.finalSugarKg,'30');
  assert.equal(production.body.totals.productionMarginRupiah,'475000');
  assert.equal(production.body.items[0].batches[0].grades[0].code,'A');
  assert.equal(production.body.grades[0].exactValueRupiah,'600000');
  assert.equal((await f.request(root+'/production-report?synthetic=true')).body.totals.lotCount,0);
  assert.equal((await f.request(root+'/production-report?before=2026-11-16T01:00:00Z')).body.totals.lotCount,0);
  assert.equal((await f.request(root+'/production-report?from=2026-11-16T01:00:00Z')).body.totals.lotCount,1);
  assert.equal((await f.request(f.siblingRoot+'/production/production-report')).body.totals.lotCount,0);

  assert.equal((await f.request(root+'/lots/'+f.ids.lot+'/costs','POST',{caneCostRupiah:'1',operationalCostRupiah:'0',ingredientCostRupiah:'0',otherCostRupiah:'0'})).status,409);
  const local=new ClosureCheckService({},f.app.get(DatabaseService));
  const access={tenantId:f.ids.tenant,factoryId:f.ids.factory,userId:f.ids.admin};
  await local.requireClear(access,f.ids.lot,false,'Bearer fixture-admin');
  assert.equal((await f.request(root+'/batches','POST',{...body,id:randomUUID(),code:'DRAFT-BLOCKS-CLOSURE'})).status,201);
  await assert.rejects(()=>local.requireClear(access,f.ids.lot,false,'Bearer fixture-admin'),e=>e.getStatus()===409);
  assert.equal((await f.request(root+'/production-report')).body.totals.batchCount,1);
  assert.equal((await f.request(f.siblingRoot+'/production/batches/'+batch+'/approve','POST')).status,404);
 }finally{await f.close();}
});
