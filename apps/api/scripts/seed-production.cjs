// Development-only, deterministic dataset. Never resets existing application data.
const {createHash}=require('node:crypto');
const {Client}=require('pg');
const {createApplication}=require('../dist/application');
const {loadConfiguration}=require('../dist/config/backend.config');
const {postgresClientOptions}=require('../dist/database/postgres.config');
const {DatabaseService}=require('../dist/database/database.service');
const {IntakeService}=require('../dist/documents/intake.service');
const {MillingService}=require('../dist/milling/milling.service');
const {Batches}=require('../dist/production/batches');
const {JuiceRepository}=require('../dist/juice/juice.repository');
const {useTransactionFixture}=require('../test/integration/database-fixture.cjs');
function id(label){const h=createHash('sha256').update('sobatnira-production-dev-v1:'+label).digest('hex');return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`;}
async function seed(){
 const config=loadConfiguration();if(config.environment==='production')throw new Error('Seed hanya untuk development.');
 const db=new Client(postgresClientOptions(config));await db.connect();let app;
 try{
  await db.query('BEGIN');await db.query("SELECT pg_advisory_xact_lock(hashtext('sobatnira-production-dev-v1'))");
  const actor=(await db.query(`SELECT fm.user_id FROM sobatnira.factory_memberships fm JOIN sobatnira.tenant_memberships tm ON tm.tenant_id=fm.tenant_id AND tm.user_id=fm.user_id JOIN sobatnira.factories f ON f.id=fm.factory_id JOIN sobatnira.tenants t ON t.id=fm.tenant_id WHERE fm.is_active AND tm.is_active AND f.is_active AND t.is_active ORDER BY (fm.role='owner') DESC,fm.user_id LIMIT 1`)).rows[0];
  if(!actor)throw new Error('Siapkan minimal satu akun development aktif sebelum seed.');
  const tenant=id('tenant');await db.query("INSERT INTO sobatnira.tenants(id,name) VALUES($1,'Dataset Sintetis Produksi v1') ON CONFLICT DO NOTHING",[tenant]);
  await db.query('INSERT INTO sobatnira.tenant_memberships(tenant_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[tenant,actor.user_id]);
  app=await createApplication();useTransactionFixture(app.get(DatabaseService),db);
  for(let f=0;f<2;f++){
   const factory=id('factory-'+f);await db.query("INSERT INTO sobatnira.factories(id,tenant_id,name) VALUES($1,$2,$3) ON CONFLICT DO NOTHING",[factory,tenant,'Pabrik Demo Variasi '+(f+1)]);
   await db.query("INSERT INTO sobatnira.factory_memberships(tenant_id,factory_id,user_id,role) VALUES($1,$2,$3,'owner') ON CONFLICT DO NOTHING",[tenant,factory,actor.user_id]);
   const access={userId:actor.user_id,tenantId:tenant,factoryId:factory,factoryName:'Pabrik Demo Variasi '+(f+1),role:'owner'};
   for(let i=0;i<12;i++){
    const supplier=id('supplier-'+(i%6)),lot=id(`lot-${f}-${i}`);
    await db.query('INSERT INTO sobatnira.suppliers(id,tenant_id,name) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',[supplier,tenant,'Pemasok Sintetis '+String.fromCharCode(65+i%6)]);
    if((await db.query('SELECT 1 FROM sobatnira.lots WHERE id=$1',[lot])).rows.length)continue;
    const day=new Date(Date.UTC(2026,9,5+i*3));const at=day.toISOString();
    await db.query('INSERT INTO sobatnira.lots(id,tenant_id,factory_id,supplier_id,display_code,received_at) VALUES($1,$2,$3,$4,$5,$6)',[lot,tenant,factory,supplier,`SYN-${f+1}-${String(i+1).padStart(3,'0')}`,at]);
    let receipt=await app.get(IntakeService).createSynthetic(access,{lotId:lot,requestId:id('intake-'+lot)});
    receipt=await app.get(IntakeService).update(access,receipt.id,{expectedRevision:receipt.currentRevision,reason:'Variasi dataset sintetis v1',changes:{netWeightKg:String(900+i*73+f*31),brix:String(12+i%9),caneTypeCode:['BL','PS862','PS864'][i%3]}});
    if(i===11)continue;
    await app.get(IntakeService).confirmSynthetic(access,receipt.id,receipt.currentRevision);await app.get(IntakeService).approve(access,receipt.id,receipt.currentRevision);
    if(i===10)continue;
    const count=1+i%6,liters=count*(80+i%3*10)+(i%4===0?20:0);
    let milling=await app.get(MillingService).createSynthetic(access,{lotId:lot,requestId:id('milling-'+lot)});
    milling=await app.get(MillingService).update(access,milling.id,{expectedRevision:milling.currentRevision,reason:'Volume nira sintetis eksplisit',changes:{juiceProducedLiters:String(liters),reportedBatches:[]}});
    await app.get(MillingService).confirmSynthetic(access,milling.id,milling.currentRevision);await app.get(MillingService).approve(access,milling.id,milling.currentRevision);
    await app.get(Batches).costs(access,lot,{caneCostRupiah:String((900+i*73+f*31)*(450+i%4*50)),operationalCostRupiah:String(65000+i*7000),ingredientCostRupiah:String(9000+i*1300),otherCostRupiah:String(i%4===1?1800000:i%3*12000)});
    for(let j=0;j<count;j++){
     const batch=id(`batch-${lot}-${j}`),code=['A','B','C'][(i+j)%3];
     await app.get(Batches).create(access,{id:batch,lotId:lot,code:`SYN-${f+1}-${i+1}-B${j+1}`,wokNumber:1+j%3,occurredAt:new Date(day.getTime()+7200000+j*3600000).toISOString(),quantityMl:String((80+i%3*10)*1000),physicalWeightKg:String(22+i+j),grades:[{code,weightKg:String(18+i+j),pricePerKgRupiah:String(({A:21000,B:18000,C:15000})[code]+f*1000+(i>5?500:0))}],synthetic:true});
     await app.get(JuiceRepository).reserve(access,lot,{requestId:id('reservation-'+batch),batchId:batch,originLotId:lot,quantityMl:String((80+i%3*10)*1000),synthetic:true});
     if(i%5!==0)await app.get(Batches).approve(access,batch);
    }
   }
  }
  const result=await db.query(`SELECT (SELECT count(*)::int FROM sobatnira.lots WHERE tenant_id=$1) AS lots,(SELECT count(*)::int FROM sobatnira.production_batches WHERE tenant_id=$1) AS batches,(SELECT count(*)::int FROM sobatnira.production_batches WHERE tenant_id=$1 AND status='approved') AS approved_batches`,[tenant]);
  await db.query('COMMIT');console.log(JSON.stringify({dataset:'production-dev-v1',synthetic:true,...result.rows[0]}));
 }catch(e){await db.query('ROLLBACK');throw e;}finally{await app?.close();await db.end();}
}
module.exports={id,seed};if(require.main===module)seed().catch(e=>{console.error(JSON.stringify({error:e.name,code:e.code,status:e.getStatus?.(),message:e.getStatus?e.message:'Seed dibatalkan; periksa konfigurasi dan skema development.'}));process.exitCode=1});
