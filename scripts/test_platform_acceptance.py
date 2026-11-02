"""Fail-closed release inspection. No network, device operation or upload."""
import copy
import json
import plistlib
import subprocess
import sys
import unittest
from check_platform_release import validate, NATIVE_FLAGS, ROOT


class PlatformReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.info = {
            "CFBundleIdentifier": "org.stationcat.music", "StationEnvironment": "production",
            **{key: "NO" for key in NATIVE_FLAGS}, "StationNativeAuthOrigin": "",
            "StationMusicWebOrigin": "", "StationProductionActivationProfile": "",
            "StationPublicAppLinksEnabled": "NO", "StationPublicReleasesEnabled": "YES", "StationPublicReleaseOrigin": "https://wwwstationcat.org",
            "StationNetEaseBrowserExperimentEnabled": "NO",
            "CFBundleShortVersionString": "1.0.6", "CFBundleVersion": "19",
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

    def test_experimental_browser_cannot_enter_production_package(self):
        for value in ["YES", "TESTFLIGHT", "APPSTORE", "yes", "NO ", True, False, 0, None]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate(dict(self.info, StationNetEaseBrowserExperimentEnabled=value),
                         self.privacy, self.notes, True)
        info = dict(self.info)
        info.pop("StationNetEaseBrowserExperimentEnabled")
        with self.assertRaises(ValueError):
            validate(info, self.privacy, self.notes, True)

    def test_explicit_testflight_listening_candidate_is_separate_from_default_release(self):
        info = dict(self.info, StationNetEaseBrowserExperimentEnabled="TESTFLIGHT")
        result = validate(info, self.privacy, self.notes, True, testflight_listening=True)
        self.assertTrue(result["testflightListeningEnabled"])
        self.assertFalse(result["appStoreListeningEnabled"])
        self.assertFalse(result["nativeServicesEnabled"])
        self.assertFalse(result["signedDistributionValidated"])
        self.assertFalse(validate(self.info, self.privacy, self.notes, True)["testflightListeningEnabled"])
        with self.assertRaises(ValueError):
            validate(info, self.privacy, self.notes, True)

    def test_testflight_listening_keeps_public_identity_and_native_boundaries(self):
        base = dict(self.info, StationNetEaseBrowserExperimentEnabled="TESTFLIGHT")
        invalid = [("StationEnvironment", "staging"), ("CFBundleIdentifier", "org.stationcat.music.staging"),
                   ("StationPublicReleaseOrigin", "https://wwwstationcat.org/"),
                   ("StationPublicReleasesEnabled", "NO")]
        invalid += [("StationNetEaseBrowserExperimentEnabled", value)
                    for value in ["YES", "NO", "APPSTORE", "testflight", "TESTFLIGHT ", True, None]]
        invalid += [(key, value) for key in NATIVE_FLAGS for value in ["YES", "no", "NO ", False, None]]
        for key, value in invalid:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                validate(dict(base, **{key: value}), self.privacy, self.notes, True, testflight_listening=True)
        closed = dict(base, StationPublicReleasesEnabled="NO", StationPublicReleaseOrigin="")
        with self.assertRaises(ValueError):
            validate(closed, self.privacy, self.notes, False, testflight_listening=True)
        for key in ["StationNetEaseBrowserExperimentEnabled", "CFBundleIdentifier", "StationEnvironment",
                    "StationPublicReleasesEnabled", "StationPublicReleaseOrigin", *NATIVE_FLAGS]:
            info = dict(base); info.pop(key)
            with self.subTest(missing=key), self.assertRaises(ValueError):
                validate(info, self.privacy, self.notes, True, testflight_listening=True)

