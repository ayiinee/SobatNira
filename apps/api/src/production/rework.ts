import { BadRequestException, Body, ConflictException, Controller, Get, Injectable, Param, Post } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { JuiceRepository } from '../juice/juice.repository';
import { kilograms, units } from './allocation';
import { decimal, sumDecimals } from './decimal';
import { found, uuid } from './production.dto';
import { SugarInventory } from './sugar-inventory';

const keys=(a:FactoryAccess)=>[a.tenantId,a.factoryId];

export async function reworkAffectedLots(db: DatabaseSession, access: FactoryAccess, synthetic: boolean) {
  const {rows}=await db.query<{id:string}>(`WITH RECURSIVE batches AS (
    SELECT id,lot_id,kind FROM sobatnira.production_batches WHERE tenant_id=$1 AND factory_id=$2 AND is_synthetic=$3 AND status='approved'
  ), edges AS (
    SELECT b.lot_id AS a,r.origin_lot_id AS z FROM batches b JOIN sobatnira.juice_reservations r ON r.batch_id=b.id AND r.state='consumed'
    UNION SELECT b.lot_id,COALESCE(s.origin_lot_id,p.lot_id,b.lot_id) FROM batches b
      JOIN sobatnira.production_rework_reservations r ON r.batch_id=b.id AND r.state='consumed'
      JOIN sobatnira.production_sugar_sources s ON s.id=r.source_id LEFT JOIN batches p ON p.id=s.batch_id
  ), affected(id) AS (
    SELECT lot_id FROM batches WHERE kind='rework'
    UNION SELECT CASE WHEN e.a=f.id THEN e.z ELSE e.a END FROM affected f JOIN edges e ON e.a=f.id OR e.z=f.id
  ) SELECT DISTINCT id FROM affected ORDER BY id`,[...keys(access),synthetic]);
  return rows.map(r=>r.id);
}

export async function assertFinancialsAvailable(db: DatabaseSession, access: FactoryAccess, synthetic: boolean,
  from: string|null=null,before: string|null=null,lotId: string|null=null,
  selection: {supplierId?:string|null;batchId?:string|null;grade?:string|null}={}) {
  const affected=await reworkAffectedLots(db,access,synthetic);
  if(!affected.length) return;
  const selected=(await db.query<{id:string}>(`SELECT l.id FROM sobatnira.lots l WHERE l.tenant_id=$1 AND l.factory_id=$2 AND l.id=ANY($3::uuid[])
    AND ($4::timestamptz IS NULL OR l.received_at >= $4) AND ($5::timestamptz IS NULL OR l.received_at < $5)
    AND ($6::uuid IS NULL OR l.id=$6) AND ($7::uuid IS NULL OR l.supplier_id=$7)
    AND (($8::uuid IS NULL AND $9::text IS NULL) OR EXISTS (
      SELECT 1 FROM sobatnira.production_batches b WHERE b.tenant_id=$1 AND b.factory_id=$2 AND b.status='approved' AND b.is_synthetic=$10
        AND ($8::uuid IS NULL OR b.id=$8) AND ($9::text IS NULL OR EXISTS(SELECT 1 FROM sobatnira.batch_grade_results g WHERE g.batch_id=b.id AND g.code=$9))
        AND (b.lot_id=l.id OR EXISTS(SELECT 1 FROM sobatnira.juice_reservations r WHERE r.batch_id=b.id AND r.origin_lot_id=l.id AND r.state='consumed'))
    )) ORDER BY l.id`,[...keys(access),affected,from,before,lotId,selection.supplierId??null,selection.batchId??null,selection.grade??null,synthetic])).rows;
  if(selected.length) throw new ConflictException({code:'REWORK_FINANCIALS_PENDING',
    message:'Nilai dan margin kloter rework belum tersedia. Laporan gabungan belum lengkap.',affectedLotIds:selected.map(r=>r.id)});
}

@Injectable()
export class ProductionRework {
  constructor(private readonly db: DatabaseService,private readonly inventory: SugarInventory,private readonly juice: JuiceRepository) {}

  enable(access: FactoryAccess, input: unknown) {
    return this.inventory.command(access,input,'enable-rework',async(tx,b,synthetic)=>{
      if(b.reportHandlingConfirmed!==true) throw new BadRequestException('Penanganan REWORK_FINANCIALS_PENDING pada laporan harus dikonfirmasi.');
      await tx.query('UPDATE sobatnira.production_inventory_state SET rework_enabled=true WHERE tenant_id=$1 AND factory_id=$2 AND is_synthetic=$3',[...keys(access),synthetic]);
      return {reworkEnabled:true,financialStatus:'REWORK_FINANCIALS_PENDING'};
    },['reportHandlingConfirmed']);
  }

