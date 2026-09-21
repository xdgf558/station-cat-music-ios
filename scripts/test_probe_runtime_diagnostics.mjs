import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync,statSync,fsyncSync,openSync,closeSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:http';
import {setTimeout as delay} from 'node:timers/promises';
import {startRuntimeDiagnostics,routeLabel} from './probe_runtime_diagnostics.mjs';

test('fixed labels never include dynamic URLs or query strings',()=>{
 assert.equal(routeLabel('/fixture/seed?secret=not-for-logs'),'seed');
 assert.equal(routeLabel('/private-secret'),'other');assert.equal(routeLabel(null),'other');
});
test('real HTTP and blocked event loop yield bounded numeric diagnostics, not secrets',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'runtime-diagnostic-')),path=join(dir,'runtime.jsonl');
 const stop=startRuntimeDiagnostics(path,{interval:20});
 const server=createServer((req,res)=>{res.writeHead(200,{'X-Secret':'server-private'});res.end('body-private');});
 try{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const result=await fetch(`http://127.0.0.1:${server.address().port}/fixture/evidence?secret=query-private`,{headers:{Authorization:'header-private'}});
  assert.equal(await result.text(),'body-private');
  await delay(25);
  const until=performance.now()+120;while(performance.now()<until){} // diagnostic-only controlled stall
  await delay(25);stop();
  const text=readFileSync(path,'utf8'),rows=text.trim().split('\n').map(JSON.parse);
  for(const secret of ['query-private','header-private','body-private','server-private','127.0.0.1','Authorization'])assert.ok(!text.includes(secret));
  assert.ok(rows.some(row=>row.event==='http_in_start'&&row.route==='evidence'));
  assert.ok(rows.some(row=>row.event==='http_in_finish'&&row.status===200));
  assert.ok(rows.some(row=>row.event==='worker_http_headers'&&row.status===200));
  assert.ok(rows.some(row=>row.event==='heartbeat'&&row.lagMs>=80));
  assert.equal(statSync(path).mode&0o777,0o600);
  const allowed=new Set(['sequence','at','elapsedMs','event','id','route','status','lagMs','cpuUserMs','cpuSystemMs','durationMs']);
  for(const row of rows)assert.ok(Object.keys(row).every(key=>allowed.has(key)));
 }finally{stop();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));rmSync(dir,{recursive:true,force:true});}
});
test('diagnostics budget is finite and stopping restores fsync',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'runtime-budget-')),path=join(dir,'runtime.jsonl');
 try{
  const stop=startRuntimeDiagnostics(path,{interval:1,budget:512});await delay(20);stop();stop();
  assert.ok(statSync(path).size<=512);
  const fd=openSync(join(dir,'plain'),'w');fsyncSync(fd);closeSync(fd);
 }finally{rmSync(dir,{recursive:true,force:true});}
});