    def test_explicit_app_store_listening_candidate_requires_its_own_opt_in(self):
        info = dict(self.info, StationNetEaseBrowserExperimentEnabled="APPSTORE")
        result = validate(info, self.privacy, self.notes, True, app_store_listening=True)
        self.assertTrue(result["appStoreListeningEnabled"])
        self.assertFalse(result["testflightListeningEnabled"])
        self.assertFalse(result["nativeServicesEnabled"])
        self.assertFalse(result["signedDistributionValidated"])
        self.assertEqual((result["version"], result["build"]), ("1.0.6", "19"))
        self.assertFalse(validate(self.info, self.privacy, self.notes, True)["appStoreListeningEnabled"])
        for options in [{}, {"testflight_listening": True},
                        {"testflight_listening": True, "app_store_listening": True}]:
            with self.subTest(options=options), self.assertRaises(ValueError):
                validate(info, self.privacy, self.notes, True, **options)

    def test_app_store_listening_keeps_public_identity_and_native_boundaries(self):
        base = dict(self.info, StationNetEaseBrowserExperimentEnabled="APPSTORE")
        invalid = [("StationEnvironment", "staging"), ("StationEnvironment", "mock"),
                   ("CFBundleIdentifier", "org.stationcat.music.staging"),
                   ("StationPublicReleaseOrigin", "https://wwwstationcat.org/"),
                   ("StationPublicReleaseOrigin", "https://unrelated.invalid"),
                   ("StationPublicReleasesEnabled", "NO"), ("StationPublicReleasesEnabled", True)]
        invalid += [("StationNetEaseBrowserExperimentEnabled", value)
                    for value in ["YES", "NO", "TESTFLIGHT", "appstore", "APPSTORE ", "APP_STORE", True, None]]
        invalid += [(key, value) for key in NATIVE_FLAGS for value in ["YES", "no", "NO ", False, None]]
        for key, value in invalid:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                validate(dict(base, **{key: value}), self.privacy, self.notes, True, app_store_listening=True)
        closed = dict(base, StationPublicReleasesEnabled="NO", StationPublicReleaseOrigin="")
        with self.assertRaises(ValueError):
            validate(closed, self.privacy, self.notes, False, app_store_listening=True)
        for key in ["StationNetEaseBrowserExperimentEnabled", "CFBundleIdentifier", "StationEnvironment",
                    "StationPublicReleasesEnabled", "StationPublicReleaseOrigin", *NATIVE_FLAGS]:
            info = dict(base); info.pop(key)
            with self.subTest(missing=key), self.assertRaises(ValueError):
                validate(info, self.privacy, self.notes, True, app_store_listening=True)

    def test_cli_rejects_mixed_distribution_modes_before_reading_package(self):
        result = subprocess.run([
            sys.executable, str(ROOT / "scripts/check_platform_release.py"),
            "--app", "/nonexistent-candidate.app", "--testflight-listening", "--app-store-listening"
        ], text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("not allowed with argument", result.stderr)
        self.assertNotIn("FileNotFoundError", result.stderr)

    def test_experiment_notes_must_be_present_in_every_locale(self):
        for locale in ["zh-Hans", "zh-Hant", "en", "ja"]:
            for key in ["releaseNetEaseBrowserRelease", "releaseNetEaseNavigationFix", "releaseNetEaseBrowserExperiment", "releaseNetEaseBrowserControl"]:
                with self.subTest(locale=locale, key=key):
                    notes = copy.deepcopy(self.notes)
                    notes[locale].pop(key, None)
                    with self.assertRaises(ValueError):
                        validate(self.info, self.privacy, notes, True)

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
        notes = copy.deepcopy(self.notes); notes["ja"].pop("releaseNotebook")
        with self.assertRaises(ValueError):
            validate(self.info, self.privacy, notes, True)

    def test_duplicate_privacy_category_rejected(self):
        privacy = copy.deepcopy(self.privacy)
        privacy["NSPrivacyAccessedAPITypes"].append(privacy["NSPrivacyAccessedAPITypes"][0])
        with self.assertRaises(ValueError):
            validate(self.info, privacy, self.notes, True)


if __name__ == "__main__":
    unittest.main()
