# R3: artwork reuse, version notes, resume and permanently free offline audio

Scope: local iOS development branch and the dedicated HTTPS R2 isolation Worker. Production native flags, payments, subscriptions, App Store release and production website deployment remain unchanged. This increment preserves the preceding physical playback / artwork-crash fixes and uncommitted UI work.

## Review dependency

Backend: [caption-ai-landing-site #181](https://github.com/xdgf558/caption-ai-landing-site/pull/181), commit `0310332102dd172d842f3b4e3a5cf02aeb9de6ac`. Review and merge that isolated API change before this iOS batch. Existing recovery/media/library CI fixtures retain their separately reviewed pins; they do not prove the new live offline endpoint. Offline deterministic tests and opt-in HTTPS/device evidence below cover that new path.

## Behaviour

- Shared ephemeral artwork session, same-URL in-flight coalescing, bounded 24 MiB decoded-image LRU (32 entries), existing 150 MiB public-only disk cache. Same URL reused by a view keeps its displayed image. Discovery/catalog shelves load lazily.
- Only successful public, versioned isolated cover responses permit five-minute client caching. Errors remain no-store; Cloudflare/CDN caching remains off. Existing publication/version/object validation runs before new responses. Cached public artwork can remain visible until that five-minute client TTL expires.
- Version in My → About & Support is read from bundle version/build: 0.1.0 (2). A four-language Updates page describes this development build; no App Store update service or subscription sales were added.
- Network/authorization interruption captures the current in-memory playhead before removing audio. Explicit Play obtains fresh online authorization, then seeks to that position before playback. Changing track/version/scope and natural completion retain their existing reset rules. This does not persist a hidden listening-history/checkpoint file across app termination.
- My → Offline music shows saved songs, storage and deletion controls. The player offers Save for offline listening only for explicit server `offlineEligible=true`. Optional auto-save starts after the audible-listen threshold; it defaults OFF and explains cellular-data use.
- Strict `accessMode=free` only. VIP, preview, limited-free and early-access policies cannot acquire offline permits, even with VIP credentials. A normal online playback grant is still needed for every download Range. The permit is not a replacement media bearer.
- Offline permit: revision + policy version + SHA-256 + exact size + duration, maximum seven days. Full download is bounded at 32 MiB, verifies SHA-256, rechecks current policy after downloading and atomically publishes an audio/receipt directory. Incomplete/cancelled/mismatched downloads never appear as saved songs. Download requests/grant URLs/Bearers are not persisted.
- Total owned offline store budget: 500 MiB, 200 entries, one active download. User-controlled deletion, no eviction of unsent personal-library data. Store is origin-scoped and excluded from backup; audio and metadata use complete-until-first-authentication file protection. Playback reopens and hashes the completed file off MainActor. Expired/clock-rollback/corrupt/changed-version files are rejected; continuous playback deadlines stop buffered offline audio too.
- A successful fresh catalog removes cached tracks that disappeared, changed revision or lost permanent-free eligibility. Without a connection, previously issued permanent-free permits remain usable only through their bounded local lease. This is not DRM or immediate remote revocation while disconnected.
- Offline uses the same AVPlayer, queue, system controls, sleep timer, natural-end path and scoped history callback. Audio network calls are unnecessary for a valid saved song. Temporary-image cleanup does not remove saved audio; Offline music has its own explicit controls.

## Verification evidence

- Final targeted simulator run: `.build/r3-offline-final.xcresult` (56 Swift tests plus the offline/version UI test). Covers shared image requests, image freshness/LRU, exact media ranges/cancellation, pause/interruption/resume, natural completion/replay, offline expiry/corruption/quota/cancelled write/withdrawn policy, and system playback controls.
- Real isolated HTTPS: `.build/r3-offline-https-acceptance.xcresult`, opt-in `R3_ENABLE_OFFLINE_ACCEPTANCE=YES`. Simulator downloaded and SHA-256 verified the actual 6,845,782-byte free MP3 (revision 4), reopened its cache through a new instance, then replaced **all audio authorization/media networking** with a transport that throws. Playback, seek past 42 seconds and resume from 44.15 seconds succeeded with zero calls to that denied transport. This is not a physical radio/network-switch test.
- Measured in that simulator run: cover cold 2.599 s, decoded memory reuse 0.000079 s, new loader/disk reuse 0.009610 s; offline playback reached >1 second of progress in 1.330 s. Cold network timing remains dependent on the connection; these are measurements, not latency guarantees.
- Backend: `test:mobile:music` 18/18, including actual temporary Miniflare D1/R2 free-permit gates, paid/limited denial, revision mismatch and withdrawal; `test:mobile:r2` 12/12 cover routing/cache/fail-closed cases.
- OpenAPI: 26 operations, 66 positive fixtures, 17 rejection cases. Source guards/four-language parity and diff whitespace checks passed.
- Local 153-page site build uses `ALLOW_EMPTY_SERIAL_CONTENT=1`; validation only, never a production deployment artifact.
- Dedicated staging Worker deployed with local Wrangler 4.131.1, config `wrangler.mobile-r2.jsonc`, version `114ef63a-cc1a-4c78-af0f-9fade8983d74`. New `MOBILE_FREE_OFFLINE_ENABLED=true` exists only there. Verified real version-4 cover returns public/max-age=300 and CDN no-store; current free permit returns seven-day expiry and exact MP3 hash/size. Stale version 1 correctly returns 409/no-store.

## Remaining physical acceptance

The initial device-unavailable installation blocker was resolved on 2026-09-25; installation and physical transport-denied tests are recorded below. A user-observed airplane-mode/background check remains pending. Other production and real-device release boundaries remain unchanged.

The synthetic short MP3 used for deterministic tests is documented in `Resources/TestAudio/README.md` and is bundled only with XCTest, not the shipping App.


## Physical installation and acceptance — 2026-09-25

The intended `拉沙的 iPhone` / iPhone Air reconnected. Installed signed Staging `org.stationcat.music.staging` version **0.1.0 (2)** in place with CoreDevice (no uninstall or data reset). Physical opt-in XCTest `.build/r3-offline-device-20260925.xcresult` passed 1/1 in 28.245 s. Downloaded the actual permanent-free track, verified SHA-256, reopened the cache through a new instance, then used a denying authorization/media transport: **zero audio network calls**, offline playback, seek past 42 seconds, failure/manual resume from **44.118 s**, pause/resume, final progress **46.371 s**. Offline playback reached progress >1 s in **1.346 s**. The saved song remains available in My → Offline music for the user's own airplane-mode check.

Physical artwork timing: cold **1.475 s**, memory reuse **0.000088 s**, reopened disk **0.01056 s**. This proves cache reuse on the device; actual first-load speed still depends on the network. This test disabled audio-network transports rather than switching the phone radio. A user-observed airplane-mode/background test remains separate.

Xcode 27 beta emitted an AVAudioSession synchronous-activation warning and, after the passing XCTest summary, a result-collection `xcrun devicectl` lookup warning caused by the default CLI tool selection. Neither is recorded as a test failure. Normal launch was checked separately with explicit `DEVELOPER_DIR` and CoreDevice.

## Generated-source check

Contract and four-language resource generators now include the R3 additions. Re-running all three generators leaves their output byte-identical. Contract validation covers 26 operations, 66 positive fixtures (including the new request/response), and 17 negative cases. This is a submission consistency check, not a replacement for pending remote CI.
