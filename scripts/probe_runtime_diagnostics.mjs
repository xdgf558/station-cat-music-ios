// Optional test-process observability. Never record URLs, headers, bodies,
// SQL, environment values, error messages or stacks. No mutation or retry.
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {subscribe,unsubscribe} from 'node:diagnostics_channel';
import {performance} from 'node:perf_hooks';

export function routeLabel(path) {
 if(typeof path!=='string')return 'other';
 const pathname=path.split('?')[0];
 return new Map([['/fixture/prepare','prepare'],['/fixture/seed','seed'],
  ['/fixture/evidence','evidence'],['/api/mobile/v1/auth/refresh','refresh']]).get(pathname)??'other';
}

export function startRuntimeDiagnostics(path,{interval=1000,budget=262144}={}) {
 const fd=fs.openSync(path,'wx',0o600),started=performance.now();
 let bytes=0,sequence=0,closed=false,lastTick=performance.now(),requestSequence=0;
 const write=entry=>{
  if(closed)return;
  const line=JSON.stringify({sequence:++sequence,at:Date.now(),elapsedMs:Math.round(performance.now()-started),...entry})+'\n';
  if(bytes+Buffer.byteLength(line)>budget)return;
  fs.writeSync(fd,line);bytes+=Buffer.byteLength(line);
 };
 const cpu=()=>{const value=process.cpuUsage();return {cpuUserMs:Math.round(value.user/1000),cpuSystemMs:Math.round(value.system/1000)};};
 const originalSync=fs.fsyncSync;
 function measuredSync(...args){
  const start=performance.now();
  try{return originalSync(...args);}
  finally{const durationMs=Math.round(performance.now()-start);if(durationMs>=100)write({event:'fsync_slow',durationMs,...cpu()});}
 }
 fs.fsyncSync=measuredSync;syncBuiltinESMExports();
 const channels=[],incoming=new WeakMap(),outgoing=new WeakMap();
 const on=(name,handler)=>{subscribe(name,handler);channels.push([name,handler]);};
 on('http.server.request.start',({request})=>{
  const value={id:++requestSequence,route:routeLabel(request.url)};incoming.set(request,value);
  write({event:'http_in_start',...value});
 });
 on('http.server.response.finish',({request,response})=>{
  const value=incoming.get(request);if(value)write({event:'http_in_finish',...value,status:response.statusCode});
 });
 on('undici:request:create',({request})=>{
  const id=++requestSequence;outgoing.set(request,id);write({event:'worker_http_start',id});
 });
 on('undici:request:bodySent',({request})=>{const id=outgoing.get(request);if(id)write({event:'worker_http_sent',id});});
 on('undici:request:headers',({request,response})=>{const id=outgoing.get(request);if(id)write({event:'worker_http_headers',id,status:response.statusCode});});
 on('undici:request:error',({request})=>{const id=outgoing.get(request);if(id)write({event:'worker_http_error',id});});
 const timer=setInterval(()=>{
  const now=performance.now();write({event:'heartbeat',lagMs:Math.max(0,Math.round(now-lastTick-interval)),...cpu()});lastTick=now;
 },interval);timer.unref();
 write({event:'observer_started',...cpu()});
 return ()=>{
  if(closed)return;
  clearInterval(timer);for(const [name,handler] of channels)unsubscribe(name,handler);
  if(fs.fsyncSync===measuredSync){fs.fsyncSync=originalSync;syncBuiltinESMExports();}
  write({event:'observer_stopped',...cpu()});closed=true;fs.closeSync(fd);
 };
}

if(process.env.M2_RUNTIME_DIAGNOSTICS_FILE){
 const stop=startRuntimeDiagnostics(process.env.M2_RUNTIME_DIAGNOSTICS_FILE);
 process.once('exit',stop);
}
