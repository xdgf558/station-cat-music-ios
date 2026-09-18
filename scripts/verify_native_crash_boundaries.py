#!/usr/bin/env python3
"""A11/A12/A13 real simulator process termination against a loopback Worker/D1.
No production configuration, ATS exception, fake clock, or extended replay deadline.
"""
from pathlib import Path
from crash_probe_runner import run_file_probe,wait_ready
import hashlib,json,os,plistlib,platform,shutil,subprocess,tempfile,time,uuid
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
# Compile the exact product Core sources into a separate simulator-only probe App.
# Install before any refresh commits; relaunch with simctl, never a second XCTest session.
products=root/'.build/recovery-probe'
app=products/'BoundaryProbe.app';app.mkdir(parents=True,exist_ok=True)
bundle='org.stationcat.music.recoveryprobe'
def run(args,name,timeout=600,env=None):
    with (output/name).open('w') as log:
        try:return subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,timeout=timeout,env=env).returncode
        except subprocess.TimeoutExpired:raise RuntimeError('Probe command timed out; see '+name)
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
sources=[str(p) for directory in ['Core','TestsSupport','IntegrationProbes'] for p in sorted((root/directory).glob('*.swift'))]
entitlements=products/'probe-entitlements.plist'
entitlements.write_bytes(plistlib.dumps({'application-identifier':'LOCALPROBE.'+bundle}))
assert run(['xcrun','--sdk','iphonesimulator','swiftc','-parse-as-library','-swift-version','6','-sdk',sdk,'-target',platform.machine()+'-apple-ios18.0-simulator','-module-name','BoundaryProbe','-Xlinker','-sectcreate','-Xlinker','__TEXT','-Xlinker','__entitlements','-Xlinker',str(entitlements),*sources,'-o',str(app/'BoundaryProbe')],'M2-boundaries-build.log')==0, 'Probe build failed'
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':bundle,'CFBundleExecutable':'BoundaryProbe','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'18.0','UIDeviceFamily':[1],'LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}))
assert run(['codesign','--force','--sign','-',str(app)],'M2-boundaries-sign.log')==0, 'Simulator ad-hoc signing failed'
# boot may return nonzero when already booted; bootstatus is authoritative.
run(['xcrun','simctl','boot',simulator],'M2-boundaries-boot.log')
assert run(['xcrun','simctl','bootstatus',simulator,'-b'],'M2-boundaries-bootstatus.log')==0, 'Simulator unavailable'
assert run(['xcrun','simctl','install',simulator,str(app)],'M2-boundaries-install.log')==0, 'Probe install failed'
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',simulator,bundle,'data'],text=True).strip())
summary=[]
with tempfile.TemporaryDirectory(prefix='station-m2-boundary-') as directory:
    log=(output/'M2-boundaries-service.log').open('w')
    server=subprocess.Popen([node,'scripts/helpers/mobile-crash-service.mjs',directory],cwd=backend,stdout=log,stderr=subprocess.STDOUT)
    try:
        ready=Path(directory)/'ready.json'
        connection=wait_ready(ready,server)
        for stage in ['A11','A12','A13']:
            started=time.monotonic()
            for mode in ['CRASH','RECOVER']:
                run_id=str(uuid.uuid4())
                resultfile=container/'Documents'/('M2-'+run_id+'.log')
                env=os.environ.copy()
                env.update({'SIMCTL_CHILD_'+key:value for key,value in {'M2_PROBE_RUN_ID':run_id,'M2_BOUNDARY_STAGE':stage,'M2_BOUNDARY_MODE':mode,'M2_PROBE_PORT':str(connection['port']),'M2_PROBE_KEY':connection['key']}.items()})
                name='M2-boundary-'+stage+'-'+mode+'.log'
                args=['xcrun','simctl','launch',simulator,bundle]
                try:
                    result=run_file_probe(args,output/name,resultfile,stage,mode,env=env)
                finally:
                    if resultfile.exists():
                        shutil.copyfile(resultfile,output/('M2-boundary-'+stage+'-'+mode+'-durable.log'))
                        resultfile.unlink()
                if mode=='CRASH':
                    crash_evidence={'hostExitConfirmed':True,'crashedHostPID':result['hostPID'],
                                    'evidenceTransport':result['evidenceTransport'],'hostExitAfterMarkerSeconds':result['hostExitAfterMarkerSeconds']}
                    print(stage+': probe host exit confirmed; launching new process directly',flush=True)
                else:
                    assert result['hostPID']!=crash_evidence['crashedHostPID'], 'Recovery must use a new process'
                    crash_evidence['recoveredHostPID']=result['hostPID']
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
        run(['xcrun','simctl','uninstall',simulator,bundle],'M2-boundaries-uninstall.log',60)
print('All three boundaries passed; no production or HTTPS/AASA activation.',flush=True)
