"""Inspect a built public-platform app. Read-only; no signing, upload or activation."""
from pathlib import Path
import argparse
import json
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
NATIVE_FLAGS = ["StationNativeAuthEnabled", "StationNativeMusicEnabled",
                "StationPersonalSyncEnabled", "StationProductionActivationEnabled"]
REASONS = {"NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
           "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]}
NOTES = ["releaseShareCards", "releaseNetEaseBrowserRelease", "releaseNetEaseNavigationFix", "releaseNetEaseBrowserExperiment", "releaseNetEaseBrowserControl", "releaseNotebook", "releaseNotebookOrganization", "releaseNotebookLocal", "releaseBundledClips", "releaseDouyinClips", "releaseDouyinControl", "releaseYouTubeClips", "releaseYouTubeControl", "releaseV1Catalog", "releaseV1Reading", "releaseV1Personal", "releaseV1Listening", "releaseSongContent", "releaseLyricsReader", "releaseContentStates", "releasePersonalHub", "releaseRecentlyViewed", "releasePlatformPreference", "releaseCatalogCategories", "releaseUniversalLinks", "releaseSongLinks", "releaseFavoriteReliability", "releaseDetailErrors", "releasePrivacyLinks", "releaseCoverCache", "releaseImageLoading", "releaseImageRetries"]


def validate(info, privacy, localizations, public_enabled, links_enabled=False,
             testflight_listening=False, app_store_listening=False):
    errors = []
    if testflight_listening and app_store_listening:
        errors.append("Listening candidate modes are mutually exclusive")
    if links_enabled and not public_enabled:
        errors.append("Public links need public metadata")
    if testflight_listening and not public_enabled:
        errors.append("TestFlight listening candidate needs public metadata")
    if app_store_listening and not public_enabled:
        errors.append("App Store listening candidate needs public metadata")
    listening_marker = "APPSTORE" if app_store_listening else "TESTFLIGHT" if testflight_listening else "NO"
    for key, expected in {
        "CFBundleIdentifier": "org.stationcat.music", "StationEnvironment": "production",
        **{key: "NO" for key in NATIVE_FLAGS},
        "StationNetEaseBrowserExperimentEnabled": listening_marker,
        "StationNativeAuthOrigin": "", "StationMusicWebOrigin": "",
        "StationProductionActivationProfile": "",
        "StationPublicAppLinksEnabled": "YES" if links_enabled else "NO",
        "StationPublicReleasesEnabled": "YES" if public_enabled else "NO",
        "StationPublicReleaseOrigin": "https://wwwstationcat.org" if public_enabled else "",
    }.items():
        if info.get(key) != expected:
            errors.append("Unexpected " + key)
    for forbidden in ["UIBackgroundModes", "NSAppTransportSecurity", "NSUserTrackingUsageDescription"]:
        if forbidden in info:
            errors.append("Unexpected " + forbidden)
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        errors.append("Expected system-only encryption declaration")
    reasons = privacy.get("NSPrivacyAccessedAPITypes", [])
    if len(reasons) != len(REASONS) or {
        row.get("NSPrivacyAccessedAPIType"): row.get("NSPrivacyAccessedAPITypeReasons") for row in reasons
    } != REASONS:
        errors.append("Required-reason manifest mismatch")
    if privacy.get("NSPrivacyTracking") is not False:
        errors.append("Tracking must remain disabled")
    if set(localizations) != {"en", "zh-Hans", "zh-Hant", "ja"}:
        errors.append("Expected four complete locales")
    for locale, values in localizations.items():
        if not all(isinstance(values.get(key), str) and values[key].strip() for key in NOTES):
            errors.append("Missing release notes: " + locale)
    if errors:
        raise ValueError("; ".join(errors))
    return {
        "bundle": info["CFBundleIdentifier"],
        "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
        "publicMetadataEnabled": public_enabled, "nativeServicesEnabled": False,
        "testflightListeningEnabled": testflight_listening,
        "appStoreListeningEnabled": app_store_listening,
        "backgroundAudio": False, "requiredReasonManifest": "present",
        "usesNonExemptEncryption": False,
        "releaseNoteLocales": sorted(localizations),
        "appStorePrivacyLabelConfirmed": False, "signedDistributionValidated": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--public-enabled", action="store_true",
                        help="Expect an explicitly enabled public-only candidate; does not change configuration")
    parser.add_argument("--public-links-entitlements", type=Path,
                        help="Exported signed entitlements for a separately approved public-links candidate")
    listening_mode = parser.add_mutually_exclusive_group()
    listening_mode.add_argument("--testflight-listening", action="store_true",
                        help="Expect an explicitly approved TESTFLIGHT listening candidate marker; does not prove or change Apple's distribution route")
    listening_mode.add_argument("--app-store-listening", action="store_true",
                        help="Expect an explicitly approved APPSTORE listening candidate marker; does not prove or change Apple's distribution route")
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / "Info.plist").read_bytes())
    project = (ROOT / "StationCatMusic.xcodeproj/project.pbxproj").read_text()
    for field, setting in [("CFBundleShortVersionString", "MARKETING_VERSION"), ("CFBundleVersion", "CURRENT_PROJECT_VERSION")]:
        values = set(re.findall(r'"' + setting + r'" = "([^"\n]+)";', project))
        if values != {info.get(field)}:
            raise ValueError("Built version differs from project: " + field)
    privacy = plistlib.loads((app / "PrivacyInfo.xcprivacy").read_bytes())
    notes = json.loads((app / "Localizations.json").read_text())
    if (app / "Localizations.json").read_bytes() != (ROOT / "Resources/Localizations.json").read_bytes():
        raise ValueError("Bundled update notes differ from reviewed source")
    if args.public_links_entitlements:
        from check_platform_links import validate as validate_links
        validate_links(info, plistlib.loads(args.public_links_entitlements.read_bytes()), enabled=True, signed=True)
    print(json.dumps(validate(info, privacy, notes, args.public_enabled,
                              args.public_links_entitlements is not None, args.testflight_listening,
                              args.app_store_listening), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
