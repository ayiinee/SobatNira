const test=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Database}=require('../../dist/documents/database');
const {mobileClosureFixture}=require('./mobile-closure-fixture.cjs');

test('approved note rows remain unique across revisions and multi-grade drafts are accepted',async()=>{
 const db=new Database();try{await db.migrate();}finally{await db.onModuleDestroy();}
 const f=await mobileClosureFixture({consume:false});
 try{
  const [document,revision,submission,operator,message,media]=Array.from({length:6},()=>randomUUID());
  await f.client.query("INSERT INTO operator_contacts(id,factory_id,display_name,phone_e164) VALUES($1,$2,'Synthetic source','+628'||floor(random()*100000000000)::bigint::text)",[operator,f.ids.factory]);
  await f.client.query("INSERT INTO whatsapp_inbound_messages(id,operator_id,provider_message_id,event,fingerprint) VALUES($1::uuid,$2,$1::text,'{}','synthetic')",[message,operator]);
  await f.client.query("INSERT INTO media_assets(id,factory_id,object_key,mime_type,size_bytes,sha256) VALUES($1::uuid,$2,$1::text,'image/png',1,'synthetic')",[media,f.ids.factory]);
  await f.client.query("INSERT INTO source_documents(id,factory_id,document_type) VALUES($1,$2,'PRODUCTION_NOTE')",[document,f.ids.factory]);
  await f.client.query('INSERT INTO document_submissions(id,document_id,inbound_message_id,media_asset_id) VALUES($1,$2,$3,$4)',[submission,document,message,media]);
  const field=(v,unit=null)=>({status:'READ',normalized_value:v,unit});
  const note={cane_blocks:[{cane_label:field('DEMO'),batches:[1,2].map(n=>({row_reference:'row-'+n,pan_number:field(1),output:{grade:field('A'),hasil_kg:field(10,'kg')},cooking:{isi_kg:field(100,'kg')}}))}]};
  await f.client.query('INSERT INTO document_revisions(id,document_id,submission_id,version,extraction) VALUES($1,$2,$3,1,$4)',[revision,document,submission,note]);
  await f.client.query('INSERT INTO document_approvals(document_id,revision_id,user_id) VALUES($1,$2,$3)',[document,revision,f.ids.admin]);
  await f.client.query('UPDATE sobatnira.milling_records SET ocr_document_id=$1,ocr_revision_id=$2 WHERE lot_id=$3',[document,revision,f.ids.lot]);
  const root=f.root+'/production';
  const rows=await f.request(root+'/lots/'+f.ids.lot+'/batch-sources');
  assert.equal(rows.status,200,JSON.stringify(rows.body));assert.equal(rows.body.items.length,2);
  const body={id:randomUUID(),lotId:f.ids.lot,code:'NOTE-ROW',wokNumber:1,occurredAt:'2026-11-16T03:00:00Z',quantityMl:'10000',physicalWeightKg:'10',grades:[{code:'A',weightKg:'8',pricePerKgRupiah:'100'},{code:'B',weightKg:'2',pricePerKgRupiah:'50'}],source:rows.body.items[0].source};
  assert.equal((await f.request(root+'/batches','POST',body)).status,201);
  assert.equal((await f.request(root+'/batches','POST',{...body,id:randomUUID(),code:'DUPLICATE'})).status,409);
  const next=randomUUID();await f.client.query('INSERT INTO document_revisions(id,document_id,submission_id,version,extraction) VALUES($1,$2,$3,2,$4)',[next,document,submission,note]);
  await f.client.query('INSERT INTO document_approvals(document_id,revision_id,user_id) VALUES($1,$2,$3)',[document,next,f.ids.admin]);
  assert.equal((await f.request(root+'/batches/'+body.id+'/approve','POST')).status,409);
  assert.equal((await f.request(root+'/batches/'+body.id+'/cancel','POST')).status,200);
  assert.equal((await f.request(root+'/batches','POST',{...body,id:randomUUID(),code:'LATEST',source:{...body.source,revisionId:next}})).status,201);
 }finally{await f.close();}
});
