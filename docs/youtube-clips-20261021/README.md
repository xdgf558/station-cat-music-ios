# YouTube song clips — 1.0.1 (14)

2026-10-21. The user selected the first displayed design and requested implementation without supplying videos yet. This is a separate local development candidate from the submitted 1.0 (13). No production clip, install, distribution signature, TestFlight upload, App Store submission or deployment was performed.

## Delivered behavior

The song's Clips tab keeps the existing navy/purple theme, identity header and lyrics/story navigation. It contains up to three published clips. A YouTube item uses a compact portrait viewport; its initial image is explicitly the **song cover**, not a claimed YouTube thumbnail. The user taps to load the official player, then uses its own controls. It never autoplays on opening a song or changing tabs.

Before creating an embed or using the explicit YouTube fallback, the client re-requests the clip list and matches the complete clip identity/revision/source. Dismissal, song/language changes, tab changes, backgrounding, privacy-sheet opening and external handoff cancel pending verification and tear down the WebView. A late result cannot resurrect it. There is no download, extracted audio, background audio, AirPlay, PiP or native playback grant. A live embed cannot be remotely erased instantaneously; fresh validation applies on each new open, and YouTube can separately revoke access.

`YouTubeClipSession` uses the official IFrame API in an ephemeral `WKWebView`, `youtube-nocookie.com`, autoplay disabled, required user gesture, a strict local document CSP, and the bundle identity `https://org.stationcat.music` as base URL/origin. Per [YouTube's WebView guidance](https://developers.google.com/youtube/terms/required-minimum-functionality), the local HTML base URL supplies the Referer. Only a validated 11-character video ID and a generated UUID enter HTML. No title, UTM field, arbitrary HTML, token or signed media URL is interpolated.

Official player branding, controls, ads and nested HTTPS frames are preserved. App-owned controls remain outside the player. Explicit player links/popups hand off through the system opener (HTTPS only; no credentials/ports). The player does not become a general in-app browser. No playback is inferred from the system accepting a URL. Failure offers retry and a fresh-validated YouTube link; a system rejection retains the copy-link fallback.

At normal type sizes the primary listening button remains at the bottom. At accessibility sizes it scrolls with content so it cannot cover the tabs or reading area. The information button presents the new third-party disclosure and official terms/privacy links. Four language UI strings and release notes are included; 1.0 (13) notes remain in history.

## Website dependency

The companion website commit is [`d7eebffd00c7b5931956e67e6206f49c421634d1`](https://github.com/xdgf558/caption-ai-landing-site/commit/d7eebffd00c7b5931956e67e6206f49c421634d1), branch `codex/ios-youtube-clips`, based on website `d382c81d05569a1219077636a0318567016fd982`. It adds the explicit `include=youtube` option to the track clips endpoint, with revision-bound references and a corresponding admin source selector. Deploy the reviewed website API first. An older API rejects the new option; the client shows the section's retry state rather than interpreting an unknown response as playable content. Old clients continue receiving file-only clips from the new API. Existing native auth/media/library fixture manifests are unchanged. The companion follow-up only fixes its staging import-test allowlist and records the initial CI failure; API and product source are unchanged. This dependency identifies the locally verified source; it is not evidence of a live HTTPS cross-repository deployment.

The owner has not supplied real links. Public production content remains empty. The test fixture's video ID and “local UI test” page are not published footage, do not contact YouTube and must not appear in store screenshots or release evidence as actual playback.

## Validation and boundaries

See `verification.json` and the root `design-qa.md` for final local results. Tests cover strict source/ID projection, explicit opt-in, malformed/mixed payload rejection, fresh publication checks, late cancellation, ephemeral WKWebView readiness, error/retry and external fallback, tab/background/dismiss teardown, the existing file player and lyric reader, and four locales with maximum accessibility text.

Local toolchain: Xcode 27.1 (27A9275), iPhone 17 Pro simulator on iOS 26.4, 402 × 874 points / 1206 × 2622 pixels. This is not the repository's pinned Xcode 26.4.1 hosted CI, a signed package, physical-device/VoiceOver acceptance, or a real published-short HTTPS end-to-end test. All submitted configuration files keep public/native service flags closed. Production Info.plist/version and bundled four-language notes are separately checked locally.

Before distributing: obtain and verify actual owner-supplied Shorts URLs, review/publish the [privacy delta](../app-store/youtube-1.0.1-privacy-delta.md), recheck Apple privacy answers, run hosted CI and the real HTTPS/device handoff cases, then separately authorize deployment/signing/upload. This task does not alter the pending 1.0 review.
