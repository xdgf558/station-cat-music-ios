# Startup loading investigation — 2026-09-24

The installed Staging build uses the isolated R2 environment. No production configuration was changed.

## Finding and change

AppModel previously restored the account, waited for every catalog page, and only then requested the featured endpoint used by the initial discovery tab. The account restore remains a prerequisite so UI actions cannot race an unconfirmed identity. Catalog and featured now load concurrently in structured child tasks; each section publishes independently. Failure of either endpoint leaves the other section usable. Both requests are cancelled by the existing load owner and checked against operation, account scope, locale and cancellation before publication. Queued cold-launch links still wait for initialization and never autoplay.

A read-only Mac curl check of the isolated public endpoints returned 200 in all six requests:

| Endpoint | Total seconds (three fresh curl processes) | Response bytes |
| --- | --- | --- |
| catalog | 1.287 / 1.188 / 1.179 | 481 |
| featured | 1.183 / 1.188 / 1.217 | 919 |

These are network timings from the Mac, not measured iPhone launch times or a before/after launch benchmark. They show that serializing these independent requests adds an avoidable request wait. Public catalog metadata remains uncached; this change does not provide offline audio. Auth restoration, server playback grants, persistent personal-library rules and production feature flags are unchanged.

## Validation

- 53 selected simulator tests passed, zero failures (CoreTests, NativeMusicTests, MusicLinkInitializationTests).
- Five new deterministic tests cover discovery before catalog completion, catalog before featured completion, independent 503 results, cancellation of both child requests, and account changes rejecting both late results.
- Existing cold/warm links, failed account restore, language reload and view-task cancellation tests passed.
- Result: `.build/startup-parallel.xcresult`; build/test log: `/tmp/station-startup-tests.log`.
- Signed Staging device build succeeded; `/tmp/station-startup-device.log`.
- Source guards and `git diff --check` passed.

Physical-device perceived launch improvement still requires observation on the user's connection; simulator correctness tests do not establish an iPhone speed percentage.
