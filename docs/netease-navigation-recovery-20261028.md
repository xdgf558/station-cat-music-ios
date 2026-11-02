# NetEase webpage navigation recovery — 1.0.5 (18)

Local fix candidate, 2026-10-28. This follows the uploaded TestFlight 1.0.4 (17) experiment; it is not a new distribution receipt. The existing App Store submission is unchanged.

## Report and confirmed behavior

The user confirmed 1.0.4 (17), the song 《屏幕朝下》, and the message “网页尝试打开此测试浏览器不支持的地址”. Retry and external-open buttons remained visible. That distinguishes a rejected document navigation from a dismissed native sheet or an app crash.

A local WebKit fixture reproduced the old behavior: an approved document loaded, its link to a disallowed HTTPS host was cancelled, and the session removed the entire web view. The old-source UI assertion requiring the committed page to remain visible failed. This reproduction establishes the page-removal behavior, not the actual destination attempted by NetEase on the user's phone. No raw navigation URL or device diagnostic was available.

The earlier sheet-disappearance hypothesis was not established: both ordinary and full-screen local sheet checks passed, and a temporary assertion intended to force the parent disappearance callback observed zero callbacks. That fixture and speculative lifecycle changes were removed.

## Change

- Allow exactly `music.163.com` and `y.music.163.com` for HTTPS document navigation and final responses. The latter was already an accepted provider host in the platform link validator. The initial canonical song-link requirements remain unchanged. No evidence establishes that this was the user's actual blocked host.
- Cancel a rejected extra navigation while retaining the previously committed approved page. A blocked initial navigation cannot retain a blank browser. Invalid HTTP/MIME responses and downloads still fail; app-scheme attempts remain cancelled with a notice. No rejected address is opened externally.
- Retry and explicit external fallback continue to revalidate the current work and its original published link. Closing or backgrounding destroys the browser and suspends webpage media.
- Show a temporary diagnostic containing a fixed action/response category, frame category and a bounded clean host where available. Do not include path, query, fragment, user information, page content or raw errors. This value is not persisted or uploaded. A new document attempt clears previous notices.
- Ignore nil and stale navigation callbacks so cancellation cannot destroy the retained page later.
- Increment the candidate to 1.0.5 (18), with four-language release notes and the 1.0.4 history retained.

All committed service/experiment defaults and the separate TestFlight opt-in requirements remain unchanged. The document allowlist does not restrict every subresource fetched by the official webpage. This remains an experiment, not native audio playback or a guarantee of full-song access.

## Validation and limits

Validation uses Xcode 27.1 (27A9275) and local iOS simulator fixtures. The HTML explicitly says it is local and has no real audio; its CSP prevents remote subresources. Giving the local document an approved base URL does not fetch that page. The browser tool previously refused live observation of `music.163.com`; no alternative network or browser route was used to bypass that refusal.

The first combined run passed 22 unit/configuration tests and the version page UI test, then the UI runner lost its connection to `testmanagerd` before reaching the mobile-document assertion. The result bundle reports a terminated runner; matching system reports contain `XPC_EXIT_REASON_SIGTERM_TIMEOUT`. The failed run is retained. A hanging earlier reproduction process was stopped before the targeted rerun.

Final focused regression passed with exit code 0: **31 tests, zero failures or skips** on the iOS 27.0 simulator. This comprises 18 browser/session tests, 5 experiment-configuration tests and 8 UI tests, including the version page, approved mobile document fixture, blocked-navigation page retention/retry, initial-navigation failure, closing/reopening, background teardown, four languages at large text, and the existing external-link fallback. This is local beta-Xcode validation, not hosted stable CI.

The 12 Python platform-package acceptance checks, source guards and whitespace checks also passed. The built Mock app reports `1.0.5 (18)` and contains the exact regenerated four-language localization bytes; its experiment flag is `NO`, with testing enabled only by the guarded local fixture. Private result bundles, logs, screenshots and comparisons are in `.build/netease-dismiss-20261028/` and are not committed.

This candidate has not been distribution-signed, installed on the user's phone or uploaded to Apple. The phone still has 1.0.4 (17). Actual NetEase navigation, sound, advancing playback progress, full duration, login and regional availability remain unverified; local fixture success must not be described as real-song playback acceptance.
