import base64
import copy
import json
import plistlib
import unittest

from configure_production import ROOT, IDENTITY, CAPABILITIES, validate, render


class ProductionProfileTests(unittest.TestCase):
    def profile(self):
        return {**IDENTITY, 'enabled': True, 'capabilities': {
            key: key != 'accountDeletion' for key in CAPABILITIES}}

    def test_checked_in_profile_is_valid_but_cannot_enable(self):
        profile = json.loads((ROOT / 'Config/ProductionActivation.example.json').read_text())
        self.assertFalse(validate(profile)['enabled'])
        self.assertFalse(any(profile['capabilities'].values()))
        with self.assertRaises(ValueError):
            render(profile)

    def test_generated_profile_and_entitlements_bind_exact_identity(self):
        settings, entitlements = render(self.profile())
        encoded = next(line.split(' = ', 1)[1] for line in settings.splitlines()
                       if line.startswith('STATION_PRODUCTION_ACTIVATION_PROFILE = '))
        self.assertEqual(json.loads(base64.b64decode(encoded)), self.profile())
        self.assertEqual(plistlib.loads(entitlements)['com.apple.developer.associated-domains'],
                         ['applinks:wwwstationcat.org', 'webcredentials:wwwstationcat.org'])
        self.assertIn('STATION_NATIVE_AUTH_ORIGIN = https:/$()/wwwstationcat.org', settings)
        self.assertNotIn('R2', settings)

    def test_auth_only_profile_does_not_grant_music_or_sync(self):
        profile = self.profile()
        for key in ['musicCatalog', 'musicPlayback', 'personalSync']:
            profile['capabilities'][key] = False
        settings, _ = render(profile)
        self.assertIn('STATION_NATIVE_MUSIC_ENABLED = NO', settings)
        self.assertIn('STATION_PERSONAL_SYNC_ENABLED = NO', settings)

    def test_wrong_identity_unknown_fields_types_and_deletion_rejected(self):
        mutations = [{key: 'wrong'} for key in IDENTITY] + [
            {'schemaVersion': True}, {'schemaVersion': 2}, {'enabled': 'YES'},
            {'extra': True}, {'apiOrigin': IDENTITY['apiOrigin'] + '/'},
        ]
        for mutation in mutations:
            profile = {**self.profile(), **mutation}
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate(profile)
        for mutation in [{'accountDeletion': True}, {'nativeAuthentication': False},
                         {'musicCatalog': False}, {'musicCatalog': False, 'musicPlayback': False},
                         {'personalSync': 'YES'}, {'futureCapability': True}]:
            profile = copy.deepcopy(self.profile())
            profile['capabilities'].update(mutation)
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate(profile)


if __name__ == '__main__':
    unittest.main()
