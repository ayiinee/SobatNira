const test=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {mobileClosureFixture}=require('./mobile-closure-fixture.cjs');

test('inventory activation, exact production, quality and correction reconcile without backfill',async()=>{
 const f=await mobileClosureFixture({consume:false});
 try{
  const root=f.root+'/production', stock=root+'/sugar';
  const opening={requestId:randomUUID(),version:0,reason:'Hitung fisik sintetis',items:[{gradeCode:'A',quality:'good',weightKg:'2.000001'}]};
  const receipt=await f.request(stock+'/opening','POST',opening);assert.equal(receipt.status,201,JSON.stringify(receipt.body));
  assert.deepEqual((await f.request(stock+'/opening','POST',opening)).body,receipt.body);
  assert.equal((await f.request(stock+'/opening','POST',{...opening,reason:'Isi berbeda'})).status,409);
  let state=(await f.request(stock)).body;assert.equal(state.sources[0].onHandKg,'2.000001');
  const source=state.sources[0].id;
  const classify={requestId:randomUUID(),version:state.version,reason:'Gula gagal sintetis',sourceId:source,quality:'failed',weightKg:'1'};
  assert.equal((await f.request(stock+'/quality','POST',classify)).status,201);
  assert.equal((await f.request(stock+'/adjustments','POST',{requestId:randomUUID(),version:classify.version,reason:'Versi usang',sourceId:source,direction:'subtract',weightKg:'1'})).status,409);
  state=(await f.request(stock)).body;
  assert.equal(state.sources.find(s=>s.quality==='failed').onHandKg,'1');
  assert.equal(state.sources.find(s=>s.quality==='good').onHandKg,'1.000001');
  assert.equal((await f.request(stock+'/adjustments','POST',{requestId:randomUUID(),version:state.version,reason:'Tidak boleh negatif',sourceId:source,direction:'subtract',weightKg:'2'})).status,409);
  const costs={caneCostRupiah:'100',operationalCostRupiah:'100',ingredientCostRupiah:'0',otherCostRupiah:'0'};
  assert.equal((await f.request(root+'/lots/'+f.ids.lot+'/costs','POST',costs)).status,200);
  const id=randomUUID(),body={id,lotId:f.ids.lot,code:'LEDGER',wokNumber:1,occurredAt:'2026-11-16T03:00:00Z',quantityMl:'10000',physicalWeightKg:'3',grades:[{code:'A',weightKg:'3',pricePerKgRupiah:'100'}]};
  assert.equal((await f.request(root+'/batches','POST',body)).status,201);
  assert.equal((await f.request(f.root+'/lots/'+f.ids.lot+'/juice/reservations','POST',{requestId:randomUUID(),batchId:id,quantityMl:'10000'})).status,201);
  assert.equal((await f.request(root+'/batches/'+id+'/approve','POST')).status,200);
  assert.equal((await f.request(root+'/batches/'+id+'/approve','POST')).status,200);
  state=(await f.request(stock)).body;assert.equal(state.sources.find(s=>s.batchId===id).onHandKg,'3');
  const history=(await f.request(stock+'/history')).body;assert.equal(history.items.length,4);
  const sum=(await f.client.query('SELECT sum(quantity_delta_kg)::text AS total FROM sobatnira.production_sugar_entries WHERE tenant_id=$1',[f.ids.tenant])).rows[0].total;
  assert.equal(Number(sum),5.000001);
  assert.equal((await f.request(stock+'/opening','POST',opening,'fixture-owner')).status,403);
  assert.equal((await f.request(f.siblingRoot+'/production/sugar')).body.active,false);
  assert.equal((await f.request(stock+'?synthetic=true')).body.active,false);
  assert.match(state.limitation,/Pengeluaran selain rework/);
 }finally{await f.close();}
});
