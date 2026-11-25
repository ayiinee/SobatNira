const test=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {mobileClosureFixture}=require('./mobile-closure-fixture.cjs');

test('official masters preserve versions, scope, legacy batches and pilot activation order',async()=>{
 const f=await mobileClosureFixture({consume:false});
 try {
  const root=f.root+'/production',path=root+'/masters';
  assert.equal((await f.request(root+'/sugar/opening','POST',{requestId:randomUUID(),version:0,reason:'Tanpa master',items:[]})).status,409);
  const grade={requestId:randomUUID(),kind:'grade',code:'A',name:'Grade A',version:0,active:true,reason:'Master sintetis'};
  const saved=await f.request(path,'POST',grade);assert.equal(saved.status,201,JSON.stringify(saved.body));
  assert.deepEqual((await f.request(path,'POST',grade)).body,saved.body);
  assert.equal((await f.request(path,'POST',{...grade,name:'Isi berbeda'})).status,409);
  assert.equal((await f.request(path,'POST',{...grade,requestId:randomUUID()})).status,409);
  const wok={requestId:randomUUID(),kind:'wok',code:'1',name:'Wajan satu',capacityLiters:'100',version:0,active:true,reason:'Kapasitas informasi'};
  assert.equal((await f.request(path,'POST',wok)).status,201);
  assert.equal((await f.request(path,'POST',{...wok,requestId:randomUUID()},'fixture-owner')).status,403);
  assert.equal((await f.request(f.siblingRoot+'/production/masters')).body.items.length,0);
  assert.equal((await f.request(path,'GET',undefined,'fixture-owner')).body.items.length,2);
  const id=randomUUID(),body={id,lotId:f.ids.lot,code:'MASTER',wokNumber:1,occurredAt:'2026-11-16T03:00:00Z',quantityMl:'10000',physicalWeightKg:'1',grades:[{code:'A',weightKg:'1',pricePerKgRupiah:'0'}],masterReferences:{wok:{code:'1',version:1},grades:[{code:'A',version:1}]}};
  assert.equal((await f.request(root+'/batches','POST',body)).status,201);
  assert.equal((await f.request(path,'POST',{...wok,requestId:randomUUID(),version:1,active:false,reason:'Nonaktif untuk batch baru'})).status,201);
  assert.equal((await f.request(root+'/batches','POST',{...body,id:randomUUID(),code:'STALE'})).status,409);
  const legacy={...body,id:randomUUID(),code:'LEGACY'};delete legacy.masterReferences;
  assert.equal((await f.request(root+'/batches','POST',legacy)).status,201);
  const parsed=require('../../dist/production/batches').parseBatch(legacy);
  const {masterReferences,kind,source,...oldPayload}=parsed;
  const oldHash=require('node:crypto').createHash('sha256').update(JSON.stringify(oldPayload)).digest('hex');
  await f.client.query('UPDATE sobatnira.production_batches SET input_hash=$2 WHERE id=$1',[legacy.id,oldHash]);
  assert.equal((await f.request(root+'/batches','POST',legacy)).status,201);
  assert.equal((await f.request(root+'/batches','POST',{...legacy,physicalWeightKg:'2'})).status,409);
  const detail=(await f.request(root+'/batches/'+id)).body;
  assert.equal(detail.master_references.wok.version,1);
  const history=(await f.request(path+'?history=true')).body.items;assert.equal(history.length,3);
  assert.equal(history.find(r=>r.kind==='wok' && r.version===1).name,'Wajan satu');
  assert.equal((await f.request(root+'/sugar/opening','POST',{requestId:randomUUID(),version:0,reason:'Setelah master',items:[{gradeCode:'A',quality:'good',weightKg:'1'}]})).status,201);
 }finally {await f.close();}
});