  reserve(access: FactoryAccess, batchId: string,input: unknown) {
    return this.inventory.command(access,input,'rework-reserve:'+batchId,async(tx,b,synthetic)=>{
      const batch=found((await tx.query('SELECT * FROM sobatnira.production_batches WHERE tenant_id=$1 AND factory_id=$2 AND id=$3 FOR UPDATE',[...keys(access),batchId])).rows[0]);
      const enabled=(await tx.query('SELECT rework_enabled FROM sobatnira.production_inventory_state WHERE tenant_id=$1 AND factory_id=$2 AND is_synthetic=$3',[...keys(access),synthetic])).rows[0];
      if(!enabled?.rework_enabled || batch.status!=='draft' || batch.kind!=='rework' || batch.is_synthetic!==synthetic)
        throw new ConflictException('Rework belum aktif atau batch/kategori tidak sesuai.');
      await this.juice.lockLots(tx,access,[batch.lot_id]);
      const closed=await tx.query('SELECT 1 FROM sobatnira.lot_closures WHERE tenant_id=$1 AND factory_id=$2 AND lot_id=$3 AND is_synthetic=$4 AND reopened_at IS NULL',[...keys(access),batch.lot_id,synthetic]);
      if(closed.rows.length) throw new ConflictException('Kloter penerima sudah ditutup.');
      const source=await this.inventory.source(tx,access,uuid(b.sourceId),synthetic);
      await this.inventory.assertSourceOpen(tx,access,source);
      if(source.batch_id) {
        const producer=found((await tx.query('SELECT status,is_synthetic FROM sobatnira.production_batches WHERE tenant_id=$1 AND factory_id=$2 AND id=$3',[...keys(access),source.batch_id])).rows[0]);
        if(producer.status!=='approved' || producer.is_synthetic!==synthetic || source.batch_id===batchId)
          throw new ConflictException('Sumber rework harus batch sah yang berbeda.');
        const cycle=(await tx.query(`WITH RECURSIVE ancestors(id) AS (SELECT $1::uuid UNION
          SELECT s.batch_id FROM ancestors a JOIN sobatnira.production_rework_reservations r ON r.batch_id=a.id AND r.state<>'released'
          JOIN sobatnira.production_sugar_sources s ON s.id=r.source_id WHERE s.batch_id IS NOT NULL)
          SELECT 1 FROM ancestors WHERE id=$2`,[source.batch_id,batchId])).rows;
        if(cycle.length) throw new ConflictException('Hubungan rework melingkar.');
      }
      const amount=decimal(b.weightKg,'weightKg');units(amount);
      const update=await tx.query(`UPDATE sobatnira.production_sugar_sources SET reserved_kg=reserved_kg+$4::numeric
        WHERE tenant_id=$1 AND factory_id=$2 AND id=$3 AND on_hand_kg-reserved_kg >= $4::numeric RETURNING id`,[...keys(access),source.id,amount]);
      if(!update.rows.length) throw new ConflictException('Gula sumber tidak cukup atau sudah dipesan.');
      const result=(await tx.query(`INSERT INTO sobatnira.production_rework_reservations(tenant_id,factory_id,is_synthetic,request_id,batch_id,source_id,weight_kg,actor_id)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING request_id AS "requestId",source_id AS "sourceId",weight_kg::text AS "weightKg",state`,
        [...keys(access),synthetic,b.requestId,batchId,source.id,amount,access.userId])).rows[0];
      return result;
    },['sourceId','weightKg']);
  }

  async finalize(tx: DatabaseSession,access: FactoryAccess,batch: any,consume: boolean) {
    const reservations=(await tx.query(`SELECT r.* FROM sobatnira.production_rework_reservations r
      WHERE r.tenant_id=$1 AND r.factory_id=$2 AND r.batch_id=$3 AND r.state='reserved' ORDER BY r.source_id,r.request_id FOR UPDATE`,[...keys(access),batch.id])).rows;
    if(consume && batch.kind==='rework' && !reservations.length) throw new ConflictException('Lengkapi reservasi gula sumber rework.');
    if(batch.kind!=='rework' && reservations.length) throw new ConflictException('Batch biasa tidak dapat memakai gula rework.');
    for(const r of reservations) {
      const source=await this.inventory.source(tx,access,r.source_id,batch.is_synthetic);
      if(consume) await this.inventory.assertSourceOpen(tx,access,source);
      await tx.query('UPDATE sobatnira.production_sugar_sources SET reserved_kg=reserved_kg-$2::numeric WHERE id=$1',[source.id,String(r.weight_kg)]);
      if(consume) await this.inventory.change(tx,access,source.id,'-'+String(r.weight_kg),'rework',r.request_id,'Pemakaian gula pada batch '+batch.code);
      await tx.query("UPDATE sobatnira.production_rework_reservations SET state=$2,finalized_at=clock_timestamp() WHERE request_id=$1 AND tenant_id=$3 AND factory_id=$4",[r.request_id,consume?'consumed':'released',...keys(access)]);
    }
    if(reservations.length) await tx.query('UPDATE sobatnira.production_inventory_state SET version=version+1 WHERE tenant_id=$1 AND factory_id=$2 AND is_synthetic=$3',[...keys(access),batch.is_synthetic]);
  }

