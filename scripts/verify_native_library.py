#!/usr/bin/env python3
"""Local isolated workerd + actual URLSession/AVPlayer. No production networking."""
import os,json,plistlib,hashlib,subprocess,tempfile,time,re,uuid
from contextlib import contextmanager
from pathlib import Path
root=Path(__file__).resolve().parents[1];os.chdir(root)
backend=Path(os.environ['M5_BACKEND_PATH']).resolve();sim=os.environ['M1_SIMULATOR_ID']
manifest=json.loads((root/'contracts/backend-library-fixture.json').read_text())
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=backend,text=True).strip()==manifest['commit'], 'Backend media revision mismatch'
for name,digest in manifest['sha256'].items():assert hashlib.sha256((backend/name).read_bytes()).hexdigest()==digest, 'Backend fixture changed: '+name
assert not subprocess.check_output(['git','status','--porcelain','--untracked-files=all','--','src','scripts/helpers','migrations','migrations-mobile','migrations-music','tests/fixtures/music-mp3','package.json','package-lock.json'],cwd=backend,text=True).strip(), 'Media fixture sources must be clean'
output=root/'evidence';output.mkdir(exist_ok=True)
def run(args,name):
    with (output/name).open('w') as log:
        result=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,timeout=900)
    assert result.returncode==0,'Failed; see '+name
subprocess.run(['bash','scripts/check_toolchain.sh'],check=True)
run(['xcodebuild','-project','StationCatMusic.xcodeproj','-scheme','StationCatMusic','-configuration','Mock','-destination','platform=iOS Simulator,id='+sim,'-derivedDataPath','.build','build-for-testing'],'M5-library-build.log')
@contextmanager
def fixture(label, run_id=None):
    with tempfile.TemporaryDirectory(prefix='station-m5-library-') as directory:
        with (output/f'M5-{label}-service.log').open('w') as log:
            server=subprocess.Popen(['node','scripts/helpers/mobile-library-service.mjs',directory],cwd=backend,stdout=log,stderr=subprocess.STDOUT)
            path=None
            try:
                ready=Path(directory)/'ready.json';end=time.monotonic()+60
                while not ready.exists():
                    assert server.poll() is None and time.monotonic()<end,'Isolated service failed to start'
                    time.sleep(.1)
                connection=json.loads(ready.read_text())
                products=root/'.build/Build/Products';source=max(products.glob('StationCatMusic_*.xctestrun'),key=lambda p:p.stat().st_mtime)
                data=plistlib.loads(source.read_bytes())
                targets=[t for c in data['TestConfigurations'] for t in c['TestTargets']] if 'TestConfigurations' in data else [v for k,v in data.items() if k!='__xctestrun_metadata__']
                for target in targets:
                    env=target.setdefault('EnvironmentVariables',{})
                    env.update({'M5_PROBE_PORT':str(connection['port']),'M5_PROBE_KEY':connection['key']})
                    if run_id:env['M5_RESTART_RUN']=run_id
                path=products/f'M5-{label}.xctestrun';path.write_bytes(plistlib.dumps(data))
                yield path
            finally:
                server.terminate()
                try:server.wait(timeout=10)
                except subprocess.TimeoutExpired:server.kill();server.wait()
                if path:path.unlink(missing_ok=True)
def test(path, method, name):
    run(['xcodebuild','-destination','platform=iOS Simulator,id='+sim,'-parallel-testing-enabled','NO','-xctestrun',str(path),'-only-testing:StationCatMusicTests/PersonalLibraryIntegrationTests/'+method,'test-without-building'],name)
    return (output/name).read_text()
def exited(pid):
    try:os.kill(pid,0);return False
    except ProcessLookupError:return True
with fixture('library') as path:
    log=test(path,'testRealWorkerTwoDevicesConflictHistoryEpochAndAudiblePlayback','M5-library-integration.log')
    assert 'M5_LIBRARY_PASSED' in log,'Missing library probe evidence'
# A fresh real backend makes the reported version 0 -> B-clear 1 collision exact.
run_id=str(uuid.uuid4())
with fixture('privacy',run_id) as path:
    log=test(path,'testPreparePrivacyConflictForHostRestart','M5-privacy-prepare.log')
    prepared=re.findall(r'M5_PRIVACY_PREPARED run='+re.escape(run_id)+r' pid=(\d+)',log)
    assert len(prepared)==1,'Missing/duplicate prepare evidence'
    old=int(prepared[0]);assert old>1
    subprocess.run(['xcrun','simctl','terminate',sim,'org.stationcat.music.dev'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    deadline=time.monotonic()+10
    while not exited(old) and time.monotonic()<deadline:time.sleep(.1)
    assert exited(old),'Prepare host is still alive; cannot claim restart'
    log=test(path,'testRecoverPrivacyConflictInNewHost','M5-privacy-recover.log')
    recovered=re.findall(r'M5_PRIVACY_RESTART_PASSED run='+re.escape(run_id)+r' old=(\d+) new=(\d+)',log)
    assert len(recovered)==1 and int(recovered[0][0])==old,'Missing/mismatched recovery evidence'
    new=int(recovered[0][1]);assert new>1 and new!=old,'Recovery reused old host'
    (output/'M5-privacy-restart.json').write_text(json.dumps({'run':run_id,'oldPID':old,'newPID':new,'oldHostExited':True,'historyRemainedEmpty':True},indent=2)+'\n')
print('M5 real Worker / native library / audible playback / privacy conflict across exited hosts passed. No production activation.')
