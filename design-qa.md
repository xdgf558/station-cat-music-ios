# Quiet Orbit — native iOS design QA

Date: 2026-09-24. Final result: passed

## Source and capture

Selected visual truth: `/Users/shaola/.codex/generated_images/01a08db7-d4ce-70b2-8601-d043a703f12b/exec-c4bae6ff-ffc0-4e9d-a376-866011dfe96c.png` (user selected option 3).

Implementation: native SwiftUI, iPhone 17 Pro simulator, iOS 26.4.1, local Xcode 27 beta 6. Viewport 402 × 874 points; screenshots 1206 × 2622 pixels, density 3. Source 853 × 1844 pixels is a concept without an OS status bar. Full comparisons normalize both to 402 pixels wide, preserving their aspect ratios. CSS/browser runtime checks do not apply to this native app.

- Full combined comparison: `docs/previews/orbit-comparison.png`
- Focused title and playback controls comparison: `docs/previews/orbit-controls-comparison.png`
- Final implementation: `docs/previews/orbit-discover.png`
- Additional actual captures: `orbit-catalog.png`, `orbit-library.png`, `orbit-queue.png`, `orbit-settings.png`, `orbit-accessibility.png`, `orbit-staging-lyrics.png` in the same directory.
- Four-screen contact sheet: `docs/previews/orbit-overview.jpg`.

Comparisons were opened as combined source/implementation images. Focused controls were also opened at readable scale. Screens show Mock songs or the isolated synthetic fixture, not a production account. The comparison is a design-direction match, not a claim of identical catalog content or identical system chrome.

## Comparison history

1. Initial capture (`orbit-discover-initial.png`): P2 — 330-point record pushed the recommendation shelf below the viewport and its rectangular background edge was visible. Reduced the record to 250 points, tightened section spacing, feathered the raster edges, and used a horizontal shelf for both real featured collections and Mock recommendations. Revised combined capture confirms the shelf now enters the first viewport and the hard image boundary is softened.
2. Isolated player capture: P2 — lyrics began too low and lower lines were obscured by the dock. Switched the navigation title to inline, reduced the record to 180 points when timed lyrics exist, and moved preview into the bottom controls. Final `orbit-staging-lyrics.png` shows both fixture lines above the fixed controls without requiring the lyrics disclosure or an extra tap.
3. Queue UI test initially found two buttons labelled Close in nested sheet accessibility snapshots. Added a distinct `queueClose` identifier and exercised opening/closing the queue. Final complete navigation run passes.

## Required fidelity surfaces

- Typography: native SF rounded headline, SF body and system CJK fallback retain the clear sans-serif hierarchy of the reference. Actual long bilingual Mock song names wrap/occupy more space than the short concept title. Dynamic Type remains enabled; four locales at Accessibility XXXL retain all three tabs and scrollable content.
- Layout: 22–24-point page insets, central record, centered discovery title, horizontal recommendation shelf, compact mini-player and five-button playback row retain the chosen structure. Native safe areas and iOS tab-bar material consume extra height; the album shelf scrolls rather than compressing content behind fixed chrome. The mini-player is asserted to remain above the tab bar.
- Color: midnight background, blue/violet record lighting, pale-violet accent, white primary text and cool-gray secondary text. Native disabled controls are dimmed. Destructive privacy controls remain semantically red. The reference's brighter neon play ring is simplified to a quieter violet border; this is a minor aesthetic difference, not a broken state.
- Images: generated raster record/tonearm and planet background follow the selected art direction. Real allowed artwork URLs use the existing bounded cached loader. The circular record center and square thumbnails use the generated rooftop art only as a generic fallback; it is not represented as an actual song cover. The user's final neon cat icon remains the brand asset. No fake rasterized UI text or controls are embedded in art.
- Copy/content: actual catalog titles, artist names, collection sizes, playback position and duration are preserved. Concept song names and invented albums were not added to catalog data. Mock/isolated disclosure remains visible in its respective configuration. Lyrics use the existing audio-version-aligned detail and preview offset; current text is bold/white and other lines are subdued, with reduce-motion-aware following.

## Verification

Final `.build/orbit-ui-verified.xcresult`: 8 MusicLinkInitializationTests + 3 NavigationTests, 0 failures. The UI flow includes player opening without autoplay, queue open/close, search, mini-player/tab separation, privacy toggle persistence and confirmation, and four locales at maximum Dynamic Type. Mock test build and isolated Staging build succeeded. Source guards and `git diff --check` passed. Actual HTTPS isolated fixture opened via its configured music link and rendered timed lyrics; no login or production enablement was performed for this visual check.

No actionable P0/P1/P2 visual finding remains in these captured states. Follow-up P3 polish: consider a brighter play-ring accent if desired after user review.

## Limits

No new physical-iPhone acceptance, iOS 18 runtime capture, AirPlay/background playback acceptance, production release or App Store submission is claimed. Existing R3 physical-device work is separate. The shown staged fixture has no supplied cover, so these captures verify fallback composition, not a newly observed remote-artwork download. Account mutations, authorization, personal-library persistence and audio Core implementations were not changed.

Final result: passed


# Follow-up: two-level “You” navigation

Date: 2026-09-24. This section is the latest design QA for the scoped library change.

## Target and evidence

Source visual: `/Users/shaola/Downloads/截屏 2026-09-24 03.30.24.png` (1260 × 2736). The requested target is a structural redesign into first/second-level pages while retaining this screenshot's existing Quiet Orbit style; identical content placement would contradict the request.

Implementation: native iPhone 17 Pro simulator, iOS 26.4.1, 402 × 874 points / 1206 × 2622 pixels at 3×. Captures are Mock guest data, with a selected sample song to exercise the persistent mini-player. Source and implementation are normalized to equal 402-pixel widths without changing aspect ratio. Source is a physical Staging guest view without a selected track; its sign-in controls are therefore different from the Mock capture, and it has a slightly different screen height.

