#!/usr/bin/env python3
"""Pinned, synthetic production-profile E2E over loopback. Never a deployment/HTTPS probe."""
import hashlib
import http.client
from datetime import datetime, timezone
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
PROTECTED = ('src', 'scripts/helpers', 'migrations', 'migrations-mobile', 'migrations-mobile-candidate',
             'migrations-music', 'tests/fixtures/music-mp3', 'tests/fixtures/mobile-links',
             'scripts/build-mobile-production-candidate.mjs', 'scripts/build-music-production-candidate.mjs',
             'wrangler.toml', 'package.json', 'package-lock.json')
REQUIRED = {'src/worker.js', 'scripts/helpers/mobile-production-service.mjs', 'migrations/0003_reader_accounts.sql',
            'migrations-mobile/0001_native_auth.sql', 'migrations-mobile-candidate/0001_binding_identity.sql',
            'migrations-music/0001_music_foundation.sql', 'tests/fixtures/mobile-links/canonical-link-cases.json',
            'scripts/build-mobile-production-candidate.mjs', 'scripts/build-music-production-candidate.mjs', 'wrangler.toml',
            'package.json', 'package-lock.json'}
MARKERS = ('PRODUCTION_NATIVE_LOCAL_E2E_PASSED:', 'PRODUCTION_LINK_MATRIX_COLD_PASSED:', 'PRODUCTION_LINK_MATRIX_WARM_PASSED:')


class VerificationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def git(backend, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=backend, text=True).strip()


def verify_backend(backend, manifest, matrix):
    require(type(manifest.get('schemaVersion')) is int and manifest.get('schemaVersion') == 1 and manifest.get('repository') == 'xdgf558/caption-ai-landing-site' and
            manifest.get('profileId') == 'station-native-production-v1', 'Invalid production fixture manifest')
    commit = manifest.get('commit', '')
    require(isinstance(commit, str) and re.fullmatch(r'[0-9a-f]{40}', commit), 'Missing reviewed backend commit')
    require(git(backend, 'rev-parse', 'HEAD') == commit, 'Production backend revision mismatch')
    require(manifest.get('protectedPaths') == list(PROTECTED), 'Production dependency roots changed')
    digests = manifest.get('sha256')
    require(isinstance(digests, dict) and REQUIRED <= digests.keys(), 'Production source manifest is incomplete')
    tracked = set(git(backend, 'ls-files', '--', *PROTECTED).splitlines())
    require(set(digests) == tracked, 'Production dependency file inventory changed')
    require(not git(backend, 'status', '--porcelain', '--untracked-files=all', '--', *PROTECTED), 'Production fixture sources must be clean')
    for name, digest in digests.items():
        path = PurePosixPath(name)
        require(not path.is_absolute() and '..' not in path.parts and str(path) == name, 'Unsafe source manifest path')
        require(isinstance(digest, str) and re.fullmatch(r'[0-9a-f]{64}', digest), 'Invalid source digest')
        source = backend / name
        require(source.is_file() and not source.is_symlink() and source.resolve().is_relative_to(backend.resolve()), 'Missing or linked production source')
        require(hashlib.sha256(source.read_bytes()).hexdigest() == digest, 'Production source digest mismatch: ' + name)
    require((backend / 'tests/fixtures/mobile-links/canonical-link-cases.json').read_bytes() == matrix.read_bytes(),
            'Shared website/iOS link matrix differs')
    return commit


def validate_connection(value):
    require(isinstance(value, dict) and set(value) == {'schemaVersion', 'port', 'key'} and type(value['schemaVersion']) is int and value['schemaVersion'] == 1,
            'Invalid local fixture ready document')
    require(type(value['port']) is int and 1024 <= value['port'] <= 65535, 'Invalid loopback port')
    require(isinstance(value['key'], str) and re.fullmatch(r'[A-Za-z0-9_-]{43}', value['key']), 'Invalid ephemeral proof')
    return value


def validate_simulator(identifier, inventory):
    require(isinstance(identifier, str) and re.fullmatch(r'[A-Fa-f0-9-]{36}', identifier), 'Explicit simulator UUID required')
    matches = [row for runtime, rows in inventory['devices'].items() if 'iOS' in runtime for row in rows
               if row.get('udid') == identifier and row.get('isAvailable') and row.get('name', '').startswith('iPhone')]
    require(len(matches) == 1, 'Destination must be one available iPhone simulator')
    return matches[0]['name']


