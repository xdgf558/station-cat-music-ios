# R2 — isolated HTTPS integration

2026-09-22: **isolated HTTPS, native transport/playback, real system-browser callback and cold/warm OS link delivery passed on the simulator**. This is not production or App Store acceptance.

Registered Apple identifiers: team `2AM5S7BM2N`, production `org.stationcat.music`, Staging `org.stationcat.music.staging`. Associated Domains was enabled for both registrations. This does not constitute provisioning, App Store submission or device acceptance.

`StationCatMusicStaging` is a separate shared scheme. The ordinary scheme continues to default to Mock. Staging and Production use their registered bundle identifiers; only the Staging app can consume the optional `Config/R2.local.xcconfig` include. Production has no R2 include or R2 Associated Domains entitlement.

Explicit local opt-in:

```sh
python3 scripts/configure_r2.py --enable
```

This generates ignored local configuration and entitlements for `station-cat-music-r2.yehao1105.workers.dev`, enabling native authentication/music/personal sync only in Staging. It does not deploy that service. Remove the generated local include to return Staging to its default closed configuration. Never commit the generated files or enable Production by copying them.

## Completed checks

- All four default configurations built and passed embedded-configuration checks with the local include temporarily absent. It was restored afterward. Defaults remain closed and no ATS exception was introduced.
- Explicitly enabled Staging built successfully. Its compiled Info.plist contains the Staging bundle ID/environment, the exact isolated HTTPS origin and the three enabled test switches.
- Local source-boundary checks passed.
- The dedicated Cloudflare Worker is deployed with separate reader/catalog D1 databases, a private R2 bucket, independent result-encryption and cover-rate-limit keys, two synthetic accounts, two synthetic three-minute tracks and a synthetic album. No production resources or real user records are used.
- HTTPS smoke checks passed for password/PKCE, single-use authorization codes, refresh replay, full/preview permissions, media HEAD/Range, cross-session favorites/history, account isolation and logout revocation. Initial evidence: 9 groups, 68 requests, three sessions created and revoked without cleanup failures. The companion website report records the additional public album/cover checks.
- Apple CDN returned the correct AASA document for the Staging App ID. This verifies retrieval, not device-level link delivery.
- `R2HTTPSIntegrationTests` passed on the iOS 26.4.1 (23E254a) iPhone 17 Pro simulator: one test, 72.019 seconds. It exercised the real Swift authentication/music/library clients and AVPlayer against public trusted HTTPS. Playback advanced beyond five seconds, with two successful HEAD requests and nine 206 Range responses; timed lyrics, free/VIP boundaries, dual-session favorites and audible-history synchronization passed. Test library state was cleaned up and all three sessions signed out.
- The probe uses an ephemeral HTTP form implementation of `AuthenticationBrowser` and an in-memory secure store. It does **not** verify `ASWebAuthenticationSession`, Universal Links or Keychain. Its output explicitly marks these limits; it must not replace the separate system-browser acceptance below.
- Normal simulator signing embedded the Staging application identifier and Associated Domains in the generated `app-Simulated.xcent` and Mach-O `__TEXT/__entitlements` section. An empty `codesign` entitlement display alone is not evidence of missing simulated entitlements. Physical-device provisioning remains unverified.

These builds used local Xcode 27 beta 6 with the documented local-toolchain override, not the fixed Xcode 26.4.1 CI acceptance environment. No signed physical-device run or archive upload was performed.

## Reproduce the opt-in native probe

Build the ordinary Mock scheme for testing first, then use `scripts/verify_r2_https_native.py --enable --input <private-json> --xctestrun <built-file> --simulator <uuid>`. The probe exercises explicitly constructed Staging clients; the test host remains Mock. The runner accepts only an owned regular mode-0600 input file, the exact isolated origin, the two designated synthetic usernames and distinct synthetic track IDs. Its input schema is documented in the script. Never pass passwords or tokens in command arguments or environment variables, and never commit that file.

The runner enables only this one test and writes owner-only evidence logs. A separate default test run confirmed the probe skips before reading private input or making network requests (one skip, zero failures, 0.008 seconds). It restores the original test favorite/history preference, clears the explicitly disposable test recent history and signs out sessions. No fixture route, TLS bypass, ATS exception or production host is used.

