"""Validate a reviewed production profile, or explicitly generate ignored local build settings.

This script performs no network, signing, deployment, installation, or database work.
The tracked example is deliberately disabled and cannot be used with --enable.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = 'https://wwwstationcat.org'
IDENTITY = {
    'schemaVersion': 1,
    'profileId': 'station-native-production-v1',
    'environment': 'production',
    'apiOrigin': ORIGIN,
    'webOrigin': ORIGIN,
    'callback': ORIGIN + '/auth/mobile/callback',
    'applicationIdentifier': '2AM5S7BM2N.org.stationcat.music',
}
CAPABILITIES = {'nativeAuthentication', 'musicCatalog', 'musicPlayback', 'personalSync', 'accountDeletion'}


def validate(profile, require_enabled=False):
    if type(profile) is not dict or set(profile) != set(IDENTITY) | {'enabled', 'capabilities'}:
        raise ValueError('Profile fields must exactly match production schema version 1')
    if any(type(profile[key]) is not type(value) or profile[key] != value for key, value in IDENTITY.items()):
        raise ValueError('Production profile identity, origins, callback, and app identifier are fixed')
    capabilities = profile['capabilities']
    if type(profile['enabled']) is not bool or type(capabilities) is not dict or set(capabilities) != CAPABILITIES:
        raise ValueError('Profile enablement and capability fields must match schema version 1')
    if any(type(value) is not bool for value in capabilities.values()):
        raise ValueError('Capabilities must be booleans')
    if capabilities['accountDeletion']:
        raise ValueError('Production account deletion is not authorized by this profile')
    if not profile['enabled']:
        if any(capabilities.values()) or require_enabled:
            raise ValueError('A disabled profile grants no capability and cannot generate active settings')
    elif (not capabilities['nativeAuthentication'] or
          capabilities['musicCatalog'] != capabilities['musicPlayback'] or
          (capabilities['personalSync'] and not capabilities['musicPlayback'])):
        raise ValueError('Authentication is required; music catalog/playback must agree; sync requires music')
    return profile


def render(profile):
    validate(profile, require_enabled=True)
    data = json.dumps(profile, sort_keys=True, separators=(',', ':')).encode()
    encoded = base64.b64encode(data).decode()
    capabilities = profile['capabilities']
    yes = lambda value: 'YES' if value else 'NO'
    # Empty expansion prevents xcconfig's // comment handling from truncating HTTPS.
    origin = ORIGIN.replace('https://', 'https:/$()/')
    settings = f'''// Generated from reviewed {profile['profileId']}; production only.
// Profile SHA-256: {hashlib.sha256(data).hexdigest()}
// Auth={capabilities['nativeAuthentication']}, music={capabilities['musicPlayback']}, sync={capabilities['personalSync']}; deletion=false.
STATION_PRODUCTION_ACTIVATION_ENABLED = YES
STATION_PRODUCTION_ACTIVATION_PROFILE = {encoded}
STATION_NATIVE_AUTH_ENABLED = YES
STATION_NATIVE_MUSIC_ENABLED = {yes(capabilities['musicPlayback'])}
STATION_PERSONAL_SYNC_ENABLED = {yes(capabilities['personalSync'])}
STATION_NATIVE_AUTH_ORIGIN = {origin}
STATION_MUSIC_WEB_ORIGIN = {origin}
STATION_APP_ENTITLEMENTS = Config/Production.local.entitlements
'''
    entitlements = {'com.apple.developer.associated-domains': [
        'applinks:wwwstationcat.org', 'webcredentials:wwwstationcat.org']}
    return settings, plistlib.dumps(entitlements)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, default=ROOT / 'Config/ProductionActivation.example.json')
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--check', action='store_true', help='Offline validation only; writes nothing')
    action.add_argument('--enable', action='store_true', help='Requires an already-reviewed enabled profile; generates local build settings')
    args = parser.parse_args()
    profile = validate(json.loads(args.profile.read_text()), require_enabled=args.enable)
    if args.check:
        print(f"Validated {profile['profileId']}: enabled={profile['enabled']}; no settings changed.")
        return
    settings, entitlements = render(profile)
    config = ROOT / 'Config'
    (config / 'Production.local.entitlements').write_bytes(entitlements)
    (config / 'Production.local.xcconfig').write_text(settings)
    print('Generated local production build settings. No build, install, upload, deployment, or server activation performed.')


if __name__ == '__main__':
    main()
