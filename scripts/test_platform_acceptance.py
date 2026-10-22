"""Fail-closed release inspection. No network, device operation or upload."""
import copy
import json
import plistlib
import unittest
from check_platform_release import validate, NATIVE_FLAGS, ROOT


class PlatformReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.info = {
            "CFBundleIdentifier": "org.stationcat.music", "StationEnvironment": "production",
            **{key: "NO" for key in NATIVE_FLAGS}, "StationNativeAuthOrigin": "",
            "StationMusicWebOrigin": "", "StationProductionActivationProfile": "",
            "StationPublicAppLinksEnabled": "NO", "StationPublicReleasesEnabled": "YES", "StationPublicReleaseOrigin": "https://wwwstationcat.org",
            "CFBundleShortVersionString": "1.0.2", "CFBundleVersion": "15",
            "ITSAppUsesNonExemptEncryption": False,
        }
        self.privacy = plistlib.loads((ROOT / "Resources/PrivacyInfo.xcprivacy").read_bytes())
        self.notes = json.loads((ROOT / "Resources/Localizations.json").read_text())

    def test_public_only_candidate(self):
        self.assertFalse(validate(self.info, self.privacy, self.notes, True)["nativeServicesEnabled"])

    def test_every_native_activation_is_rejected(self):
        for key in NATIVE_FLAGS:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(dict(self.info, **{key: "YES"}), self.privacy, self.notes, True)

    def test_wrong_origin_and_staging_bundle_rejected(self):
        for key, value in [("StationPublicReleaseOrigin", "https://stationcat.org"),
                           ("CFBundleIdentifier", "org.stationcat.music.staging"),
                           ("StationNativeAuthOrigin", "https://wwwstationcat.org")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(dict(self.info, **{key: value}), self.privacy, self.notes, True)

    def test_audio_and_ats_exceptions_rejected(self):
        for key, value in [("UIBackgroundModes", ["audio"]), ("NSAppTransportSecurity", {})]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(dict(self.info, **{key: value}), self.privacy, self.notes, True)

    def test_default_closed_candidate(self):
        info = dict(self.info, StationPublicReleasesEnabled="NO", StationPublicReleaseOrigin="")
        self.assertFalse(validate(info, self.privacy, self.notes, False)["publicMetadataEnabled"])
        with self.assertRaises(ValueError):
            validate(info, self.privacy, self.notes, True)

    def test_encryption_declaration_must_be_explicit(self):
        for value in [None, True, "NO", 0]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate(dict(self.info, ITSAppUsesNonExemptEncryption=value), self.privacy, self.notes, True)

    def test_missing_manifest_reason_and_notes_rejected(self):
        privacy = copy.deepcopy(self.privacy); privacy["NSPrivacyAccessedAPITypes"].pop()
        with self.assertRaises(ValueError):
            validate(self.info, privacy, self.notes, True)
        notes = copy.deepcopy(self.notes); notes["ja"].pop("releaseV1Catalog")
        with self.assertRaises(ValueError):
            validate(self.info, self.privacy, notes, True)

    def test_duplicate_privacy_category_rejected(self):
        privacy = copy.deepcopy(self.privacy)
        privacy["NSPrivacyAccessedAPITypes"].append(privacy["NSPrivacyAccessedAPITypes"][0])
        with self.assertRaises(ValueError):
            validate(self.info, privacy, self.notes, True)


if __name__ == "__main__":
    unittest.main()
