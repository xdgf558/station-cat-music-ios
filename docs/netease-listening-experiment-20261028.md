# NetEase in-app webpage experiment — 1.0.4 (17)

Status: implemented and locally tested on 2026-10-28. The initial development package was built and signature verified. The user subsequently authorized a separate 1.0.4 (17) TestFlight upload with webpage listening enabled. Formal App Store review submission is not authorized by that upload request; the existing submitted candidate is unchanged.

## Behavior

An explicitly enabled Development/Staging build or the separately authorized TestFlight candidate opens an eligible NetEase song link in a system-style sheet inside Station Cat. Other providers and unsupported NetEase URL shapes retain the existing external handoff. The experiment accepts the published `music.163.com/song?id=…` form and the supported `/#/song?id=…` alias. It does not extract audio, proxy streams, change access rights, or claim that NetEase permits full playback.

Opening, retrying and explicit external fallback re-fetch the current Station Cat work detail and require the same work and original published link. Cancellation, dismissal and backgrounding invalidate pending results. The fallback never uses a redirected destination.

The WKWebView uses temporary storage and requires user interaction for media. No Station Cat account, native playback authorization, audio download, lock-screen player, AirPlay, or picture-in-picture is added. Closing or leaving the foreground suspends all webpage media and destroys the view; returning requires a manual retry. Main and child document navigation and final responses are restricted to the exact HTTPS `music.163.com` host (empty child documents may use `about:blank`). Popups, downloads and automatic app-scheme handoffs are cancelled. The page can still request its own subresources; the document allowlist is not a network-subresource allowlist.

The `loaded` state means the HTML document finished loading. It is not a playback, audible-sound, entitlement, or full-duration result.

## Activation and privacy boundary

`STATION_NETEASE_BROWSER_EXPERIMENT_ENABLED` is `NO` in all four committed configurations. `ExperimentalListeningConfiguration` accepts an explicit `YES` only in Development/Staging. For the user-authorized TestFlight candidate, Production accepts the exact `TESTFLIGHT` marker only with the formal bundle, expected public metadata origin and all four native service flags `NO`. Mock has a separately guarded DEBUG/simulator-only local fixture. The default production package validator rejects the experiment; `--testflight-listening` explicitly validates this separate candidate. The marker is a build configuration, not proof of an Apple distribution channel, and must not be treated as permission to submit the build for App Store release.

This experiment introduces in-app requests to NetEase and the resources used by its website. The sheet explains that IP address, browser and usage information may be processed under those services' policies. Temporary storage does not mean the third party collects no information. No credentials or webpage contents are read into native code, logs or analytics. No persistent NetEase sign-in is provided. Any future App Store activation needs a separate review of real playback behavior and the published privacy description/Apple questionnaire; this change does not save or publish those documents. The authorized TestFlight candidate retains the in-app third-party data notice and does not claim real-song verification.

The private device candidate uses `org.stationcat.music.staging`, display name `Station Cat Test`, version `1.0.4`, build `17`, development signing, and the background-mode-free platform Info.plist. Public Station Cat metadata is enabled; Universal Links, native authentication, native music, personal sync and production activation are off. It is separate from the production app identifier, but installation could update an older Staging app with the same identifier, so the package has not been installed automatically.

## Completed validation

- Local Xcode 27.1 (27A9275), iPhone 17 Pro simulator with iOS 26.4. This is not the repository's pinned stable hosted CI.
- Final focused run: 49 unit/integration tests passed, including 12 NetEase browser tests, 3 experiment-configuration tests, and existing platform catalog/presentation regressions.
- Final UI run: 5 tests passed, including dismissal/reopening, foreground lifecycle, blocked navigation/retry, rejected external handoff, four languages at largest Dynamic Type, and the old external-listening fallback with the experiment off.
- The updated version/release-notes UI passed separately. Four-language 1.0.4 notes retain all earlier entries.
- 10 Python platform-package acceptance tests passed; source guards, regenerated project/resources and whitespace checks passed.
- Development device build succeeded. Deep/strict code-sign verification passed; the built plist, entitlements, four-language resource bytes and version/build were checked. This result is for the earlier Staging package, not distribution signing.
- After the TestFlight opt-in change, 17 focused unit tests (12 browser and 5 configuration) plus 3 UI regressions passed. The updated package checks passed 12 cases, public-link checks passed 3 cases, source guards and OpenAPI validation passed (26 operations, 67 positive and 21 negative fixtures). Current changes have not run on hosted CI. Distribution archive/export/upload evidence is recorded separately in the ignored `.build/testflight-20261028-v1.0.4-build17/` directory.

All browser tests use local HTML with a restrictive CSP and no real NetEase requests or audio. Screenshots explicitly label the local fixture. The browser tool's site-safety policy refused observation of `music.163.com`; no alternative browser or network probe was used to bypass it. Therefore no real NetEase song has been verified as playable in this build.

Private artifacts remain in `.build/netease-browser-20261028/`: `final-focused.xcresult`, `ui.xcresult`, build logs, `package-validation.json`, screenshots and the development app under `DeviceData/Build/Products/Staging-iphoneos/StationCatMusic.app`. Signing artifacts and raw logs are not committed.

## Remaining manual acceptance

Using the independent test app, open 《屏幕朝下》, 《钥匙放你那里》 and 《每句话都留一半》. Separately record whether the official webpage loads, whether tapping its own play button gives audible sound and advancing progress, whether it permits the full song, and whether it requires login, the NetEase app, or a supported region. Check closing, backgrounding, network interruption and external fallback. No webpage-ready result should be reported as full playback success. These results remain required before claiming reliable in-app listening or submitting it for App Store release. The user specifically authorized TestFlight distribution to perform this validation; that permission does not turn the local fixture results into real-playback evidence.
