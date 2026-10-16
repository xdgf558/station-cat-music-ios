import plistlib
from pathlib import Path
import unittest
from check_platform_links import validate, NATIVE, ORIGIN, APP_ID

ROOT = Path(__file__).resolve().parents[1]

class PlatformLinks(unittest.TestCase):
    def setUp(self):
        self.info = {'StationPublicAppLinksEnabled':'YES', 'StationPublicReleasesEnabled':'YES', 'StationPublicReleaseOrigin':ORIGIN,
                     'CFBundleIdentifier':'org.stationcat.music', 'StationEnvironment':'production', **{key:'NO' for key in NATIVE}}
        self.entitlements = plistlib.loads((ROOT/'Config/PlatformLinks.entitlements').read_bytes())

    def test_enabled_candidate_and_signature_identity(self):
        self.assertTrue(validate(self.info, self.entitlements, enabled=True)['publicLinksEnabled'])
        signed = dict(self.entitlements, **{'application-identifier':APP_ID, 'com.apple.developer.team-identifier':'2AM5S7BM2N'})
        self.assertTrue(validate(self.info, signed, enabled=True, signed=True)['publicLinksEnabled'])
        with self.assertRaises(ValueError): validate(self.info, self.entitlements, enabled=True, signed=True)

    def test_closed_build_cannot_silently_claim_domain(self):
        closed = dict(self.info, StationPublicAppLinksEnabled='NO')
        self.assertFalse(validate(closed, {})['publicLinksEnabled'])
        with self.assertRaises(ValueError): validate(closed, self.entitlements)
        for config in ['Mock','Development','Staging','Production']:
            self.assertIn('STATION_PUBLIC_APP_LINKS_ENABLED = NO', (ROOT/f'Config/{config}.xcconfig').read_text())

    def test_other_domains_authentication_and_wrong_identity_rejected(self):
        for domains in [['applinks:*.wwwstationcat.org'], ['webcredentials:wwwstationcat.org'], ['applinks:wwwstationcat.org?mode=developer'], []]:
            with self.assertRaises(ValueError): validate(self.info, {'com.apple.developer.associated-domains':domains}, enabled=True)
        for key, value in [('CFBundleIdentifier','org.stationcat.music.staging'),('StationEnvironment','staging'),('StationPublicReleaseOrigin','https://stationcat.org'), *[(key,'YES') for key in NATIVE]]:
            with self.assertRaises(ValueError): validate(dict(self.info, **{key:value}), self.entitlements, enabled=True)

if __name__ == '__main__': unittest.main()