Full combined source/new-home/new-privacy comparison: `docs/previews/library-hierarchy/comparison.jpg`. Three-screen preview: `docs/previews/library-hierarchy/overview.jpg`. Full-resolution captures in that folder: `home.png`, `account.png`, `favorites.png`, `history.png`, `privacy.png`, `preferences.png`, `help.png`, `accessibility.png`. Full-size root, privacy and accessibility screenshots were also opened separately for legibility. No additional focused crop was necessary: all labels and controls are readable in those full-size views.

## Findings and changes

The old page mixed profile, authentication, deletion receipts, full music lists and destructive settings into a long form. The new first level contains six entry points: account/security, favorites, recent history, privacy/storage, preferences, about/support. Each opens a native second-level page with a back button. Favorites and history counts describe the same available track arrays used by their lists. Queue snapshots still come from those lists. Existing sign-in/out, deletion confirmation, receipt lookup, sync status, history setting, cache clearing, local cleanup confirmation and legal links remain reachable.

Typography retains system SF/CJK sizing and hierarchy. Spacing uses a compact profile card, a two-column music grid and grouped setting rows; accessibility sizes use one grid column with wrapping. Midnight artwork, panel colors, lavender accents and destructive red remain unchanged. Existing cat/icon/background rasters are reused without new fabricated images. Copy is localized in four languages; the favorites empty state now describes songs rather than calling real catalog songs samples. Back navigation and persistent playback controls use native elements.

Initial English hierarchy tests passed. The additional Chinese test with a selected track exposed inherited page accessibility identifiers replacing the mini-player button identifier. Moving the identifier to the form before attaching its playback inset fixed this. One subsequent attempt failed before tests because the simulator runner was Busy; the final run used the booted simulator serially and passed. Final captures show the mini-player above the tab bar on both levels. There are no actionable P0/P1/P2 visual findings in the captured states.

## Validation and limits

Final `.build/library-hierarchy-final.xcresult`: 4 navigation tests, 0 failures, 125.538 seconds. Coverage includes all six destinations and back navigation in Chinese, selected mini-player position on every destination, four locales at Accessibility XXXL, privacy setting persistence across relaunch and clear-history cancellation, catalog search and player/queue regressions. Mock build, signed Staging iOS build, source guards and diff whitespace checks passed.

The isolated system-login UI driver now enters Account & security before operating login and cleanup. Its real HTTPS/browser flow was not rerun for this layout change; no new authentication acceptance is claimed. Core auth/playback/personal-library code and production settings were not changed. The previously used iPhone Air was unavailable, so this follow-up was not installed there. Another paired phone was not used as a substitute.

final result: passed


## Startup showcase — selected first image (2026-09-24)

Initial comparison: `docs/previews/startup/comparison-initial.jpg`. Source `docs/previews/startup/selected-reference.png` (853×1844); implementation from `.build/startup-showcase.xcresult` (1206×2622, 402×874pt at 3×), normalized to 390px width preserving each aspect ratio. Standard-size Chinese loading and English failure were compared; the source is loading only, failure is an intentional additional recovery state.

Initial findings: [P2] the outer accessibility identifier propagated to normal-layout buttons and loading text; remove it so leaf identifiers and hidden decorative artwork remain correct. [P2] large-text content scrolled over the stationary cat art, reducing text contrast; move the hero into the large-text scroll flow and retain a solid navy reading surface below it. Normal-size typography, artwork position, palette and copy otherwise match the selected design.

Final result for this initial pass: blocked. Re-capture after those two fixes is required.

### Startup showcase recheck — final

- Source visual truth: `docs/previews/startup/selected-reference.png`.
- Implementation: `docs/previews/startup/loading.png`, `failure.png`, and `accessibility-{en,zh-Hans,zh-Hant,ja}.png`.
- Full comparison: `docs/previews/startup/comparison-final.jpg`; focused type and indicator comparison: `docs/previews/startup/type-detail.jpg`.
- Native viewport: 402×874 pt, 3× capture, 1206×2622 px. Reference 853×1844 px (~390×844 design). Full comparisons preserve aspect ratio at 390px width; detail is normalized at 402px width. A narrow native aspect-ratio difference is expected. OS status bar is hidden during startup; no raster device chrome is embedded.
- States: loading, failure, largest Dynamic Type failure scrolled to recovery controls. Failure and large-text layouts are intentional accessibility/recovery additions beyond the loading-only mock.

The two initial P2 findings are fixed: identifiers remain on actual actionable leaf views, and accessibility artwork scrolls with the content rather than under the text. Final three startup UI tests pass with screenshots from `.build/startup-showcase-fixed.xcresult`. The earlier run passed all 46 selected logic tests and the four existing navigation/UI cases; its two initial startup UI failures remain recorded rather than claimed as clean first-run results.

Required fidelity surfaces: native SF system typography closely matches the white title, spaced lilac MUSIC label and centered Chinese tagline. Position and spacing follow the mock at 62.5%, 71% and 84% of height. Palette remains navy/white/lilac with a correctly sharp bundled neon-cat illustration and preserved planet crop; no raster UI text or replacement hand-drawn artwork. Copy matches the selection, with four-language equivalents. Native error controls are readable, at least 44pt high, and reachable in all four largest-type captures. Reduce Motion selects static dots and disables the fade; this behavior was code-checked, not tested with an actual VoiceOver user or physical accessibility settings.

Residual P3: native SF letter metrics and the generated starfield differ slightly from the mock; neither affects hierarchy or usability. No actionable P0/P1/P2 findings remain.

final result: passed
