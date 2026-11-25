const test=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {mobileClosureFixture}=require('./mobile-closure-fixture.cjs');

test('rework conserves stock atomically, retains source lineage and blocks incomplete financials',async()=>{
 const f=await mobileClosureFixture({consume:false});
 try{
  const root=f.root+'/production',stock=root+'/sugar';
  assert.equal((await f.request(root+'/masters','POST',{requestId:randomUUID(),kind:'grade',code:'A',version:0,name:'Grade A',active:true,reason:'Master sintetis'})).status,201);
  let state=(await f.request(stock)).body;
  assert.equal((await f.request(stock+'/opening','POST',{requestId:randomUUID(),version:0,reason:'Start sintetis',items:[]})).status,201);
  state=(await f.request(stock)).body;
  assert.equal((await f.request(stock+'/rework-enablement','POST',{requestId:randomUUID(),version:state.version,reason:'Kontrak laporan sintetis telah diuji',reportHandlingConfirmed:true})).status,201);
  assert.equal((await f.request(root+'/lots/'+f.ids.lot+'/costs','POST',{caneCostRupiah:'100',operationalCostRupiah:'100',ingredientCostRupiah:'0',otherCostRupiah:'0'})).status,200);
  async function create(kind,kg='3') {
   const id=randomUUID();const body={id,kind,lotId:f.ids.lot,code:kind+'-'+id,wokNumber:1,occurredAt:'2026-11-16T03:00:00Z',quantityMl:'10000',physicalWeightKg:kg,grades:[{code:'A',weightKg:kg,pricePerKgRupiah:'100'}]};
   const r=await f.request(root+'/batches','POST',body);assert.equal(r.status,201,JSON.stringify(r.body));
   assert.equal((await f.request(f.root+'/lots/'+f.ids.lot+'/juice/reservations','POST',{requestId:randomUUID(),batchId:id,quantityMl:'10000'})).status,201);
   return id;
  }
  const sourceBatch=await create('normal','10');
  const first=await f.request(root+'/batches/'+sourceBatch+'/approve','POST');assert.equal(first.status,200,JSON.stringify(first.body));
  state=(await f.request(stock)).body;const source=state.sources.find(s=>s.batchId===sourceBatch);
  const batch=await create('rework');
  assert.equal((await f.request(root+'/batches/'+batch+'/approve','POST')).status,409);
  const reservation={requestId:randomUUID(),version:state.version,sourceId:source.id,weightKg:'2',reason:'Masak ulang sintetis'};
  const reserve=await f.request(root+'/batches/'+batch+'/rework-inputs','POST',reservation);
  assert.equal(reserve.status,201,JSON.stringify(reserve.body));
  assert.deepEqual((await f.request(root+'/batches/'+batch+'/rework-inputs','POST',reservation)).body,reserve.body);
  // A failure after consumption must restore both juice and sugar reservations.
  await f.client.query(`CREATE FUNCTION pg_temp.reject_rework_output() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic rework failure'; END $$;
    CREATE TRIGGER reject_rework_output BEFORE INSERT ON sobatnira.production_output_allocations FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_rework_output()`);
  assert.equal((await f.request(root+'/batches/'+batch+'/approve','POST')).status,500);
  state=(await f.request(stock)).body;assert.equal(state.sources.find(s=>s.id===source.id).onHandKg,'10');assert.equal(state.sources.find(s=>s.id===source.id).reservedKg,'2');
  await f.client.query('DROP TRIGGER reject_rework_output ON sobatnira.production_output_allocations');
  const approval=await f.request(root+'/batches/'+batch+'/approve','POST');assert.equal(approval.status,200,JSON.stringify(approval.body));
  assert.equal(approval.body.financialStatus,'REWORK_FINANCIALS_PENDING');
  assert.equal((await f.request(root+'/batches/'+batch+'/approve','POST')).status,200);
  state=(await f.request(stock)).body;
  assert.equal(state.sources.find(s=>s.id===source.id).onHandKg,'8');assert.equal(state.sources.find(s=>s.id===source.id).reservedKg,'0');
  assert.equal(state.sources.find(s=>s.batchId===batch).onHandKg,'3');
  const trace=(await f.request(root+'/batches/'+batch+'/traceability')).body;
  assert.equal(trace.grossWeightKg,'3');assert.equal(trace.reusedWeightKg,'2');assert.equal(trace.netAdditionalKg,'1');assert.equal(trace.inputs[0].sourceBatchId,sourceBatch);
  for(const suffix of ['/production-report','/production-report?view=summary','/production-report?view=page','/profit-report','/recap']) {
   const report=await f.request(root+suffix);assert.equal(report.status,409,JSON.stringify(report.body));assert.equal(report.body.code,'REWORK_FINANCIALS_PENDING');
  }
  assert.equal((await f.request(root+'/production-report?lotId='+f.ids.thirdLot)).status,200);
  assert.equal((await f.client.query('SELECT output_snapshot FROM sobatnira.production_calculation_snapshots WHERE id=$1',[first.body.id])).rows[0].output_snapshot.finalSugarKg,'10');
  const cancelled=await create('rework','1');state=(await f.request(stock)).body;
  assert.equal((await f.request(root+'/batches/'+cancelled+'/rework-inputs','POST',{...reservation,requestId:randomUUID(),version:state.version,weightKg:'1'})).status,201);
  assert.equal((await f.request(root+'/batches/'+cancelled+'/cancel','POST')).status,200);
  assert.equal((await f.request(stock)).body.sources.find(s=>s.id===source.id).reservedKg,'0');
  const shrink=await create('rework','1');state=(await f.request(stock)).body;
  const tooMuch={...reservation,requestId:randomUUID(),version:state.version,weightKg:'9'};
  assert.equal((await f.request(root+'/batches/'+shrink+'/rework-inputs','POST',tooMuch)).status,409);
  assert.equal((await f.request(root+'/batches/'+shrink+'/rework-inputs','POST',{...tooMuch,requestId:randomUUID(),weightKg:'2'})).status,201);
  assert.equal((await f.request(root+'/batches/'+shrink+'/approve','POST')).status,200);
  assert.equal((await f.request(root+'/batches/'+shrink+'/traceability')).body.netAdditionalKg,'-1');
  const correction=root+'/batches/'+sourceBatch+'/corrections/'+randomUUID();
  assert.equal((await f.request(correction,'POST',{reason:'Tidak boleh mengurangi gula terpakai'})).status,201);
  assert.equal((await f.request(correction,'PATCH',{version:1,physicalWeightKg:'1',grades:[{code:'A',weightKg:'1',pricePerKgRupiah:'100'}]})).status,200);
  assert.equal((await f.request(correction+'/approve','POST',{version:2})).status,409);
  assert.equal((await f.request(root+'/batches/'+sourceBatch)).body.physical_weight_kg,'10');

 }finally{await f.close();}
});
