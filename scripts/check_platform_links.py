"""Validate a public-links candidate's Info.plist and exported signing entitlements.
This is artifact validation, not Apple CDN, provisioning or device acceptance.
"""
import argparse
import json
import plistlib
from pathlib import Path

ORIGIN = 'https://wwwstationcat.org'
APP_ID = '2AM5S7BM2N.org.stationcat.music'
NATIVE = ['StationNativeAuthEnabled', 'StationNativeMusicEnabled', 'StationPersonalSyncEnabled', 'StationProductionActivationEnabled']


def validate(info, entitlements, *, enabled=False, signed=False):
    if info.get('StationPublicAppLinksEnabled') != ('YES' if enabled else 'NO'):
        raise ValueError('Unexpected public-links flag')
    domains = entitlements.get('com.apple.developer.associated-domains', [])
    if not enabled:
        if domains:
            raise ValueError('Closed public candidate claims associated domains')
        return {'publicLinksEnabled': False, 'deviceAccepted': False}
    if info.get('CFBundleIdentifier') != 'org.stationcat.music' or info.get('StationEnvironment') != 'production':
        raise ValueError('Wrong public app identity')
    if info.get('StationPublicReleasesEnabled') != 'YES' or info.get('StationPublicReleaseOrigin') != ORIGIN:
        raise ValueError('Public metadata configuration is not ready')
    if any(info.get(key) != 'NO' for key in NATIVE) or info.get('StationNativeAuthOrigin') or info.get('StationProductionActivationProfile'):
        raise ValueError('Native activation is outside this public-link release')
    if domains != ['applinks:wwwstationcat.org']:
        raise ValueError('Associated domains must claim exactly the public website; no webcredentials, wildcard or development mode')
    if signed and (entitlements.get('application-identifier') != APP_ID or entitlements.get('com.apple.developer.team-identifier') != '2AM5S7BM2N'):
        raise ValueError('Signed application/team identifier mismatch')
    return {'publicLinksEnabled': True, 'applicationIdentifier': APP_ID, 'deviceAccepted': False, 'appleCDNVerified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--entitlements', type=Path, required=True)
    parser.add_argument('--enabled', action='store_true')
    parser.add_argument('--signed', action='store_true')
    args = parser.parse_args()
    info = plistlib.loads((args.app / 'Info.plist').read_bytes())
    entitlements = plistlib.loads(args.entitlements.read_bytes())
    print(json.dumps(validate(info, entitlements, enabled=args.enabled, signed=args.signed), indent=2))


if __name__ == '__main__':
    main()
