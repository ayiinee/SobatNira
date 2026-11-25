import { BadRequestException, Body, ConflictException, Controller, Get, Injectable, Param, Post, Query } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { JuiceRepository } from '../juice/juice.repository';
import { allocate, kilograms, units } from './allocation';
import { decimal } from './decimal';
import { found, object, parsePage, scopeValues, text, uuid } from './production.dto';

export const INVENTORY_LIMITATION = 'Pengeluaran selain rework belum dicatat. Saldo ini bukan stok gudang lengkap setelah pengiriman.';
const keys = (a: FactoryAccess) => [a.tenantId,a.factoryId];
export function category(value: unknown) {
  if (value !== undefined && typeof value !== 'boolean') throw new BadRequestException('synthetic harus boolean.');
  return value === true;
}
function version(value: unknown) {
  if (!Number.isSafeInteger(value) || Number(value)<0) throw new BadRequestException('Versi tidak valid.');
  return Number(value);
}
function weight(value: unknown, zero=false) { const v=decimal(value,'weightKg',zero); units(v); return v; }
function quality(value: unknown) {
  if (value !== 'good' && value !== 'failed') throw new BadRequestException('Kualitas harus good atau failed.');
  return value;
}

@Injectable()
export class SugarInventory {
  constructor(private readonly db: DatabaseService, private readonly juice: JuiceRepository) {}

  async read(access: FactoryAccess, synthetic: boolean) {
    const scope=[...scopeValues(access),synthetic];
    const state=(await this.db.query(`WITH ${FACTORY_SCOPE_CTE} SELECT i.* FROM sobatnira.production_inventory_state i
      JOIN authorized_scope a ON (a."tenantId",a."factoryId")=(i.tenant_id,i.factory_id) WHERE i.is_synthetic=$4`,scope)).rows[0];
    const sources=(await this.db.query(`WITH ${FACTORY_SCOPE_CTE} SELECT s.id,s.batch_id AS "batchId",
      s.origin_lot_id AS "originLotId",l.display_code AS "lotCode",s.grade_code AS "gradeCode",s.quality,
      trim_scale(s.on_hand_kg)::text AS "onHandKg",trim_scale(s.reserved_kg)::text AS "reservedKg",
      trim_scale(s.on_hand_kg-s.reserved_kg)::text AS "availableKg",s.opening_request_id AS "openingRequestId"
      FROM sobatnira.production_sugar_sources s JOIN authorized_scope a
        ON (a."tenantId",a."factoryId")=(s.tenant_id,s.factory_id)
      LEFT JOIN sobatnira.lots l ON (l.tenant_id,l.factory_id,l.id)=(s.tenant_id,s.factory_id,s.origin_lot_id)
      WHERE s.is_synthetic=$4 ORDER BY s.grade_code,s.quality,s.id`,scope)).rows;
    return {active:!!state,version:state?.version ?? 0,activatedAt:state?.activated_at ?? null,
      synthetic,limitation:INVENTORY_LIMITATION,sources};
  }

  async history(access: FactoryAccess, query: unknown) {
    const q=object(query,['synthetic','limit','offset']);
    const synthetic=q.synthetic === 'true';
    if(q.synthetic!==undefined && !['true','false'].includes(String(q.synthetic))) throw new BadRequestException('synthetic tidak valid.');
    const page=parsePage({limit:q.limit,offset:q.offset});
    const items=(await this.db.query(`WITH ${FACTORY_SCOPE_CTE} SELECT e.id,e.source_id AS "sourceId",
      trim_scale(e.quantity_delta_kg)::text AS "quantityDeltaKg",e.kind,e.event_id AS "eventId",
      e.actor_id AS "actorId",e.reason,e.created_at AS "createdAt",s.grade_code AS "gradeCode",s.quality
      FROM sobatnira.production_sugar_entries e JOIN sobatnira.production_sugar_sources s ON s.id=e.source_id
      JOIN authorized_scope a ON (a."tenantId",a."factoryId")=(e.tenant_id,e.factory_id)
      WHERE s.is_synthetic=$4 ORDER BY e.created_at DESC,e.id LIMIT $5 OFFSET $6`,
      [...scopeValues(access),synthetic,page.limit,page.offset])).rows;
    return {items,...page};
  }

