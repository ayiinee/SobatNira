const { randomUUID } = require('node:crypto');
const { intakeFixture } = require('./intake-fixture.cjs');
const { TruckIntake } = require('../../dist/documents/truck-intake');
const { MillingRepository } = require('../../dist/milling/milling.repository');
const { Batches } = require('../../dist/production/batches');
const { JuiceRepository } = require('../../dist/juice/juice.repository');
const { parseReservation } = require('../../dist/juice/juice.dto');

async function reportFixture(count = 3) {
  const f = await intakeFixture(false);
  try {
    const access = { userId: f.ids.admin, tenantId: f.ids.tenant, factoryId: f.ids.factory,
      factoryName: 'Synthetic factory', role: 'admin' };
    const batches = f.app.get(Batches), milling = f.app.get(MillingRepository);
    const batchIds = [];
    for (let n = 0; n < count; n++) {
      const lotId = randomUUID();
      await f.client.query(`INSERT INTO sobatnira.lots(id,tenant_id,factory_id,supplier_id,display_code,received_at)
        VALUES($1,$2,$3,$4,$5,timestamptz '2026-10-01T01:00:00Z'+$6*interval '1 hour')`, [lotId, f.ids.tenant, f.ids.factory, f.ids.supplier, 'REPORT-'+n,n*12]);
      await milling.mutate(access, async tx => {
        await f.app.get(TruckIntake).post(tx, {userId:f.ids.admin,factoryId:f.ids.factory,lotId,
          supplierId:f.ids.supplier,documentId:randomUUID(),revisionId:randomUUID(),note:{document_type:'TRUCK_ARRIVAL_NOTE',header:{
            cane_type:{status:'READ',normalized_value:'DEMO'},net_weight_kg:{status:'READ',unit:'kg',normalized_value:'1250'}}}});
        const intake = await milling.intakeAndBalance(tx,access,lotId,false);
        await milling.postMilling(tx,access,{lotId,occurredAt:'2026-11-16T02:00:00Z',juiceProducedLiters:'250',reportedBatches:[]},
          intake,{synthetic:false,ocrDocumentId:randomUUID(),ocrRevisionId:randomUUID(),caneLabel:'DEMO'});
      });
      await batches.costs(access,lotId,{caneCostRupiah:n%2?'100000':'2000000',operationalCostRupiah:'20000',ingredientCostRupiah:'5000',otherCostRupiah:'0'});
      for (let b=0;b<4;b++) {
        const id=randomUUID(); batchIds.push(id);
        await batches.create(access,{id,lotId,code:`REPORT-${n}-${b}`,wokNumber:b%3+1,occurredAt:'2026-11-16T03:00:00Z',
          quantityMl:'50000',physicalWeightKg:'10.125',grades:[{code:b%2?'B':'A',weightKg:'10.125',pricePerKgRupiah:b%2?'18000':'20000'}]});
        await f.app.get(JuiceRepository).reserve(access,lotId,parseReservation({requestId:id,batchId:id,quantityMl:'50000'}));
        await batches.approve(access,id);
      }
      const id= batchIds.at(-1), correction=randomUUID();
      await batches.correct(access,id,correction,'open',{reason:'Synthetic report correction'});
      await batches.correct(access,id,correction,'save',{version:1,physicalWeightKg:'11.125',grades:[
        {code:'B',weightKg:'11.125',pricePerKgRupiah:'18000'}]});
      await batches.correct(access,id,correction,'approve',{version:2});
    }
    return {...f,access,batches,batchIds};
  } catch(e) { await f.close(); throw e; }
}
module.exports={reportFixture};
