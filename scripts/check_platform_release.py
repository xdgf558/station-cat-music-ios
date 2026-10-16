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
NOTES = ["releaseSongLinks", "releaseFavoriteReliability", "releaseDetailErrors", "releasePrivacyLinks", "releaseCoverCache", "releaseImageLoading", "releaseImageRetries"]


def validate(info, privacy, localizations, public_enabled, links_enabled=False):
    errors = []
    if links_enabled and not public_enabled:
        errors.append("Public links need public metadata")
    for key, expected in {
        "CFBundleIdentifier": "org.stationcat.music", "StationEnvironment": "production",
        **{key: "NO" for key in NATIVE_FLAGS},
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
    print(json.dumps(validate(info, privacy, notes, args.public_enabled, args.public_links_entitlements is not None), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
