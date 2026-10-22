# Douyin song clips — 1.0.2 (15)

2026-10-22. This is a separate development candidate after the merged, undeployed YouTube update 1.0.1 (14). The user explicitly deferred deployment until **1.0 is formally live**. This task does not change the submitted 1.0 (13), publish content, operate a physical iPhone, sign a distribution package or upload to TestFlight.

## Behavior

The existing selected short-clip layout gains a **抖音 / Douyin** source. A song can show up to three published clips; the preview is labelled as the song cover, not as a retrieved Douyin thumbnail. Nothing connects to Douyin on opening the song or switching into the Clips tab. The user taps to load the official player, then operates its own controls; autoplay, background playback, AirPlay, picture-in-picture and downloads are disabled.

Each load or explicit external fallback re-fetches the Station Cat clip list and checks the complete identity/revision/source against the displayed item. Loading then queries the [official Douyin iframe API](https://developer.open-douyin.com/docs/resource/zh-CN/dop/develop/openapi/video-management/douyin/iframe-player/get-iframe-by-video) with the validated video ID. The request has a bounded timeout/body, no cookies or Station Cat authorization, and rejects redirects. The response must identify the same official player URL with autoplay disabled. API-returned HTML is **never executed or persisted**: the client constructs its own minimal wrapper from a numeric video ID and internal UUID.

The official player runs in a nonpersistent WKWebView with a restricted wrapper CSP and required media user action. Its own controls, branding, ads and nested HTTPS frames remain provider-controlled. A wrapper iframe `load` event is labelled only as **document loaded**, never confirmed playback; there is no invented Douyin readiness/watch-count API. The card retains an external **Open in Douyin** action if login, region, network or embedding restrictions prevent playback. The external button also performs fresh Station Cat validation and the existing system-open/copy fallback remains available.

Changing tabs, song, language, dismissing, opening the privacy sheet, handing off externally or backgrounding cancels verification and destroys the player. Late publication/API responses cannot recreate it. A public clip already open cannot be instantly erased by a Station Cat content change; every new load revalidates and the provider can separately revoke it.

The four-language information sheet describes the third-party connection, temporary storage and provider processing, and links the official privacy policy. The [privacy-policy delta](../app-store/douyin-1.0.2-privacy-delta.md) is a **draft**, not a published policy or saved Apple answer. This build adds no click/watch telemetry, account login, native music grant or subscription feature. Marketing version, build and four-language update notes are **1.0.2 (15)**; earlier records remain available.

## Website dependency

The exact companion source is local website commit **`e21e2b8901ef4c8892fbd6e6ddf31d83d5a8ba42`**, branch `codex/douyin-clips-20261022`, based on merged website main `721cca8`. It adds an authenticated bounded short-link resolver, a manually confirmed Douyin admin source, and `include=youtube,douyin` on the track-clips endpoint. Existing native auth/media/library dependency manifests remain unchanged.

An older website API rejects the new option and this client displays a retry state; this is a website-first deployment dependency. Default old clients keep file-only clips and YouTube-only clients do not receive Douyin items. No production API, short link, video publication or real-video HTTPS cross-repository path was exercised in this task.

## Local verification and investigation

`verification.json` records completed checks, toolchain and exclusions. Tests use a synthetic video ID and a locally generated WKWebView document, not a public Douyin video. UI fixtures are restricted to Mock + DEBUG + Simulator and have an explicit “local UI test / no real video” label; they must not be represented as published footage or store screenshots.

The initial local container test failed because WebKit normalized the wrapper root URL to end in `/`, while the navigation delegate compared against an otherwise equivalent root without `/`. A diagnostic run confirmed `same host = true`, `root = true`, `exact URL = false`. The fix accepts only the two equivalent root forms, while rejecting query/fragment, credentials, ports, different origins and other/encoded paths. A focused regression checks those boundaries, and the WKWebView test attaches to a foreground window to match actual UI presentation. Original failed results remain in the ignored `.build/douyin-validation/` directory; they were not classified as unexplained environment noise.

Screenshot inspection also found compressed headings and a clipped load label at maximum accessibility text, despite the controls remaining reachable. The clip heading and source information now stack at those sizes, and the Douyin load text/hint flow below the cover instead of being cropped inside it. Normal text keeps the existing selected portrait-card layout. The affected UI cases were rerun after this correction.

Local Xcode is **27.1 (27A9275)**, with an iPhone 17 Pro simulator on iOS **26.4**. This is not the repository-pinned Xcode 26.4.1 hosted CI, a distribution signature, VoiceOver speech acceptance or an actual iPhone/real-short playback test.

## Deferred release requirements

After 1.0 is live, obtain owner-supplied videos and verify official embedding, account/region behavior, audio, failure fallback and HTTPS delivery on the target phone. Review/publish the provider privacy delta and corresponding Apple answers before distribution. Preserve the deployed website's L29/L31 image variants and L30 effective privacy overlays when preparing the later website package; do not replace production with an empty-private-novel local build. Then deploy the reviewed website API first and separately authorize signing/upload of the iOS update. No step here implies automatic deployment when 1.0 changes status.
