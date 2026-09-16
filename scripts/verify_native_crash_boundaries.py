#!/usr/bin/env python3
"""A11/A12/A13 real simulator process termination against a loopback Worker/D1.
No production configuration, ATS exception, fake clock, or extended replay deadline.
"""
from pathlib import Path
from crash_probe_runner import run_crash
import copy,hashlib,json,os,plistlib,shutil,subprocess,tempfile,time
from urllib.request import Request,urlopen
root=Path(__file__).resolve().parents[1]
os.chdir(root)
backend=Path(os.environ['M2_BACKEND_PATH']).resolve()
manifest=json.loads((root/'contracts/backend-recovery-fixture.json').read_text())
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=backend,text=True).strip()==manifest['commit'], 'Backend revision differs from reviewed fixture'
for name,digest in manifest['sha256'].items():
    assert hashlib.sha256((backend/name).read_bytes()).hexdigest()==digest, 'Backend source changed: '+name
tracked=subprocess.check_output(['git','status','--porcelain','--untracked-files=all','--','src','migrations','migrations-mobile','scripts/helpers','package.json','package-lock.json'],cwd=backend,text=True)
assert not tracked.strip(), 'Backend fixture sources must be clean'
if os.environ.get('M2_VERIFY_FIXTURE_ONLY')=='1':
    print('Pinned backend fixture verified: '+manifest['commit'])
    raise SystemExit(0)
subprocess.run(['bash','scripts/check_toolchain.sh'],check=True)
simulator=os.environ['M1_SIMULATOR_ID']
node=os.environ.get('M2_NODE_BINARY') or shutil.which('node')
assert node, 'Node.js is required'
output=root/'evidence';output.mkdir(exist_ok=True)
products=root/'.build/Build/Products'
common=['xcodebuild','-destination','platform=iOS Simulator,id='+simulator,'-parallel-testing-enabled','NO']
def run(args,name,timeout=600):
    with (output/name).open('w') as log:
        try:return subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,timeout=timeout).returncode
        except subprocess.TimeoutExpired:raise RuntimeError('Probe command timed out; see '+name)
assert run(['xcodebuild','-project','StationCatMusic.xcodeproj','-scheme','StationCatMusic','-configuration','Mock','-destination','platform=iOS Simulator,id='+simulator,'-derivedDataPath','.build','build-for-testing'],'M2-boundaries-build.log')==0, 'Build failed'
source=max(products.glob('StationCatMusic_*.xctestrun'),key=lambda p:p.stat().st_mtime)
base=plistlib.loads(source.read_bytes())
summary=[]
with tempfile.TemporaryDirectory(prefix='station-m2-boundary-') as directory:
    log=(output/'M2-boundaries-service.log').open('w')
    server=subprocess.Popen([node,'scripts/helpers/mobile-crash-service.mjs',directory],cwd=backend,stdout=log,stderr=subprocess.STDOUT)
    try:
        ready=Path(directory)/'ready.json'
        for _ in range(100):
            if ready.exists():break
            if server.poll() is not None:raise RuntimeError('Local service failed to start')
            time.sleep(.1)
        connection=json.loads(ready.read_text())
        for stage in ['A11','A12','A13']:
            started=time.monotonic()
            for mode,method in [('CRASH','testCrashAtRefreshBoundary'),('RECOVER','testRecoverOriginalOperation')]:
                data=copy.deepcopy(base)
                if 'TestConfigurations' in data:targets=[t for c in data['TestConfigurations'] for t in c['TestTargets']]
                else:targets=[v for k,v in data.items() if k!='__xctestrun_metadata__']
                for target in targets:target.setdefault('EnvironmentVariables',{}).update(M2_BOUNDARY_STAGE=stage,M2_BOUNDARY_MODE=mode,M2_PROBE_PORT=str(connection['port']),M2_PROBE_KEY=connection['key'])
                xctestrun=products/('M2-boundary-'+stage+'-'+mode+'.xctestrun')
                xctestrun.write_bytes(plistlib.dumps(data))
                name='M2-boundary-'+stage+'-'+mode+'.log'
                args=common+['-xctestrun',str(xctestrun),'-only-testing:StationCatMusicTests/NativeCrashBoundaryTests/'+method,'test-without-building']
                try:
                    if mode=='CRASH':
                        crash_evidence=run_crash(args,output/name,stage)
                        print(stage+': host exit confirmed; XCTest teardown stopped',flush=True)
                    else:
                        code=run(args,name,300)
                        content=(output/name).read_text()
                        assert code==0 and 'M2_BOUNDARY_RECOVERED:'+stage+':' in content and 'TEST EXECUTE SUCCEEDED' in content, 'Recovery failed: '+stage
                finally:
                    xctestrun.unlink(missing_ok=True)
            request=Request('http://127.0.0.1:'+str(connection['port'])+'/fixture/evidence',headers={'X-Probe-Key':connection['key']})
            with urlopen(request,timeout=5) as response:
                evidence=json.load(response)
            requests=evidence['requests']
            interval=(requests[1]['committedAt']-requests[0]['committedAt'])/1000
            print(stage+': server request interval '+str(round(interval,3))+' seconds',flush=True)
            summary.append({'case':stage,'result':'passed','seconds':round(time.monotonic()-started,2),'actual_process_exit':True,**crash_evidence,'serverRequestIntervalSeconds':round(interval,3),'storage':'simulator Keychain','server':'real isolated Worker + temporary D1','transport':'test-only HTTP loopback bridge','replay_window_seconds':120})
            (output/'M2-boundaries-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
            print(stage+': process termination and recovery passed',flush=True)
    finally:
        server.terminate()
        try:server.wait(timeout=10)
        except subprocess.TimeoutExpired:server.kill();server.wait()
        log.close()
print('All three boundaries passed; no production or HTTPS/AASA activation.',flush=True)
