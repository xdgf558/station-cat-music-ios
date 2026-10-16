# Platform reliability batch — 2026-10-16

Local development candidate: **0.1.0 (8)**. No website deployment, phone installation, TestFlight upload, native-service activation or production association change was performed in this batch. The previously uploaded build 7 remains a separate delivery.

## Delivered behavior

- `PlatformMusicLink` validates the exact HTTPS website host, ordinary unencoded song path and one nonempty slug (1–100 ASCII bytes). Root, zh-hant, zh-hans, en and ja song paths work with or without the terminal slash.
- Only `utm_source`, `utm_medium`, `utm_campaign`, `utm_content` are accepted alongside a song slug. Each occurs at most once and contains 1–128 ASCII letters/digits or `._~-`; the encoded query is capped at 640 bytes. Unknown, duplicate, empty, credential/redirect-like, fragment and encoded-path inputs are rejected. Attribution stays in the current navigation context, is replaced with the latest valid link, and is neither persisted nor sent to analytics or external platforms. Sharing uses the canonical URL without attribution.
- Canonical `/music/tracks/{slug}/` links request the existing no-store detail endpoint directly. They can open before the catalog finishes or after it fails, including a song not in either loaded list. Returned slug, UUID, locale, canonical href and platform URLs still pass the existing projection checks. A catalog that omits the selected song cannot revoke its independently loaded detail. Request generation, locale and account scope reject late responses. No audio/grant is requested.
- Historical `?track=<UUID>` links retain their existing catalog-ID lookup compatibility; the new direct resolver is for canonical slug links. No native UUID/audio endpoint was opened as a fallback.
- A 404 means the address is missing **or withdrawn**; the public server intentionally does not expose which. A 410, if returned, has a withdrawn message. Offline, timeout, service and malformed-data failures have separate messages and retry. We do not infer a withdrawal merely from catalog absence.
- Favorites still live in `ScopedLibrary`. The count and rows come from saved IDs, not the online catalog. A fresh permitted snapshot shows title/artist offline; missing/expired/corrupt presentation shows a saved-work placeholder, never an empty favorite list. Every detail/platform-opening attempt revalidates online; cached names never restore platform buttons. Any row can be removed without network access.

## Explicit minimal-cache contract

The paired website change adds `GET|HEAD /api/station/content/tracks/{slug}/bookmark?locale=…`:

```json
{"schemaVersion":1,"locale":"en","bookmark":{"id":"<UUID>","slug":"<canonical-slug>","revision":1,"title":"…","artist":"…"}}
```

Success: `Cache-Control: private, max-age=86400, must-revalidate`, both CDN controls `no-store`, explicit `Date`. Failures retain `no-store`. Publication/locale/schema checks and catalog admission still apply. No R2 or private audio check is needed for this text-only response.

The client **never copies a no-store catalog/detail response to disk**. Only the dedicated cache-authorized projection can become a `PlatformBookmark`. HTTP age/Date and transfer duration conservatively reduce freshness; no-store, max-age=0, Vary or Set-Cookie denies persistence. A mismatched UUID/slug/locale is rejected. Only ID, slug, revision, title, artist, locale and cache times are serialized; no cover, outbound URL, availability, audio URL, credentials or tracking source.

`PublicMusicBookmarks-v1` is a disposable cache separate from favorites and private journals: environment/account hashed filenames, atomic protected files, excluded from backup, at most 5,000 records / 2 MiB per scope, 64 scopes and 16 MiB total. Clock rollback hides metadata without deleting the complete copy; corruption is a miss repairable by a later valid response. Symlinks are rejected. OS cache eviction or cache failure leaves favorite relationships intact. Optional cache fetches run in groups of at most three after catalog display.

Cached names may remain on a device until their finite lifetime expires. Withdrawal cannot remotely erase previously downloaded presentation. Online no-store details remain the source of current platform availability.

## Independent Universal Links preparation

