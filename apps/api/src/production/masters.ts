import { BadRequestException, Body, ConflictException, Controller, Get, Injectable, Post, Query } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { FactoryAccess } from '../auth/auth.types';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { JuiceRepository } from '../juice/juice.repository';
import { decimal } from './decimal';
import { object, scopeValues, text, uuid } from './production.dto';

export function parseMasterReferences(input: unknown) {
  if(input===undefined) return null;
  const b=object(input,['wok','grades']);
  const ref=(value: unknown)=>{const r=object(value,['code','version']);
    if(!Number.isSafeInteger(r.version) || Number(r.version)<1) throw new BadRequestException('Versi master tidak valid.');
    return {code:text(r.code,'code',40),version:Number(r.version)};};
  if(!Array.isArray(b.grades) || b.grades.length>100) throw new BadRequestException('Referensi grade tidak valid.');
  return {wok:ref(b.wok),grades:b.grades.map(ref).sort((a,b)=>a.code.localeCompare(b.code))};
}
export async function assertMasterReferences(tx: DatabaseSession,a: FactoryAccess,b: {masterReferences: ReturnType<typeof parseMasterReferences>;wokNumber:number;grades:{code:string}[]}) {
  const refs=b.masterReferences;if(!refs) return;
  if(refs.wok.code!==String(b.wokNumber) || refs.grades.length!==b.grades.length || new Set(refs.grades.map(r=>r.code)).size!==refs.grades.length || b.grades.some(g=>!refs.grades.some(r=>r.code===g.code))) throw new BadRequestException('Referensi master tidak sesuai batch.');
  const entries: [string,{code:string;version:number}][]=[['wok',refs.wok],...refs.grades.map(r=>['grade',r] as [string,typeof r])];
  for(const [kind,r] of entries) {
    const row=(await tx.query(`SELECT version,active FROM sobatnira.production_master_versions WHERE tenant_id=$1 AND factory_id=$2 AND kind=$3 AND code=$4 ORDER BY version DESC LIMIT 1`,[a.tenantId,a.factoryId,kind,r.code])).rows[0];
    if(!row?.active || row.version!==r.version) throw new ConflictException('Master berubah atau nonaktif. Muat ulang pilihan.');
  }
}
@Injectable()
export class ProductionMasters {
  constructor(private readonly db:DatabaseService,private readonly juice:JuiceRepository) {}
  async read(a:FactoryAccess,query:unknown) {
    const q=object(query,['history','synthetic']);
    if(q.history!==undefined && !['true','false'].includes(String(q.history)) || q.synthetic!==undefined && !['true','false'].includes(String(q.synthetic))) throw new BadRequestException('Parameter master tidak valid.');
    const rows=(await this.db.query(`WITH ${FACTORY_SCOPE_CTE}, versions AS (
      SELECT m.*,row_number() OVER(PARTITION BY kind,code ORDER BY version DESC) AS rank
      FROM sobatnira.production_master_versions m JOIN authorized_scope a ON (a."tenantId",a."factoryId")=(m.tenant_id,m.factory_id))
      SELECT kind,code,version,name,capacity_liters::text AS "capacityLiters",active,reason,actor_id AS "actorId",created_at AS "createdAt"
      FROM versions WHERE ($4::boolean OR rank=1) ORDER BY kind,code,version DESC`,[...scopeValues(a),q.history==='true'])).rows;
    const usage=(await this.db.query(`WITH ${FACTORY_SCOPE_CTE} SELECT b.wok_number AS "wokNumber",count(DISTINCT b.id)::int AS "batchCount"
      FROM sobatnira.production_batches b JOIN authorized_scope a ON (a."tenantId",a."factoryId")=(b.tenant_id,b.factory_id)
      WHERE b.status='approved' AND b.is_synthetic=$4 GROUP BY b.wok_number ORDER BY b.wok_number`,[...scopeValues(a),q.synthetic==='true'])).rows;
    return {items:rows,usage};
  }
  async save(a:FactoryAccess,input:unknown) {
    const b=object(input,['requestId','kind','code','version','name','capacityLiters','active','reason']);
    const requestId=uuid(b.requestId),kind=b.kind;
    if(kind!=='wok' && kind!=='grade') throw new BadRequestException('Jenis master tidak valid.');
    const code=text(b.code,'code',40),name=text(b.name,'name',100),reason=text(b.reason,'reason',500);
    if(!Number.isSafeInteger(b.version) || Number(b.version)<0 || typeof b.active!=='boolean') throw new BadRequestException('Versi atau status master tidak valid.');
    if(kind==='wok' && (!/^[1-9]\d{0,4}$/.test(code) || Number(code)>10000)) throw new BadRequestException('Nomor wajan tidak valid.');
    if(kind==='grade' && b.capacityLiters!==undefined && b.capacityLiters!==null) throw new BadRequestException('Grade tidak memiliki kapasitas.');
    const capacity=kind==='wok'?decimal(b.capacityLiters,'capacityLiters'):null;
    const data={kind,code,name,version:Number(b.version),active:b.active,capacityLiters:capacity,reason};
    const hash=createHash('sha256').update(JSON.stringify(data)).digest('hex');
    return this.juice.mutate(a,async tx=>{
      const scope=[a.tenantId,a.factoryId];
      const old=(await tx.query('SELECT input_hash,result FROM sobatnira.production_master_requests WHERE tenant_id=$1 AND factory_id=$2 AND request_id=$3',[...scope,requestId])).rows[0];
      if(old) {if(old.input_hash!==hash) throw new ConflictException('ID permintaan digunakan untuk isi berbeda.');return old.result;}
      const current=(await tx.query('SELECT version FROM sobatnira.production_master_versions WHERE tenant_id=$1 AND factory_id=$2 AND kind=$3 AND code=$4 ORDER BY version DESC LIMIT 1',[...scope,kind,code])).rows[0];
      if((current?.version??0)!==data.version) throw new ConflictException('Versi master sudah berubah.');
      const result={...data,version:data.version+1};
      await tx.query(`INSERT INTO sobatnira.production_master_versions(tenant_id,factory_id,kind,code,version,name,capacity_liters,active,actor_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,[...scope,kind,code,result.version,name,capacity,b.active,a.userId,reason]);
      await tx.query('INSERT INTO sobatnira.production_master_requests VALUES($1,$2,$3,$4,$5)',[...scope,requestId,hash,result]);
      return result;
    });
  }
}
@Controller('tenants/:tenantId/factories/:factoryId/production/masters')
@FactoryRoles('admin','owner')
export class ProductionMastersController {
  constructor(private readonly masters:ProductionMasters) {}
  @Get() read(@CurrentFactory() a:FactoryAccess,@Query() q:unknown) {return this.masters.read(a,q);}
  @Post() @FactoryRoles('admin') save(@CurrentFactory() a:FactoryAccess,@Body() b:unknown) {return this.masters.save(a,b);}
}