def boot_simulator(identifier, inventory, run):
    """Finish simulator cold boot before starting the resource-limited fixture."""
    validate_simulator(identifier, inventory)
    selected = next(row for runtime, rows in inventory['devices'].items() if 'iOS' in runtime
                    for row in rows if row.get('udid') == identifier)
    require(selected.get('state') in ('Shutdown', 'Booted'), 'Simulator boot state is not ready')
    if selected['state'] == 'Shutdown':
        run(['xcrun', 'simctl', 'boot', identifier], 'production-local-boot.log')
    # Even an already booted device must finish its boot work before the server
    # is initialized; a failed or timed-out boot never starts the fixture.
    run(['xcrun', 'simctl', 'bootstatus', identifier, '-b'], 'production-local-bootstatus.log')


def inject_connection(data, connection):
    targets = ([target for config in data['TestConfigurations'] for target in config['TestTargets']]
               if 'TestConfigurations' in data else [value for key, value in data.items() if key != '__xctestrun_metadata__'])
    injected = 0
    for target in targets:
        if target.get('BlueprintName') == 'StationCatMusicTests':
            target.setdefault('EnvironmentVariables', {}).update({'PRODUCTION_ENABLE_LOCAL_E2E': 'YES',
                'PRODUCTION_PROBE_PORT': str(connection['port']), 'PRODUCTION_PROBE_KEY': connection['key']})
            injected += 1
    require(injected == 1, 'Expected one native unit-test target')
    return data


def require_evidence(log):
    for marker in MARKERS:
        require(marker in log, 'Missing local production evidence: ' + marker)
    require('PRODUCTION_NATIVE_LOCAL_FAILED' not in log, 'Native production fixture failed')


def read_service_evidence(connection):
    local = http.client.HTTPConnection('127.0.0.1', connection['port'], timeout=10)
    try:
        local.request('GET', '/fixture/evidence', headers={'X-Production-Probe-Key': connection['key']})
        response = local.getresponse()
        require(response.status == 200, 'Missing local service evidence')
        data = response.read(1_048_577)
        require(len(data) <= 1_048_576, 'Oversized local service evidence')
        value = json.loads(data)
    finally:
        local.close()
    return validate_service_evidence(value)


def validate_service_evidence(value):
    require(isinstance(value, dict) and type(value.get('schemaVersion')) is int and value.get('schemaVersion') == 1 and
            value.get('scope') == 'local-production-profile-e2e' and type(value.get('outboundRequests')) is int and
            value.get('outboundRequests') == 0 and value.get('hasProductionSideEffects') is False,
            'Local production isolation evidence failed')
    count = value.get('requestCount')
    require(type(count) is int and count > 0 and isinstance(value.get('requests'), list) and len(value['requests']) == count,
            'Missing real-worker request evidence')
    counts = value.get('counts', {})
    for key in ('sessions', 'revokedSessions', 'refreshOperations', 'favorites', 'recent'):
        require(type(counts.get(key)) is int and counts[key] > 0, 'Missing real-worker database evidence: ' + key)
    require(counts['sessions'] >= 3 and counts['revokedSessions'] == counts['sessions'], 'Synthetic sessions were not all closed')
    return {'requestCount': count, 'counts': {key: counts[key] for key in
            ('sessions', 'revokedSessions', 'refreshOperations', 'favorites', 'recent')}, 'outboundRequests': 0}


