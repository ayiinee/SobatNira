const assert = require('node:assert/strict');
const test = require('node:test');
const { allocate, units, kilograms } = require('../dist/production/allocation');
const { assertGradeWeight } = require('../dist/production/batches');
const { calculateProductionPreview } = require('../dist/production/calculation');
const { loadConfiguration } = require('../dist/config/backend.config');
const { migrationChecksum } = require('../dist/documents/database');
const { MediaStorage } = require('../dist/documents/media');
const { reconcileMedia } = require('../dist/documents/reconcile-media');
const { createHash } = require('node:crypto');
const { mkdtemp, writeFile, rm, utimes } = require('node:fs/promises');
const { join } = require('node:path');
const { tmpdir } = require('node:os');

test('allocation conserves micrograms and rupiah with deterministic ties', () => {
  assert.deepEqual([...allocate(units('10'), [{ id:'A', quantity:'80000' }, { id:'B', quantity:'20000' }])].map(([id,n])=>[id,kilograms(n)]), [['A','8'],['B','2']]);
  assert.deepEqual([...allocate(1n, [{id:'B',quantity:'1'}, {id:'A',quantity:'1'}])], [['A',1n],['B',0n]]);
  for(let amount=0n;amount<100n;amount++) {
    const rows=allocate(amount,[{id:'A',quantity:'0.001'},{id:'B',quantity:'2.2'},{id:'C',quantity:'3'}]);
    assert.equal([...rows.values()].reduce((a,b)=>a+b,0n),amount);
  }
  assert.doesNotThrow(()=>assertGradeWeight('0.3',[{weightKg:'0.1'},{weightKg:'0.2'}]));
  assert.throws(()=>assertGradeWeight('0.300001',[{weightKg:'0.1'},{weightKg:'0.2'}]), /Total berat/);
});

test('public preview keeps input bound while cumulative calculator accepts 101 groups', () => {
  const input={caneNetKg:'200',caneCostRupiah:'0',operationalCostRupiah:'0',ingredientCostRupiah:'0',otherCostRupiah:'0',rounding:'HALF_UP',
    grades:Array.from({length:101},(_,i)=>({code:'G'+i,weightKg:'1',pricePerKgRupiah:'1'}))};
  assert.throws(()=>calculateProductionPreview(input), /grades/);
  assert.equal(calculateProductionPreview(input,true).finalSugarKg,'101');
  assert.equal(migrationChecksum('SELECT 1;\r\n'),migrationChecksum('SELECT 1;\n'));
  assert.notEqual(migrationChecksum('SELECT 1;'),migrationChecksum('SELECT 2;'));
});

test('connected export requires privacy URL at configuration boundary', () => {
  assert.throws(()=>loadConfiguration({envFile:false,env:{NODE_ENV:'production',REPORT_EXPORT_ENABLED:'true'}}), /R2_PUBLIC_BASE_URL/);
});

test('verified media refuses same-size tampering; cleanup protects references and young uploads', async () => {
  const folder=await mkdtemp(join(tmpdir(),'sobatnira-media-v2-'));
  const previous=process.env.DOCUMENT_MEDIA_DIR; process.env.DOCUMENT_MEDIA_DIR=folder;
  const media=new MediaStorage();
  try {
    const key='a'.repeat(64), orphan='b'.repeat(64), young='c'.repeat(64);
    const bytes=Buffer.from('89504e470d0a1a0a1234','hex');
    const expected={mime_type:'image/png',size_bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')};
    await media.put(key,'image/png',bytes);
    assert.deepEqual(await media.verifiedRead(key,expected),bytes);
    await writeFile(join(folder,key),Buffer.alloc(bytes.length));
    await assert.rejects(()=>media.verifiedRead(key,expected));
    await media.put(orphan,'image/png',bytes); await media.put(young,'image/png',bytes);
    const old=new Date(Date.now()-48*3600000);await utimes(join(folder,key),old,old);await utimes(join(folder,orphan),old,old);
    const calls=[];
    const db={transaction:work=>work({query:async(sql,args)=>{calls.push(sql);return {rows:sql.startsWith('SELECT 1')&&args[0]===key?[{}]:[]};}})};
    assert.deepEqual(await reconcileMedia(db,media),{candidates:1,removed:0,mode:'report'});
    assert.deepEqual(await reconcileMedia(db,media,true),{candidates:1,removed:1,mode:'cleanup'});
    assert.ok(calls[0].includes('pg_advisory_xact_lock'));
  } finally {
    media.onModuleDestroy(); if(previous===undefined)delete process.env.DOCUMENT_MEDIA_DIR;else process.env.DOCUMENT_MEDIA_DIR=previous;
    await rm(folder,{recursive:true,force:true});
  }
});

test('PDF embeds Unicode font and refuses unsupported glyphs instead of replacing text', async () => {
  const { renderReport } = require('../dist/production/report-formats');
  const { PDFDocument } = require('pdf-lib');
  const snapshot={from:null,before:null,synthetic:false,periodBasis:'lot_received_at',grades:[],
    totals:{lotCount:1,batchCount:0,caneNetKg:'1',finalSugarKg:'0',productionValueRupiah:'0',totalCostRupiah:'0',productionMarginRupiah:'0'},
    items:[{lotId:'test',code:'Kloter Café — É',calculation:null}]};
  const pdf=await renderReport('pdf',snapshot,new Date('2026-11-25T00:00:00Z'));
  assert.ok((await PDFDocument.load(pdf)).getPageCount()>0);
  snapshot.items[0].code='Unsupported \u{1F680}';
  await assert.rejects(()=>renderReport('pdf',snapshot,new Date()),/Karakter laporan/);
  const { ReportExports } = require('../dist/production/report-exports');
  const writes=[], warnings=[];
  const worker=new ReportExports({query:async(sql,args)=>{
    if(sql.startsWith('WITH next'))return {rows:[{id:'report',attempts:1,claim_token:'claim',snapshot,created_at:new Date()}]};
    writes.push(args);return {rows:[]};
  }},null,{findFactoryAccess:async()=>({role:'owner'})},null);
  worker.logger={warn:value=>warnings.push(value)};
  assert.equal(await worker.processOne(),true);
  assert.equal(writes.at(-1)[2],'FAILED');
  assert.equal(warnings[0].reason,'unsupported_pdf_character');
});