  async command(access: FactoryAccess, input: unknown, kind: string,
    work: (tx: DatabaseSession,b: Record<string,unknown>,synthetic: boolean)=>Promise<unknown>, fields: string[]) {
    const b=object(input,['requestId','version','reason','synthetic',...fields]);
    const requestId=uuid(b.requestId), synthetic=category(b.synthetic), expected=version(b.version);
    const reason=text(b.reason,'reason',500);
    const canonical=(v: any): any => Array.isArray(v) ? v.map(canonical) : v && typeof v==='object'
      ? Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])) : v;
    const hash=createHash('sha256').update(JSON.stringify(canonical({kind,...b,synthetic}))).digest('hex');
    return this.juice.mutate(access,async tx=>{
      const previous=(await tx.query('SELECT input_hash,result FROM sobatnira.production_inventory_requests WHERE tenant_id=$1 AND factory_id=$2 AND request_id=$3',[...keys(access),requestId])).rows[0];
      if(previous) {
        if(previous.input_hash!==hash) throw new ConflictException('ID permintaan digunakan untuk isi berbeda.');
        return previous.result;
      }
      const state=(await tx.query('SELECT * FROM sobatnira.production_inventory_state WHERE tenant_id=$1 AND factory_id=$2 AND is_synthetic=$3 FOR UPDATE',[...keys(access),synthetic])).rows[0];
      if((state?.version ?? 0)!==expected) throw new ConflictException('Stok sudah berubah. Muat ulang saldo.');
      if(kind!=='opening' && !state) throw new ConflictException('Saldo awal belum diaktifkan.');
      const result=await work(tx,{...b,reason,requestId},synthetic);
      const next=(await tx.query('UPDATE sobatnira.production_inventory_state SET version=version+1 WHERE tenant_id=$1 AND factory_id=$2 AND is_synthetic=$3 RETURNING version',[...keys(access),synthetic])).rows[0];
      const receipt={requestId,version:next.version,result};
      await tx.query(`INSERT INTO sobatnira.production_inventory_requests(tenant_id,factory_id,is_synthetic,request_id,input_hash,result,actor_id,reason)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,[...keys(access),synthetic,requestId,hash,receipt,access.userId,reason]);
      return receipt;
    });
  }

  opening(access: FactoryAccess, input: unknown) {
    return this.command(access,input,'opening',async(tx,b,synthetic)=>{
      if(b.version!==0) throw new ConflictException('Saldo awal hanya dapat dicatat satu kali. Gunakan penyesuaian.');
      if(!Array.isArray(b.items) || b.items.length>100) throw new BadRequestException('Saldo awal harus berupa daftar maksimum 100 sumber.');
      await tx.query('INSERT INTO sobatnira.production_inventory_state(tenant_id,factory_id,is_synthetic) VALUES($1,$2,$3)',[...keys(access),synthetic]);
      const ids=[];
      for(const item of b.items) {
        const row=object(item,['gradeCode','quality','weightKg','batchId','originLotId']);
        const grade=text(row.gradeCode,'gradeCode',40), q=quality(row.quality), amount=weight(row.weightKg);
        const batch=row.batchId===undefined ? null : uuid(row.batchId);
        const origin=row.originLotId===undefined ? null : uuid(row.originLotId);
        if(batch) {
          const old=found((await tx.query('SELECT status,is_synthetic,approved_at FROM sobatnira.production_batches WHERE tenant_id=$1 AND factory_id=$2 AND id=$3',[...keys(access),batch])).rows[0]);
          if(old.status!=='approved' || old.is_synthetic!==synthetic) throw new ConflictException('Batch saldo awal belum sah atau kategori berbeda.');
        }
        if(origin) await this.juice.lockLots(tx,access,[origin]);
        const source=(await tx.query(`INSERT INTO sobatnira.production_sugar_sources(tenant_id,factory_id,is_synthetic,batch_id,origin_lot_id,grade_code,quality,opening_request_id)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,[...keys(access),synthetic,batch,origin,grade,q,b.requestId])).rows[0];
        await this.change(tx,access,source.id,amount,'opening',String(b.requestId),String(b.reason));ids.push(source.id);
      }
      return {sourceIds:ids};
    },['items']);
  }

  async source(tx: DatabaseSession, access: FactoryAccess, id: string, synthetic: boolean) {
    return found((await tx.query(`SELECT * FROM sobatnira.production_sugar_sources WHERE tenant_id=$1 AND factory_id=$2 AND id=$3 AND is_synthetic=$4 FOR UPDATE`,[...keys(access),id,synthetic])).rows[0]);
  }

  async assertSourceOpen(tx: DatabaseSession, access: FactoryAccess, source: any) {
    const closed=await tx.query(`SELECT 1 FROM sobatnira.lot_closures c WHERE c.tenant_id=$1 AND c.factory_id=$2 AND c.is_synthetic=$3
      AND c.reopened_at IS NULL AND (c.lot_id=$4 OR c.lot_id IN (SELECT lot_id FROM sobatnira.production_batches WHERE id=$5))`,
      [...keys(access),source.is_synthetic,source.origin_lot_id,source.batch_id]);
    if(closed.rows.length) throw new ConflictException('Buka kembali kloter sumber sebelum memakai atau mengubah stok.');
  }

  async change(tx: DatabaseSession, access: FactoryAccess, sourceId: string, delta: string,
    kind: string,eventId: string,reason: string) {
    const changed=await tx.query(`UPDATE sobatnira.production_sugar_sources SET on_hand_kg=on_hand_kg+$4::numeric
      WHERE tenant_id=$1 AND factory_id=$2 AND id=$3 AND on_hand_kg+$4::numeric>=reserved_kg RETURNING id`,[...keys(access),sourceId,delta]);
    if(!changed.rows.length) throw new ConflictException('Stok tidak cukup atau sudah dipesan.');
    await tx.query(`INSERT INTO sobatnira.production_sugar_entries(tenant_id,factory_id,source_id,quantity_delta_kg,kind,event_id,actor_id,reason)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,[...keys(access),sourceId,delta,kind,eventId,access.userId,reason]);
  }

  adjust(access: FactoryAccess, input: unknown, transferQuality=false) {
    return this.command(access,input,transferQuality?'quality':'adjustment',async(tx,b,synthetic)=>{
      const source=await this.source(tx,access,uuid(b.sourceId),synthetic);
      await this.assertSourceOpen(tx,access,source);
      const amount=weight(b.weightKg);
      if(transferQuality) {
        const destination=quality(b.quality);
        if(source.quality===destination) throw new BadRequestException('Kualitas tujuan harus berbeda.');
        await this.change(tx,access,source.id,'-'+amount,'quality',String(b.requestId),String(b.reason));
        const target=(await tx.query(`INSERT INTO sobatnira.production_sugar_sources(tenant_id,factory_id,is_synthetic,batch_id,origin_lot_id,grade_code,quality,opening_request_id)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(tenant_id,factory_id,is_synthetic,batch_id,origin_lot_id,grade_code,quality)
          DO UPDATE SET grade_code=EXCLUDED.grade_code RETURNING id`,[...keys(access),synthetic,source.batch_id,source.origin_lot_id,source.grade_code,destination,source.opening_request_id])).rows[0];
        await this.change(tx,access,target.id,amount,'quality',String(b.requestId),String(b.reason));
        return {sourceId:source.id,targetId:target.id};
      }
      if(b.direction!=='add' && b.direction!=='subtract') throw new BadRequestException('direction harus add atau subtract.');
      await this.change(tx,access,source.id,(b.direction==='subtract'?'-':'')+amount,'adjustment',String(b.requestId),String(b.reason));
      return {sourceId:source.id};
    },transferQuality?['sourceId','weightKg','quality']:['sourceId','weightKg','direction']);
  }

  async postBatch(tx: DatabaseSession, access: FactoryAccess, batch: any, eventId: string, correction=false) {
    const state=(await tx.query('SELECT * FROM sobatnira.production_inventory_state WHERE tenant_id=$1 AND factory_id=$2 AND is_synthetic=$3 FOR UPDATE',[...keys(access),batch.is_synthetic])).rows[0];
    if(!state || new Date(batch.approved_at)<new Date(state.activated_at)) return;
    // A pre-activation source is never implicitly backfilled by a later correction.
    if(correction && !(await tx.query("SELECT 1 FROM sobatnira.production_sugar_entries e JOIN sobatnira.production_sugar_sources s ON s.id=e.source_id WHERE s.batch_id=$1 AND e.kind='production'",[batch.id])).rows.length) return;
    const grades=(await tx.query('SELECT code,weight_kg::text AS weight FROM sobatnira.batch_grade_results WHERE batch_id=$1 ORDER BY code',[batch.id])).rows;
    const shares=(await tx.query<{id:string;quantity:string}>(`SELECT origin_lot_id AS id,sum(quantity_ml)::text AS quantity FROM sobatnira.juice_reservations
      WHERE tenant_id=$1 AND factory_id=$2 AND batch_id=$3 AND state='consumed' GROUP BY origin_lot_id ORDER BY origin_lot_id`,[...keys(access),batch.id])).rows;
    const desired=new Map<string,{grade:string,origin:string,amount:bigint}>();
    for(const grade of grades) for(const [origin,amount] of allocate(units(grade.weight),shares)) {
      desired.set(origin+'/'+grade.code,{grade:grade.code,origin,amount});
      await tx.query(`INSERT INTO sobatnira.production_output_allocations(tenant_id,factory_id,batch_id,event_id,version,origin_lot_id,grade_code,weight_kg)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,[...keys(access),batch.id,eventId,state.version+1,origin,grade.code,kilograms(amount)]);
    }
    const old=(await tx.query(`SELECT s.id,s.origin_lot_id,s.grade_code,COALESCE(sum(e.quantity_delta_kg) FILTER(WHERE e.kind IN ('production','correction')),0)::text AS credited
      FROM sobatnira.production_sugar_sources s LEFT JOIN sobatnira.production_sugar_entries e ON e.source_id=s.id
      WHERE s.tenant_id=$1 AND s.factory_id=$2 AND s.batch_id=$3 AND s.opening_request_id IS NULL AND s.quality='good'
      GROUP BY s.id`,[...keys(access),batch.id])).rows;
    for(const source of old) if(!desired.has(source.origin_lot_id+'/'+source.grade_code)) desired.set(source.origin_lot_id+'/'+source.grade_code,{origin:source.origin_lot_id,grade:source.grade_code,amount:0n});
    for(const item of desired.values()) {
      const previous=old.find(s=>s.origin_lot_id===item.origin && s.grade_code===item.grade);
      const delta=item.amount-units(previous?.credited ?? '0');
      if(!delta) continue;
      const source=previous ?? (await tx.query(`INSERT INTO sobatnira.production_sugar_sources(tenant_id,factory_id,is_synthetic,batch_id,origin_lot_id,grade_code,quality)
        VALUES($1,$2,$3,$4,$5,$6,'good') RETURNING id`,[...keys(access),batch.is_synthetic,batch.id,item.origin,item.grade])).rows[0];
      await this.change(tx,access,source.id,(delta<0n?'-':'')+kilograms(delta<0n?-delta:delta),correction?'correction':'production',eventId,correction?'Koreksi hasil batch':'Pengesahan hasil batch');
    }
    await tx.query('UPDATE sobatnira.production_inventory_state SET version=version+1 WHERE tenant_id=$1 AND factory_id=$2 AND is_synthetic=$3',[...keys(access),batch.is_synthetic]);
  }
}

@Controller('tenants/:tenantId/factories/:factoryId/production/sugar')
@FactoryRoles('admin','owner')
export class SugarInventoryController {
  constructor(private readonly inventory: SugarInventory) {}
  @Get() read(@CurrentFactory() a: FactoryAccess,@Query() query: unknown) {
    const q=object(query,['synthetic']);
    if(q.synthetic!==undefined && !['true','false'].includes(String(q.synthetic))) throw new BadRequestException('synthetic tidak valid.');
    return this.inventory.read(a,q.synthetic==='true');
  }
  @Get('history') history(@CurrentFactory() a: FactoryAccess,@Query() q: unknown) { return this.inventory.history(a,q); }
  @Post('opening') @FactoryRoles('admin') opening(@CurrentFactory() a: FactoryAccess,@Body() b: unknown) { return this.inventory.opening(a,b); }
  @Post('adjustments') @FactoryRoles('admin') adjust(@CurrentFactory() a: FactoryAccess,@Body() b: unknown) { return this.inventory.adjust(a,b); }
  @Post('quality') @FactoryRoles('admin') quality(@CurrentFactory() a: FactoryAccess,@Body() b: unknown) { return this.inventory.adjust(a,b,true); }
}
