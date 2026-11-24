const {mkdir,writeFile}=require('node:fs/promises');
const {resolve}=require('node:path');
const {performance}=require('node:perf_hooks');
const {reportFixture}=require('../test/integration/report-fixture.cjs');
async function main(){
 const url=new URL(process.env.PERF_DATABASE_URL??'');
 if(!['postgres:','postgresql:'].includes(url.protocol)||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||
   !/^\/sobatnira_perf_[a-z0-9_]+$/.test(url.pathname))throw Error('Use a disposable local sobatnira_perf_* database.');
 const lots=Number(process.env.PERF_REPORT_LOTS??30);
 if(!Number.isInteger(lots)||lots<3||lots>100)throw Error('PERF_REPORT_LOTS must be 3..100');
 process.env.DATABASE_URL=url.href;process.env.NODE_ENV='test';
 process.env.DOCUMENT_WORKER_ENABLED='false';process.env.REPORT_EXPORT_ENABLED='false';
 const f=await reportFixture(lots);
 try{
  const original=f.client.query.bind(f.client);let captured=[],record=false;
  f.client.query=(sql,args)=>{if(record&&typeof sql==='string'&&/^WITH /.test(sql))captured.push({sql,args});return original(sql,args);};
  const results=[];
  for(const [name,query] of [['full',{}],['summary',{view:'summary'}],['page',{view:'page',limit:'20'}]]){
   const elapsed=[];let report;
   for(let i=0;i<5;i++){captured=[];record=true;const start=performance.now();report=await f.batches.productionReport(f.access,query);elapsed.push(performance.now()-start);record=false;}
   const plans=[];
   for(const {sql,args} of captured)plans.push((await original('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '+sql,args)).rows[0]['QUERY PLAN'][0]);
   const medianMs=[...elapsed].sort((a,b)=>a-b)[2];
   results.push({name,medianMs,elapsed,responseBytes:Buffer.byteLength(JSON.stringify(report)),totals:report.totals,plans});
  }
  const directory=resolve(__dirname,'../../../.tmp/performance');await mkdir(directory,{recursive:true});
  await writeFile(resolve(directory,'reports-query-profile.json'),JSON.stringify({synthetic:true,lots,batches:lots*4,
    gradeRows:lots*4,distinctGrades:2,snapshots:lots*5,note:'Five warm single-client samples; seed uses domain services, alternating grades, fractional weights, negative margins and approved corrections. All rows rolled back.',results},null,2));
  for(const r of results)console.log(`${r.name}: ${r.medianMs.toFixed(3)} ms; ${r.responseBytes} bytes`);
 }finally{await f.close();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
