#!/usr/bin/env python3
"""Explicit isolated Staging system UI acceptance; build first, keep results private.

Requires separate user approval for XCTest UI automation. --input is the same
owned 0600 JSON used by verify_r2_https_native.py; only its path reaches the test
environment. Never upload raw xcresult: XCTest may record typed synthetic values.
No build, account provisioning, production mutation or fixture server is run.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import uuid
from verify_r2_https_native import ROOT, ORIGIN, validate_input

CASES = {
    'login': ('R2SystemLoginUITests/testRealSystemBrowserSignsInAndReturnsToStaging', 'R2_SYSTEM_LOGIN_PASSED:'),
    'links': ('R2UniversalLinkUITests/testSystemDispatchesColdAndWarmAlbumAndTrackLinks', 'R2_SYSTEM_LINKS_PASSED:'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--enable', action='store_true', required=True)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--xctestrun', type=Path, required=True)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--suite', choices=CASES, default='login')
    args = parser.parse_args()
    validate_input(args.input.absolute())
    private_input = args.input.resolve(strict=True)
    credentials = json.loads(private_input.read_bytes())
    secrets = [credentials[role][key] for role in ('free', 'vip') for key in ('username', 'password')]
    source = args.xctestrun.resolve(strict=True)
    if source.suffix != '.xctestrun' or not source.is_relative_to(ROOT / '.build'):
        raise ValueError('Use a built local xctestrun')
    uuid.UUID(args.simulator)
    data = plistlib.loads(source.read_bytes())
    targets = [t for c in data['TestConfigurations'] for t in c['TestTargets']] if 'TestConfigurations' in data else [v for k, v in data.items() if k != '__xctestrun_metadata__' and isinstance(v, dict)]
    found = False
    for target in targets:
        target['IsEnabled'] = target.get('BlueprintName') == 'StationCatMusicUITests'
        if not target['IsEnabled']:
            continue
        found = True
        raw_app = target.get('UITargetAppPath', '')
        app = Path(raw_app.replace('__TESTROOT__', str(source.parent))).resolve(strict=True)
        if not app.is_relative_to(ROOT / '.build') or app.suffix != '.app':
            raise ValueError('Unexpected target app')
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        required = {'CFBundleIdentifier': 'org.stationcat.music.staging', 'StationEnvironment': 'staging',
                    'StationNativeAuthOrigin': ORIGIN, 'StationMusicWebOrigin': ORIGIN,
                    'StationNativeAuthEnabled': 'YES', 'StationNativeMusicEnabled': 'YES', 'StationPersonalSyncEnabled': 'YES'}
        if any(info.get(key) != value for key, value in required.items()) or 'NSAppTransportSecurity' in info:
            raise ValueError('App must be the explicit isolated Staging build without ATS overrides')
        target.setdefault('EnvironmentVariables', {}).update({'R2_ENABLE_SYSTEM_UI': 'YES', 'R2_PRIVATE_INPUT': str(private_input)})
        target['SystemAttachmentLifetime'] = 'keepNever'
        target['UserAttachmentLifetime'] = 'keepAlways'
        target['TestLanguage'] = 'en'
        target['TestRegion'] = 'US'
    if not found:
        raise ValueError('Missing UI target')
    test, marker = CASES[args.suite]
    # xctestrun stays beside products to retain __TESTROOT__. All results remain
    # beneath an owner-only directory; known inputs are scrubbed from text output.
    run_id = str(uuid.uuid4())
    directory = ROOT / 'evidence' / ('R2-system-ui-' + run_id)
    directory.mkdir(mode=0o700, parents=True)
    generated = source.parent / ('R2-system-ui-' + run_id + '.xctestrun')
    with generated.open('xb') as output:
        os.chmod(generated, 0o600)
        output.write(plistlib.dumps(data))
    log = directory / 'private.log'
    result = None
    try:
        with log.open('x') as output:
            os.chmod(log, 0o600)
            result = subprocess.run(['xcodebuild', '-destination', 'platform=iOS Simulator,id=' + args.simulator,
                '-parallel-testing-enabled', 'NO', '-xctestrun', str(generated),
                '-only-testing:StationCatMusicUITests/' + test, '-resultBundlePath', str(directory / 'private.xcresult'),
                'test-without-building'], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=300, umask=0o077)
    finally:
        generated.unlink(missing_ok=True)
        if log.exists():
            text = log.read_text(errors='replace')
            for secret in secrets:
                text = text.replace(secret, '[REDACTED_SYNTHETIC_INPUT]')
            # XCTest also truncates typed values in activity labels, so replacing
            # only complete input strings is insufficient for its text log.
            text = re.sub(r"Type '[^'\r\n]*' into", "Type '[REDACTED_INPUT]' into", text)
            log.write_text(text)
            os.chmod(log, 0o600)
    text = log.read_text()
    if result is None or result.returncode != 0 or marker not in text:
        # Emit only explicitly enumerated phase identifiers, never raw XCTest text.
        for phase in ['private_input', 'launch_staging', 'open_system_browser', 'system_login_form', 'username_focus', 'username_input', 'username_value', 'password_focus', 'password_input', 'submit_navigation', 'submit_system_login', 'password_save_prompt', 'https_callback_return', 'signout_cleanup']:
            if 'R2_SYSTEM_UI_PHASE:' + phase in text:
                print('R2_SYSTEM_UI_PHASE:' + phase)
            if 'R2_SYSTEM_UI_FAILED phase=' + phase + ' category=checkpoint' in text:
                print('R2_SYSTEM_UI_FAILED phase=' + phase + ' category=checkpoint')
        for phase in ['input', 'staging_ready', 'cold_track', 'warm_track', 'cold_album', 'warm_album']:
            if 'R2_SYSTEM_LINKS_FAILED phase=' + phase + ' category=assertion' in text:
                print('R2_SYSTEM_LINKS_FAILED phase=' + phase + ' category=assertion')
        if 'R2_SYSTEM_UI_ACTION:password_save_declined' in text:
            print('R2_SYSTEM_UI_ACTION:password_save_declined')
        for auth_present in ['true', 'false']:
            for cleaned in ['true', 'false']:
                diagnostic = 'R2_SYSTEM_UI_DIAGNOSTIC auth_message_present=' + auth_present + ' cleanup_confirmed=' + cleaned
                if diagnostic in text:
                    print(diagnostic)
        raise RuntimeError('System UI probe did not complete')
    print(marker + ' suite=' + args.suite + ' local_private_results=true physical_device=false')
    print('Raw screenshots/xcresult are private local evidence and must not be uploaded.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, RuntimeError, subprocess.TimeoutExpired):
        raise SystemExit('R2 system UI probe did not complete; inspect private local evidence without publishing credentials.')
