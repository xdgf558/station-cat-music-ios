import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync,statSync,fsyncSync,openSync,closeSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:http';
import {spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {startRuntimeDiagnostics,routeLabel} from './probe_runtime_diagnostics.mjs';

test('fixed labels never include dynamic URLs or query strings',()=>{
 const routes=new Map([['/fixture/prepare','prepare'],['/fixture/seed','seed'],['/fixture/evidence','evidence'],
  ['/request','request'],['/fixture/bootstrap','bootstrap'],['/api/mobile/v1/config','config'],
  ['/api/mobile/v1/auth/refresh','refresh'],['/api/mobile/v1/music/catalog','catalog'],
  ['/api/mobile/v1/music/featured','featured'],['/fixture/featured','fixture_featured'],
  ['/fixture/featured-clear','fixture_featured_clear'],
  ...['revoke','rotation','rotation-evidence','stability','stability/limited','stability/expiry','stability/revoke']
   .map(route=>['/fixture/'+route,'fixture'])]);
 for(const [path,label] of routes)assert.equal(routeLabel(path+'?secret=not-for-logs'),label);
 for(const path of ['/private-secret','/fixture/private-secret','/api/mobile/v1/music/tracks/private-secret/playback-grants',
  '/api/mobile/v1/music/catalog/private-secret','https://user:password@private/api/mobile/v1/music/catalog',null,{}])assert.equal(routeLabel(path),'other');
});
test('real HTTP and blocked event loop yield bounded numeric diagnostics, not secrets',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'runtime-diagnostic-')),path=join(dir,'runtime.jsonl');
 const stop=startRuntimeDiagnostics(path,{interval:20});
 const server=createServer((req,res)=>{res.writeHead(200,{'X-Secret':'server-private'});res.end('body-private');});
 try{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  for(const path of ['/fixture/evidence','/api/mobile/v1/music/catalog','/api/mobile/v1/music/featured','/fixture/featured','/request','/fixture/bootstrap','/api/mobile/v1/config']){
   const result=await fetch(`http://127.0.0.1:${server.address().port}${path}?secret=query-private`,{
    headers:{Authorization:'header-private'},...(path==='/request'?{method:'POST',body:'request-body-private'}:{})});
   assert.equal(await result.text(),'body-private');
  }
  await delay(25);
  const until=performance.now()+120;while(performance.now()<until){} // diagnostic-only controlled stall
  await delay(25);stop();
  const text=readFileSync(path,'utf8'),rows=text.trim().split('\n').map(JSON.parse);
  for(const secret of ['query-private','header-private','body-private','request-body-private','server-private','127.0.0.1','Authorization','/api/','/fixture/'])assert.ok(!text.includes(secret));
  for(const route of ['evidence','catalog','featured','fixture_featured','request','bootstrap','config']){
   for(const event of ['http_in_start','http_in_finish','worker_http_start','worker_http_sent','worker_http_headers','worker_http_finish']){
    assert.ok(rows.some(row=>row.event===event&&row.route===route),event+' '+route);
   }
  }
  assert.ok(rows.filter(row=>['http_in_finish','worker_http_headers'].includes(row.event)).every(row=>row.status===200));
  assert.ok(rows.some(row=>row.event==='heartbeat'&&row.lagMs>=80));
  assert.equal(statSync(path).mode&0o777,0o600);
  const allowed=new Set(['sequence','at','elapsedMs','event','id','route','status','lagMs','cpuUserMs','cpuSystemMs','durationMs','unlabelledIncoming','unlabelledOutgoing']);
  for(const row of rows){
   assert.ok(Object.keys(row).every(key=>allowed.has(key)));
   if(row.route!==undefined)assert.ok(['evidence','catalog','featured','fixture_featured','request','bootstrap','config'].includes(row.route));
  }
 }finally{stop();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));rmSync(dir,{recursive:true,force:true});}
});
test('failed Worker HTTP requests retain only their fixed route and numeric ID',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'runtime-failure-')),path=join(dir,'runtime.jsonl');
 const stop=startRuntimeDiagnostics(path);
 const server=createServer((req)=>req.socket.destroy());
 try{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  await assert.rejects(fetch(`http://127.0.0.1:${server.address().port}/api/mobile/v1/music/featured?secret=failure-private`,{headers:{Authorization:'credential-private'}}));
  stop();
  const text=readFileSync(path,'utf8'),rows=text.trim().split('\n').map(JSON.parse);
  const failure=rows.find(row=>row.event==='worker_http_error'&&row.route==='featured');
  assert.ok(failure);assert.equal(typeof failure.id,'number');
  assert.ok(rows.some(row=>row.event==='worker_http_start'&&row.id===failure.id&&row.route==='featured'));
  for(const secret of ['failure-private','credential-private','127.0.0.1','/api/','socket','UND_ERR'])assert.ok(!text.includes(secret));
 }finally{stop();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));rmSync(dir,{recursive:true,force:true});}
});
test('production, media and recovery preloads retain private diagnostics on process failure',()=>{
 const dir=mkdtempSync(join(tmpdir(),'runtime-preload-'));
 try{
  for(const name of ['M2_RUNTIME_DIAGNOSTICS_FILE','M3_RUNTIME_DIAGNOSTICS_FILE','PRODUCTION_RUNTIME_DIAGNOSTICS_FILE']){
   const path=join(dir,name+'.jsonl');
   const runId=randomUUID();
   const env={...process.env,M2_RUNTIME_DIAGNOSTICS_FILE:'',M3_RUNTIME_DIAGNOSTICS_FILE:'',PRODUCTION_RUNTIME_DIAGNOSTICS_FILE:'',
    PRODUCTION_RUNTIME_DIAGNOSTICS_RUN_ID:runId,[name]:path};
   const result=spawnSync(process.execPath,['--import',fileURLToPath(new URL('./probe_runtime_diagnostics.mjs',import.meta.url)),
    '-e','process.exit(23)'],{env,encoding:'utf8',timeout:10000});
   assert.equal(result.status,23,result.stderr);
   assert.equal(statSync(path).mode&0o777,0o600);
   const rows=readFileSync(path,'utf8').trim().split('\n').map(JSON.parse);
   assert.deepEqual(rows.map(row=>row.event),['observer_started','observer_stopped']);
   assert.ok(rows.every(row=>name==='PRODUCTION_RUNTIME_DIAGNOSTICS_FILE'?row.runId===runId:row.runId===undefined));
  }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
test('standard generated UUIDs are accepted and kept on every diagnostic row',()=>{
 const dir=mkdtempSync(join(tmpdir(),'runtime-standard-uuid-')),path=join(dir,'runtime.jsonl');
 try{
  const runId=randomUUID();
  const stop=startRuntimeDiagnostics(path,{runId});stop();
  const rows=readFileSync(path,'utf8').trim().split('\n').map(JSON.parse);
  assert.deepEqual(rows.map(row=>row.event),['observer_started','observer_stopped']);
  assert.ok(rows.every(row=>row.runId===runId));
 }finally{rmSync(dir,{recursive:true,force:true});}
});
test('run IDs cannot inject arbitrary diagnostic text',()=>{
 const dir=mkdtempSync(join(tmpdir(),'runtime-run-id-')),path=join(dir,'runtime.jsonl');
 try{
  for(const runId of ['private-value','11111111-2222-4333-555555555555',
   '11111111-2222-4333-8444-5555-55555555',123,{}, {toString:()=> '11111111-2222-4333-8444-555555555555'}]){
   assert.throws(()=>{const stop=startRuntimeDiagnostics(path,{runId});stop();},{message:'INVALID_DIAGNOSTIC_RUN_ID'});
  }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
test('diagnostics budget is finite and stopping restores fsync',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'runtime-budget-')),path=join(dir,'runtime.jsonl');
 try{
  const stop=startRuntimeDiagnostics(path,{interval:1,budget:512});await delay(20);stop();stop();
  assert.ok(statSync(path).size<=512);
  const fd=openSync(join(dir,'plain'),'w');fsyncSync(fd);closeSync(fd);
 }finally{rmSync(dir,{recursive:true,force:true});}
});

test('unlabelled startup traffic cannot consume the request diagnostics budget',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'runtime-startup-')),path=join(dir,'runtime.jsonl');
 const stop=startRuntimeDiagnostics(path,{interval:10000,budget:16384});
 const server=createServer((req,res)=>{res.writeHead(200);res.end('private-body');});
 try{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  for(let index=0;index<400;index++){
   const result=await fetch(base+'/private-startup?credential=private');await result.text();
  }
  for(const route of ['/request','/api/mobile/v1/config']){const result=await fetch(base+route);await result.text();}
  stop();
  const text=readFileSync(path,'utf8'),rows=text.trim().split('\n').map(JSON.parse);
  for(const route of ['request','config']){
   assert.ok(rows.some(row=>row.event==='http_in_finish'&&row.route===route&&row.status===200));
   assert.ok(rows.some(row=>row.event==='worker_http_finish'&&row.route===route));
  }
  assert.ok(!rows.some(row=>row.route==='other'));
  const last=rows.at(-1);assert.equal(last.event,'observer_stopped');
  assert.equal(last.unlabelledIncoming,400);assert.equal(last.unlabelledOutgoing,400);
  assert.ok(statSync(path).size<8192);
  for(const secret of ['private-startup','credential','private-body','127.0.0.1'])assert.ok(!text.includes(secret));
 }finally{stop();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));rmSync(dir,{recursive:true,force:true});}
});