A redacted [native result summary](R2-native-evidence.json) is retained with this report. Raw local evidence is ignored: `evidence/R2-native-https-*.log`, `evidence/R2-native-probe-build.log`, `evidence/R2-signed-simulator-build.log`, `evidence/R2-simulator-configuration.json` and `evidence/R2-configurations.log`. These local results predate pull-request CI; the paired PR checks report stable remote validation separately.

## Actual system UI acceptance

The user explicitly authorized XCTest UI automation after Device Hub's computer-control interface repeatedly timed out. `R2SystemLoginUITests` launches the actual Staging app, types only the named synthetic account into its `ASWebAuthenticationSession`, follows the real HTTPS callback, verifies Signed in/Sign out, then signs out and verifies guest state. It passed in **40.091 seconds**, zero failures. The product's normal Keychain-backed authentication model is used; this does not test Keychain locking or physical-device restart recovery. The test declines a recognized system save-password prompt instead of saving test credentials.

`R2UniversalLinkUITests` invokes `XCUIDevice.shared.system.open`, not AppModel or a direct target-app URL helper. Warm cases first confirm background/suspended state; cold cases confirm process termination. **Warm/cold song and album delivery all passed** in 36.439 seconds. The target lyric/album and exact synthetic track IDs were checked, with a three-second observation per link showing no Playing/Pause UI. This is not acoustic or physical-device acceptance.

The first cold song run exposed a product race: catalog startup and URL resolution cancelled one another, and account restoration could clear a selected link. The model now queues the latest valid URL until restoration, scope and the latest catalog/locale finish. Eight deterministic regression tests pass, including a single cold URL, latest-valid URL, account restoration/failure, late scope notifications, locale reloads, view-task cancellation and stale results after an account change. They also verify no audio source/grant is created simply by opening the link.

The real browser also exposed two form issues in the companion website code. Inputs/buttons now inherit readable text with a 16px minimum, preserving user zoom. More importantly, the old `no-referrer` form policy caused browser POST navigation to send `Origin: null`, conflicting with the existing strict origin check. Only actual form documents now use `strict-origin` (origin only, no path/query); JSON, authorization-code redirects and callback pages keep `no-referrer`. Missing/null/foreign origins are still rejected. This behavior is specified by [Fetch's Origin-header algorithm](https://fetch.spec.whatwg.org/#append-a-request-origin-header), and a local real-browser old/new comparison reproduced 403/302. The isolated Worker version used for the successful system login is `b3f418bb-94e6-42ab-8be0-2dd4a128045a`. No production deployment occurred.

Run the opt-in UI driver only with the user's UI-automation authorization:

```sh
python3 scripts/verify_r2_system_ui.py --enable --suite login --input <owned-0600-private-json> --xctestrun <built-Staging-file> --simulator <uuid>
python3 scripts/verify_r2_system_ui.py --enable --suite links --input <owned-0600-private-json> --xctestrun <built-Staging-file> --simulator <uuid>
```

The driver validates the built Staging app's exact bundle/environment/origins/switches and rejects ATS exceptions. Ordinary CI skips both UI probes before reading input or launching an app. Raw xcresult, screenshots and typed-input activity logs are private local evidence, never public CI artifacts. Full and truncated typed values are redacted from text logs; CI upload explicitly excludes these R2 evidence paths. [The redacted result summary](R2-system-ui-evidence.json) records source hashes and earlier failures. The iOS 26.5 test-host Busy error and unsuccessful driver attempts were retained, not substituted for passing evidence.

The final default Mock run passed **138 unit tests and 3 ordinary UI tests**, with 20 dedicated unit probes and both R2 UI probes skipped by design (zero failures). The new HTTPS and UI probes skip before reading private input or performing their network/app actions. Source guards, Python compilation and diff whitespace checks also passed.

## Remaining release acceptance

These results close the R2 isolated simulator HTTPS/UI checks, not production or App Store acceptance. Fixed stable Xcode CI must be assessed separately from the local Xcode 27 beta evidence above. Physical iPhone signing/provisioning, locked Keychain, background/interruption playback, network switching and AirPlay remain R3 work. Complete account deletion and production retention/activation remain separately reviewed requirements.

Production integration requires code/configuration work: current native clients reject Production activation, and the server accepts only isolated mode. See the companion website's `docs/mobile-ios-r2/production-gaps.md`. No production enablement, StoreKit sales or App Store upload is implied by these checks.
