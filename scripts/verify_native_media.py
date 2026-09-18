#!/usr/bin/env python3
"""Local isolated workerd + actual URLSession/AVPlayer. No production networking."""
import os,json,plistlib,hashlib,subprocess,tempfile,time
from pathlib import Path
root=Path(__file__).resolve().parents[1];os.chdir(root)
backend=Path(os.environ['M3_BACKEND_PATH']).resolve();sim=os.environ['M1_SIMULATOR_ID']
manifest=json.loads((root/'contracts/backend-media-fixture.json').read_text())
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=backend,text=True).strip()==manifest['commit'], 'Backend media revision mismatch'
for name,digest in manifest['sha256'].items():assert hashlib.sha256((backend/name).read_bytes()).hexdigest()==digest, 'Backend fixture changed: '+name
assert not subprocess.check_output(['git','status','--porcelain','--untracked-files=all','--','src','scripts/helpers','migrations','migrations-mobile','migrations-music','tests/fixtures/music-mp3','package.json','package-lock.json'],cwd=backend,text=True).strip(), 'Media fixture sources must be clean'
output=root/'evidence';output.mkdir(exist_ok=True)
def run(args,name):
    with (output/name).open('w') as log:
        result=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,timeout=900)
    assert result.returncode==0,'Failed; see '+name
subprocess.run(['bash','scripts/check_toolchain.sh'],check=True)
run(['xcodebuild','-project','StationCatMusic.xcodeproj','-scheme','StationCatMusic','-configuration','Mock','-destination','platform=iOS Simulator,id='+sim,'-derivedDataPath','.build','build-for-testing'],'M3-media-build.log')
with tempfile.TemporaryDirectory(prefix='station-m3-media-') as directory:
    with (output/'M3-media-service.log').open('w') as log:
        server=subprocess.Popen(['node','scripts/helpers/mobile-music-service.mjs',directory],cwd=backend,stdout=log,stderr=subprocess.STDOUT)
        try:
            ready=Path(directory)/'ready.json';end=time.monotonic()+60
            while not ready.exists():
                assert server.poll() is None and time.monotonic()<end,'Isolated service failed to start'
                time.sleep(.1)
            connection=json.loads(ready.read_text())
            products=root/'.build/Build/Products';source=max(products.glob('StationCatMusic_*.xctestrun'),key=lambda p:p.stat().st_mtime)
            data=plistlib.loads(source.read_bytes())
            targets=[t for c in data['TestConfigurations'] for t in c['TestTargets']] if 'TestConfigurations' in data else [v for k,v in data.items() if k!='__xctestrun_metadata__']
            for target in targets:target.setdefault('EnvironmentVariables',{}).update({'M3_PROBE_PORT':str(connection['port']),'M3_PROBE_KEY':connection['key']})
            path=products/'M3-media.xctestrun';path.write_bytes(plistlib.dumps(data))
            run(['xcodebuild','-destination','platform=iOS Simulator,id='+sim,'-parallel-testing-enabled','NO','-xctestrun',str(path),'-only-testing:StationCatMusicTests/NativeMediaIntegrationTests','-only-testing:StationCatMusicTests/PlaybackStabilityTests','-only-testing:StationCatMusicTests/PlaybackSystemIntegrationTests','test-without-building'],'M3-media-integration.log')
            assert 'M3_NATIVE_MEDIA_PASSED' in (output/'M3-media-integration.log').read_text()
            assert 'M3_FEATURED_PASSED' in (output/'M3-media-integration.log').read_text()
            for marker in ['M3_LONG_RENEWAL_PASSED','M3_RENEWAL_FAILURE_PASSED','M3_LATE_RENEWAL_PASSED','M3_OFFLINE_SEEK_PASSED','M3_POLICY_EXPIRY_PASSED','M4_SYSTEM_PASSED','M4_QUEUE_SLEEP_PASSED','M4_AUTH_ROTATION_PASSED','M4_LINKS_PASSED']:
                assert marker in (output/'M3-media-integration.log').read_text(), 'Missing stability evidence: '+marker
            print('Actual native AVPlayer / HTTP HEAD / Range / revocation / hard-stop passed against isolated workerd. HTTPS/AASA and physical iPhone remain unverified.')
        finally:
            server.terminate()
            try:server.wait(timeout=10)
            except subprocess.TimeoutExpired:server.kill();server.wait()
            if 'path' in locals():path.unlink(missing_ok=True)
