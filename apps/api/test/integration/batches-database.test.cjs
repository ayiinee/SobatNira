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
  assert.deepEqual(recap.body.items[0].batches[0].grades,[{code:'A',weightKg:'30'}]);
  assert.equal((await f.request(root+'/batches?lotId='+f.ids.lot+'&synthetic=false')).body.items[0].id,batch);
  assert.equal((await f.request(root+'/batches?lotId='+f.ids.secondLot)).body.items.length,0);
  assert.equal((await f.request(root+'/profit-report?from=2026-12-01T00:00:00Z')).body.total,0);
  assert.equal((await f.request(root+'/lots/'+f.ids.lot+'/costs','POST',{caneCostRupiah:'1',operationalCostRupiah:'0',ingredientCostRupiah:'0',otherCostRupiah:'0'})).status,409);
  const local=new ClosureCheckService({});
  const session=f.app.get(DatabaseService);
  const access={tenantId:f.ids.tenant,factoryId:f.ids.factory,userId:f.ids.admin};
  await local.requireClear(session,access,f.ids.lot,false,'Bearer fixture-admin');
  assert.equal((await f.request(root+'/batches','POST',{...body,id:randomUUID(),code:'DRAFT-BLOCKS-CLOSURE'})).status,201);
  await assert.rejects(()=>local.requireClear(session,access,f.ids.lot,false,'Bearer fixture-admin'),e=>e.getStatus()===409);
  assert.equal((await f.request(f.siblingRoot+'/production/batches/'+batch+'/approve','POST')).status,404);
  assert.equal((await f.request(f.siblingRoot+'/production/recap')).body.total,0);
 }finally{await f.close();}
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
   quantityMl:'100000',physicalWeightKg:'32',grades:[grade]};
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

test('operational closure checks an approved batch in the same database', async () => {
 const f = await mobileClosureFixture();
 try {
  const closure = await f.request(f.root + '/lots/' + f.closureLotId + '/closure', 'POST', {synthetic:false});
  assert.equal(closure.status,200,JSON.stringify(closure.body));
  assert.equal(closure.body.status,'closed');
  const report = await f.request(f.root + '/production/recap');
  assert.equal(report.body.items[0].closed,true);
 } finally { await f.close(); }
});