Website `STATION_PUBLIC_APP_LINKS_ENABLED=true` additionally requires profile `station-cat-music-platform-links-v1` and enabled public content. Without that deliberate deployment, existing association behavior remains unchanged. The public profile returns only `applinks` for `2AM5S7BM2N.org.stationcat.music`, claims localized song routes and legacy music-root track queries, and excludes nested song routes and fragments. It contains no native callback or webcredentials.

AASA matching is routing, **not full query validation**. Apple pattern matching does not express the entire client allowlist/length/duplicate policy; the client independently enforces it. The shared matrix is a local contract test, not proof of Apple CDN delivery.

All four checked-in iOS configurations keep `STATION_PUBLIC_APP_LINKS_ENABLED=NO`, public metadata defaults closed, and native flags closed. `Config/PlatformLinks.entitlements` is an unselected artifact containing only `applinks:wwwstationcat.org`. A future approved Production candidate must explicitly select that file and public metadata/link settings, then pass `scripts/check_platform_links.py` against its exported **signed** entitlements. `check_platform_release.py --public-links-entitlements <plist>` also requires the signed team/application identity and still rejects native activation.

Before enabling: deploy/recheck the paired website, verify AASA at origin and Apple CDN, verify signed entitlements/provisioning, and separately exercise cold/warm links on a device from an external app in all supported locales. This batch does not claim those checks or third-party platform handoff acceptance.

## Local evidence

See `platform-reliability-20261016/verification.json`. Toolchain actually used: Xcode **27.1 (27A9275)**, iOS **27.0** simulator. The repository CI remains pinned to its configured Xcode; no current remote CI success is claimed here.

- Full Swift suite: 288 cases, **265 passed / 23 dedicated integration probes skipped / 0 failures**. Skipped probes require their isolated service/fixture drivers; they were not replaced by mocks and called complete.
- Six UI tests passed, including four locales/large type, opening failure/copy, no native playback, offline terminate/relaunch favorites, and build 8 release notes.
- Follow-up after presentation-cache repair and final row/status changes: 19 relevant unit tests and one offline-relaunch UI test passed.
- [Offline favorites UI screenshot](platform-reliability-20261016/offline-favorites.png): persisted labels and favorite count survive a terminated-app relaunch with catalog requests failing, with a retry action and removable rows.
- Python release inspection 8/8; public-link signing/config validation 3/3; source guards and diff whitespace checks passed.
- Mock, Development, Staging and Production builds passed. Packaged version/build and four-language localization bytes match source; default link/native flags are closed.
- Website public/runtime suite 60/60; association/new-contract suite 84/84; 181-page development build and postbuild passed. Website build used `ALLOW_EMPTY_SERIAL_CONTENT=1` and is not a deployable production package.

The first full local run used `CODE_SIGNING_ALLOWED=NO`, causing three real Keychain failures (-34018). Two older presentation mocks also lacked the new direct-resolution protocol. Those failures were preserved in `.build/platform-reliability-full.xcresult`; the mocks were completed and the full suite rerun with normal simulator signing, with zero failures. No Keychain or production authentication code was weakened.

The same 56-case link fixture is stored in both repositories. SHA-256: `1dce0ad82c4f2b491b908396470518cdbcc5111abbd81d5150501577f6a6db40`. API decoder tests and actual Miniflare/D1 route tests validate opposite sides of the cache contract; no live production end-to-end run is claimed.

## Workspace preservation and next delivery

Preexisting TestFlight build-7 preparation changes were left in place, including legal links, privacy manifest, release inspection, App Store drafts and upload evidence. A before-change patch/list lives in ignored `.build/platform-reliability-checkpoint/`. The new build increments version notes rather than overwriting their history.

Review the website and iOS changes together, deploy the website before a build relying on bookmark metadata, then prepare the separately signed public-links candidate. An older website safely yields favorites with placeholders. Neither merging nor an installed build alone proves system Universal Links delivery.
