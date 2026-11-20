const test=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {reportFixture}=require('./report-fixture.cjs');
const {renderReport,verifyReport}=require('../../dist/production/report-formats');
const {ReportExports}=require('../../dist/production/report-exports');
const {MillingRepository}=require('../../dist/milling/milling.repository');
const {TruckIntake}=require('../../dist/documents/truck-intake');
test('report summary, paged detail and artifacts retain complete exact totals and correction state',async()=>{
 const f=await reportFixture();
 try {
  const path=f.root+'/production/production-report';
  const full=(await f.request(path)).body;
  const summary=await f.request(path+'?view=summary');
  assert.equal(summary.status,200,JSON.stringify(summary.body));
  assert.deepEqual(summary.body.totals,full.totals);
  assert.deepEqual(summary.body.grades,full.grades);
  assert.deepEqual(summary.body.items,[]);
  assert.equal(full.totals.lotCount,3); assert.equal(full.totals.batchCount,12);
  assert.equal((await f.request(path+'?view=summary&from=2026-10-01T01:00:00Z&before=2026-10-01T13:00:00Z')).body.totals.lotCount,1);
  assert.equal((await f.request(path+'?view=summary&before=2026-10-01T01:00:00Z')).body.totals.lotCount,0);
  assert.equal((await f.request(path+'?view=summary&synthetic=true')).body.totals.lotCount,0);
  assert.equal((await f.request(path+'?from=2024-01-01T00:00:00Z&before=2026-11-21T00:00:00Z')).status,400);
  assert.ok(full.items.some(l=>BigInt(l.calculation.productionMarginRupiah)<0n));
  await assert.rejects(f.batches.productionReport(f.access,{},2),e=>e.getStatus()===400);
  assert.equal((await f.batches.productionReport(f.access,{},500)).totals.lotCount,3);
  const ids=[];
  for(let offset=0;offset<3;offset++) {
    const page=await f.request(path+`?view=page&limit=1&offset=${offset}`);
    assert.equal(page.status,200,JSON.stringify(page.body));
    assert.deepEqual(page.body.totals,full.totals);
    assert.deepEqual(page.body.grades,full.grades);
    ids.push(page.body.items[0].lotId);
  }
  assert.equal(new Set(ids).size,3);
  const empty=(await f.request(path+'?view=page&offset=99')).body;
  assert.deepEqual(empty.items,[]); assert.deepEqual(empty.totals,full.totals); assert.equal(empty.nextOffset,null);
  assert.equal((await f.request(f.siblingRoot+'/production/production-report?view=summary')).body.totals.lotCount,0);
  const id=f.batchIds[0], c=randomUUID();
  await f.batches.correct(f.access,id,c,'open',{reason:'Synthetic pending correction'});
  assert.deepEqual((await f.request(path+'?view=summary')).body.totals,full.totals);
  await f.batches.correct(f.access,id,c,'discard',{version:1});
  assert.deepEqual((await f.request(path)).body.totals,full.totals);
  for(const format of ['pdf','xlsx']) {
    const bytes=await renderReport(format,full,new Date('2026-11-20T00:00:00Z'));
    await verifyReport(format,bytes,bytes,full);
  }
  const old=process.env.REPORT_EXPORT_ENABLED;
  process.env.REPORT_EXPORT_ENABLED='true';
  try {
    const key=randomUUID(), payload={from:'2026-10-01T00:00:00Z',before:'2026-11-01T00:00:00Z',synthetic:false};
    const service=f.app.get(ReportExports), owner={...f.access,userId:f.ids.owner,role:'owner'};
    const job=await service.request(owner,key,payload);
    assert.equal(job.status,'QUEUED');
    assert.equal((await service.request(owner,key,payload)).id,job.id);
    const {rows:[saved]}=await f.client.query('SELECT snapshot FROM sobatnira.report_exports WHERE id=$1',[job.id]);
    assert.deepEqual(saved.snapshot.totals,full.totals);
    assert.deepEqual(saved.snapshot.items.map(i=>i.calculationSnapshotId),full.items.map(i=>i.calculationSnapshotId));
  } finally {if(old===undefined) delete process.env.REPORT_EXPORT_ENABLED; else process.env.REPORT_EXPORT_ENABLED=old;}
  for(let n=0;n<98;n++) {
    const lotId=randomUUID();
    await f.client.query(`INSERT INTO sobatnira.lots(id,tenant_id,factory_id,supplier_id,received_at)
      VALUES($1,$2,$3,$4,'2026-10-05T00:00:00Z')`,[lotId,f.ids.tenant,f.ids.factory,f.ids.supplier]);
    await f.app.get(MillingRepository).mutate(f.access,async tx=>f.app.get(TruckIntake).post(tx,{
      userId:f.ids.admin,factoryId:f.ids.factory,lotId,supplierId:f.ids.supplier,
      documentId:randomUUID(),revisionId:randomUUID(),note:{document_type:'TRUCK_ARRIVAL_NOTE',header:{
        cane_type:{status:'READ',normalized_value:'DEMO'},net_weight_kg:{status:'READ',unit:'kg',normalized_value:'1250'}}}}));
  }
  const denied=await f.request(path);
  assert.equal(denied.status,400);assert.equal(denied.body.items,undefined);
  const whole=(await f.request(path+'?view=summary')).body;
  assert.equal(whole.totals.lotCount,101); assert.equal(whole.totals.producedLotCount,3);
  assert.equal(whole.totals.productionMarginRupiah,full.totals.productionMarginRupiah);
  const limited=(await f.request(path+'?view=page&limit=20')).body;
  assert.equal(limited.items.length,20);assert.equal(limited.totals.lotCount,101);assert.equal(limited.nextOffset,20);
  assert.equal((await f.batches.productionReport(f.access,{},500)).items.length,101);
 } finally {await f.close();}
});
