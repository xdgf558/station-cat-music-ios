#!/usr/bin/env python3
"""Opt-in real HTTPS native test. Uses an already-built test bundle; never builds.

Input (private, mode 0600 JSON): origin, free/vip {username,password},
tracks {free,vip}, collectionSlug='r2-synthetic-album', allowTestLibraryReset=true.
Only the two synthetic R2 users are accepted. This probe resets the free test
user's recent history and restores its original favorite/history preference.
Passwords/tokens are never passed in argv or environment. Form HTTP automation
is not ASWebAuthenticationSession, AASA, Universal Link or physical-device proof.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import uuid

ORIGIN = 'https://station-cat-music-r2.yehao1105.workers.dev'
ROOT = Path(__file__).resolve().parents[1]
TEST = 'StationCatMusicTests/R2HTTPSIntegrationTests/testExplicitNativeHTTPSAuthenticationPlaybackAndLibrary'


def validate_input(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 8192 or info.st_uid != os.getuid():
        raise ValueError('Private input must be an owned regular 0600 file, at most 8192 bytes')
    data = json.loads(path.read_bytes())
    if data.get('origin') != ORIGIN or data.get('allowTestLibraryReset') is not True or data.get('collectionSlug') != 'r2-synthetic-album':
        raise ValueError('Input is not an explicitly authorized isolated R2 test')
    for role in ('free', 'vip'):
        identity = data.get(role, {})
        password = identity.get('password')
        if identity.get('username') != 'r2tester-' + role or not isinstance(password, str) or not 16 <= len(password) <= 256:
            raise ValueError('Only dedicated synthetic R2 identities are accepted')
        uuid.UUID(data['tracks'][role])
    if data['tracks']['free'] == data['tracks']['vip']:
        raise ValueError('Distinct synthetic tracks are required')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--enable', action='store_true', required=True)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--xctestrun', type=Path, required=True)
    parser.add_argument('--simulator', required=True)
    args = parser.parse_args()
    # lstat before resolve ensures a symlink cannot acquire an acceptable target's mode.
    validate_input(args.input.absolute())
    private_input = args.input.resolve(strict=True)
    source = args.xctestrun.resolve(strict=True)
    if source.suffix != '.xctestrun' or not source.is_relative_to(ROOT / '.build'):
        raise ValueError('Use an existing locally built .build xctestrun')
    uuid.UUID(args.simulator)
    data = plistlib.loads(source.read_bytes())
    targets = [t for c in data['TestConfigurations'] for t in c['TestTargets']] if 'TestConfigurations' in data else [v for k, v in data.items() if k != '__xctestrun_metadata__' and isinstance(v, dict)]
    found = False
    for target in targets:
        target['IsEnabled'] = target.get('BlueprintName') == 'StationCatMusicTests'
        if target['IsEnabled']:
            found = True
            target.setdefault('EnvironmentVariables', {}).update({'R2_ENABLE_NATIVE_HTTPS': 'YES', 'R2_PRIVATE_INPUT': str(private_input)})
    if not found:
        raise ValueError('No StationCatMusicTests target in xctestrun')
    evidence = ROOT / 'evidence'
    evidence.mkdir(exist_ok=True)
    run_id = str(uuid.uuid4())
    generated = source.parent / ('R2-https-' + run_id + '.xctestrun')
    log = evidence / ('R2-native-https-' + run_id + '.log')
    # Keep generated files next to original products so __TESTROOT__ is unchanged.
    with generated.open('xb') as output:
        os.chmod(generated, 0o600)
        output.write(plistlib.dumps(data))
    try:
        with log.open('x') as output:
            os.chmod(log, 0o600)
            result = subprocess.run(['xcodebuild', '-destination', 'platform=iOS Simulator,id=' + args.simulator,
                '-parallel-testing-enabled', 'NO', '-xctestrun', str(generated), '-only-testing:' + TEST,
                'test-without-building'], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=300)
        text = log.read_text()
        if result.returncode != 0 or 'R2_NATIVE_HTTPS_PASSED:' not in text or 'R2_NATIVE_HTTP_PASSED:' not in text:
            raise RuntimeError('Native HTTPS probe failed; inspect the private R2 evidence log')
        for line in text.splitlines():
            if line.startswith(('R2_NATIVE_HTTP_PASSED:', 'R2_NATIVE_HTTPS_PASSED:')):
                print(line)
        print('Native HTTPS transport/playback passed. System-browser/AASA/Universal Link and physical-device acceptance remain separate.')
    finally:
        generated.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, RuntimeError, subprocess.TimeoutExpired):
        # Do not stringify input/JSON/subprocess exceptions: they can retain input values.
        raise SystemExit('R2 native probe did not complete; check private input/configuration and the private evidence log.')
