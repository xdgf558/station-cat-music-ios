#!/usr/bin/env python3
"""Local isolated workerd + actual URLSession/AVPlayer. No production networking."""
import os,json,plistlib,hashlib,subprocess,tempfile,time
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
with tempfile.TemporaryDirectory(prefix='station-m5-library-') as directory:
    with (output/'M5-library-service.log').open('w') as log:
        server=subprocess.Popen(['node','scripts/helpers/mobile-library-service.mjs',directory],cwd=backend,stdout=log,stderr=subprocess.STDOUT)
        try:
            ready=Path(directory)/'ready.json';end=time.monotonic()+60
            while not ready.exists():
                assert server.poll() is None and time.monotonic()<end,'Isolated service failed to start'
                time.sleep(.1)
            connection=json.loads(ready.read_text())
            products=root/'.build/Build/Products';source=max(products.glob('StationCatMusic_*.xctestrun'),key=lambda p:p.stat().st_mtime)
            data=plistlib.loads(source.read_bytes())
            targets=[t for c in data['TestConfigurations'] for t in c['TestTargets']] if 'TestConfigurations' in data else [v for k,v in data.items() if k!='__xctestrun_metadata__']
            for target in targets:target.setdefault('EnvironmentVariables',{}).update({'M5_PROBE_PORT':str(connection['port']),'M5_PROBE_KEY':connection['key']})
            path=products/'M5-library.xctestrun';path.write_bytes(plistlib.dumps(data))
            run(['xcodebuild','-destination','platform=iOS Simulator,id='+sim,'-parallel-testing-enabled','NO','-xctestrun',str(path),'-only-testing:StationCatMusicTests/PersonalLibraryIntegrationTests','test-without-building'],'M5-library-integration.log')
            assert 'M5_LIBRARY_PASSED' in (output/'M5-library-integration.log').read_text(), 'Missing library probe evidence'
            print('M5 real isolated Worker / two native sessions / personal library / audible playback passed. No production activation.')
        finally:
            server.terminate()
            try:server.wait(timeout=10)
            except subprocess.TimeoutExpired:server.kill();server.wait()
            if 'path' in locals():path.unlink(missing_ok=True)