def main():
    # A failed rerun must never leave an earlier passed report available to CI.
    # Do this before even validating inputs/pins or invoking the toolchain.
    output = ROOT / 'evidence'; output.mkdir(exist_ok=True)
    for name in ('production-local-summary.json', 'production-local-build.log',
                 'production-local-boot.log', 'production-local-bootstatus.log',
                 'production-local-integration.log', 'production-local-service.log', 'production-local-runtime.jsonl'):
        (output / name).unlink(missing_ok=True)
    run_id = str(uuid.uuid4())
    started_at = datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
    print('LOCAL_PRODUCTION_RUN_STARTED: ' + run_id + ' ' + started_at, flush=True)
    require('PRODUCTION_BACKEND_PATH' in os.environ, 'Set PRODUCTION_BACKEND_PATH to the reviewed local checkout')
    backend = Path(os.environ['PRODUCTION_BACKEND_PATH']).resolve()
    manifest = json.loads((ROOT / 'contracts/backend-production-fixture.json').read_text())
    revision = verify_backend(backend, manifest, ROOT / 'contracts/fixtures/canonical-link-cases.json')
    subprocess.run(['bash', 'scripts/check_toolchain.sh'], cwd=ROOT, check=True)
    sim = os.environ.get('M1_SIMULATOR_ID', '')
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True))
    simulator = validate_simulator(sim, inventory)
    runtime = next(runtime for runtime, rows in inventory['devices'].items() if any(row.get('udid') == sim for row in rows))
    def run(arguments, name):
        with (output / name).open('w') as log:
            log.write('Local production run ' + run_id + '; started ' + started_at + '\n'); log.flush()
            result = subprocess.run(arguments, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=900)
        require(result.returncode == 0, 'Failed; inspect evidence/' + name)
    destination = 'platform=iOS Simulator,id=' + sim
    run(['xcodebuild', '-project', 'StationCatMusic.xcodeproj', '-scheme', 'StationCatMusic', '-configuration', 'Mock',
         '-destination', destination, '-derivedDataPath', '.build/production-e2e', 'build-for-testing'], 'production-local-build.log')
    # Re-read state after compilation: Xcode may already have booted this device.
    boot_inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True))
    boot_simulator(sim, boot_inventory, run)
    with tempfile.TemporaryDirectory(prefix='station-production-e2e-') as directory:
        directory = str(Path(directory).resolve())  # The fixture rejects symlinked /var and /tmp aliases.
        with (output / 'production-local-service.log').open('w') as log:
            log.write('Local production run ' + run_id + '; started ' + started_at + '\n'); log.flush()
            runtime_file = Path(directory) / 'runtime-diagnostics.jsonl'
            fixture_env = os.environ.copy()
            fixture_env.update({'PRODUCTION_RUNTIME_DIAGNOSTICS_FILE': str(runtime_file),
                                'PRODUCTION_RUNTIME_DIAGNOSTICS_RUN_ID': run_id})
            server = subprocess.Popen(['node', '--import', str(ROOT / 'scripts/probe_runtime_diagnostics.mjs'),
                                       'scripts/helpers/mobile-production-service.mjs', directory], cwd=backend,
                                      stdout=log, stderr=subprocess.STDOUT, env=fixture_env)
            test_file = None
            try:
                ready = Path(directory) / 'ready.json'; deadline = time.monotonic() + 90
                while not ready.exists():
                    require(server.poll() is None and time.monotonic() < deadline, 'Local production fixture failed to start')
                    time.sleep(0.1)
                require(ready.is_file() and not ready.is_symlink() and ready.stat().st_size <= 4096 and
                        ready.stat().st_mode & 0o777 == 0o600, 'Invalid ready file')
                connection = validate_connection(json.loads(ready.read_text()))
                products = ROOT / '.build/production-e2e/Build/Products'
                sources = list(products.glob('StationCatMusic_*.xctestrun'))
                require(bool(sources), 'Missing compiled test configuration')
                source = max(sources, key=lambda path: path.stat().st_mtime)
                data = inject_connection(plistlib.loads(source.read_bytes()), connection)
                descriptor, name = tempfile.mkstemp(prefix='production-local-', suffix='.xctestrun', dir=products)
                test_file = Path(name)
                with os.fdopen(descriptor, 'wb') as destination_file:
                    destination_file.write(plistlib.dumps(data))  # mkstemp uses 0600; proof is never stored in evidence.
                run(['xcodebuild', '-destination', destination, '-parallel-testing-enabled', 'NO', '-xctestrun', str(test_file),
                     '-only-testing:StationCatMusicTests/ProductionLocalIntegrationTests',
                     '-only-testing:StationCatMusicTests/ProductionMusicLinkMatrixTests',
                     '-only-testing:StationCatMusicTests/ProductionActivationTests',
                     '-only-testing:StationCatMusicTests/MusicLinkInitializationTests', 'test-without-building'],
                    'production-local-integration.log')
                require_evidence((output / 'production-local-integration.log').read_text())
                # Save only selected aggregate evidence; never persist headers, URLs, bodies, or proof.
                service_evidence = read_service_evidence(connection)
                summary = {'schemaVersion': 1, 'scope': 'local-production-profile-e2e', 'runId': run_id, 'startedAt': started_at,
                           'completedAt': datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z'),
                           'backendCommit': revision, 'profileId': manifest['profileId'],
                           'simulator': simulator, 'localToolchainOverride': os.environ.get('M1_ALLOW_LOCAL_TOOLCHAIN') == '1',
                           'simulatorIdentifier': sim, 'simulatorRuntime': runtime,
                           'xcodeVersion': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
                           'nodeVersion': subprocess.check_output(['node', '--version'], text=True).strip(),
                           'workerEvidence': service_evidence,
                           'localRealImplementationE2E': True, 'productionActivated': False,
                           'realProductionHTTPSVerified': False, 'osAssociationVerified': False, 'physicalDeviceVerified': False}
                (output / 'production-local-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
                print('Pinned production-profile native/real-worker E2E and shared cold/warm URL matrix passed locally. Native production activation remains off; real HTTPS/OS association/device acceptance remains open.')
            finally:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill(); server.wait()
                if runtime_file.exists():
                    runtime_destination = output / 'production-local-runtime.jsonl'
                    shutil.copyfile(runtime_file, runtime_destination)
                    runtime_destination.chmod(0o600)
                if test_file:
                    test_file.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        main()
    except (VerificationError, OSError, ValueError, subprocess.SubprocessError) as error:
        # No credential or response data is included by VerificationError.
        raise SystemExit(str(error))