  async trace(access: FactoryAccess,batchId: string) {
    const batch=found((await this.db.query('SELECT * FROM sobatnira.production_batches WHERE tenant_id=$1 AND factory_id=$2 AND id=$3',[...keys(access),batchId])).rows[0]);
    const inputs=(await this.db.query(`SELECT r.request_id AS "requestId",r.source_id AS "sourceId",r.weight_kg::text AS "weightKg",r.state,
      s.batch_id AS "sourceBatchId",s.opening_request_id AS "openingRequestId",s.origin_lot_id AS "originLotId",s.grade_code AS "gradeCode",s.quality
      FROM sobatnira.production_rework_reservations r JOIN sobatnira.production_sugar_sources s ON s.id=r.source_id
      WHERE r.tenant_id=$1 AND r.factory_id=$2 AND r.batch_id=$3 ORDER BY r.created_at,r.request_id`,[...keys(access),batchId])).rows;
    const recipients=(await this.db.query(`SELECT r.batch_id AS "batchId",r.weight_kg::text AS "weightKg",r.state
      FROM sobatnira.production_rework_reservations r JOIN sobatnira.production_sugar_sources s ON s.id=r.source_id
      WHERE s.tenant_id=$1 AND s.factory_id=$2 AND s.batch_id=$3 AND r.state<>'released' ORDER BY r.batch_id`,[...keys(access),batchId])).rows;
    const used=sumDecimals(inputs.filter(r=>r.state==='consumed').map(r=>r.weightKg));
    const net=units(String(batch.physical_weight_kg))-units(used);
    const allocations=(await this.db.query(`SELECT event_id AS "eventId",version,origin_lot_id AS "originLotId",grade_code AS "gradeCode",weight_kg::text AS "weightKg"
      FROM sobatnira.production_output_allocations WHERE tenant_id=$1 AND factory_id=$2 AND batch_id=$3 ORDER BY version,origin_lot_id,grade_code`,[...keys(access),batchId])).rows;
    const juice=(await this.db.query(`SELECT r.request_id AS "requestId",r.origin_lot_id AS "originLotId",l.display_code AS "lotCode",r.quantity_ml::text AS "quantityMl",r.state
      FROM sobatnira.juice_reservations r JOIN sobatnira.lots l ON l.id=r.origin_lot_id
      WHERE r.tenant_id=$1 AND r.factory_id=$2 AND r.batch_id=$3 ORDER BY r.origin_lot_id,r.request_id`,[...keys(access),batchId])).rows;
    const corrections=(await this.db.query(`SELECT id,version,status,reason,before_data AS "before",proposed_data AS "after",created_at AS "createdAt",updated_at AS "updatedAt"
      FROM sobatnira.production_batch_corrections WHERE batch_id=$1 ORDER BY created_at,id`,[batchId])).rows;
    return {batchId,kind:batch.kind,status:batch.status,inputs,recipients,allocations,juice,corrections,
      source:batch.source_document_id?{documentId:batch.source_document_id,revisionId:batch.source_revision_id,block:batch.source_block,rowReference:batch.source_row}:null,
      masterReferences:batch.master_references,
      grossWeightKg:String(batch.physical_weight_kg),reusedWeightKg:used,netAdditionalKg:(net<0n?'-':'')+kilograms(net<0n?-net:net),
      financialStatus:(await reworkAffectedLots(this.db,access,batch.is_synthetic)).includes(batch.lot_id)?'REWORK_FINANCIALS_PENDING':'available'};
  }
}

@Controller('tenants/:tenantId/factories/:factoryId/production')
@FactoryRoles('admin','owner')
export class ProductionReworkController {
  constructor(private readonly rework: ProductionRework) {}
  @Post('sugar/rework-enablement') @FactoryRoles('admin') enable(@CurrentFactory() a:FactoryAccess,@Body() b:unknown) { return this.rework.enable(a,b); }
  @Post('batches/:id/rework-inputs') @FactoryRoles('admin') reserve(@CurrentFactory() a:FactoryAccess,@Param('id') id:string,@Body() b:unknown) { return this.rework.reserve(a,uuid(id),b); }
  @Get('batches/:id/traceability') trace(@CurrentFactory() a:FactoryAccess,@Param('id') id:string) { return this.rework.trace(a,uuid(id)); }
}
