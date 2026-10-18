# Catalog design 2 — native implementation QA

Source: `docs/catalog-categories-20261017/selected-design.png` (853 × 1844). Implemented in native SwiftUI, not a mobile web prototype. Native SF typography/SF Symbols, the existing Orbit raster background/brand and the OS tab bar are retained.

First capture: `.build/catalog-categories-ui-attachments/9BD16DBB-9F9F-41D9-A1AD-42360E10666F.png` (1206 × 2622; iPhone 18 Pro simulator 402 × 874 points at 3×). Both images were opened together in one tool result. The concept has no status bar, so safe-area/OS chrome differences are excluded from content fidelity decisions. State: Simplified Chinese, Albums selected, top scroll position, ordinary text size.

## Iteration 1 findings

- P2 — The 22-point outer stack rhythm leaves the first album row too low and obscures second-row labels behind the native tab bar. Reduced stack spacing to 12, top inset to 6, category hit-height to 44 and grid row spacing to 18; touch targets remain accessible.
- P2 — Search's default placeholder color is too dark. Use the existing `Palette.muted` foreground explicitly.
- P2 — At the largest English accessibility text size, the selected Albums tab is only partially visible. Add a native scroll-to-selection behavior to the category rail. Bound the decorative brand heading at xxxLarge; functional headings, categories and content continue to use the user's Dynamic Type size. Album columns already collapse to one.

First album-detail and AX English screenshots were also opened. Ordered song labels and the native back control were usable. Source illustrative cover/count values are intentionally replaced by representative real cover assets and synthetic test membership/counts; production uses backend metadata and controlled cached artwork.

## Iteration 2

The second full-view comparison used the exact source plus `.build/catalog-categories-ui-v2-attachments/89E738FD-58BB-4441-9273-6AEB7CDCD793.png` together. The new spacing restores both rows' titles/counts above the tab bar and the search placeholder is now legible. These first two P2s are closed.

The scroll-to-selection variant passed Chinese/English but the largest Japanese text still made the horizontal category selection unreliable. The second UI run is retained as a failed accessibility iteration. Replaced the rail with a native category menu only at accessibility text sizes. Standard text retains the selected reference's three underlined tabs. No content typography is reduced to hide an overflow.

## Final comparison and evidence

Latest implementation: `docs/catalog-categories-20261017/Catalog-Albums-zh-Hans.png`. This and the source were reopened together in the same tool result, with `Catalog-Albums-ja-AXXXL.png` as additional evidence. All implementation screenshots are 1206 × 2622, representing a 402 × 874-point native viewport at 3×. The raster concept is compared in width-normalized coordinates (853 px mapped to 402 logical points; its resulting height is about 869 points). There is no CSS viewport or reconstructed device chrome. Native safe-area/status bar differences are intentional, so no false pixel-perfect claim is made.

The whole-screen inputs were large enough to read the brand, title, search prompt, category underline, cover crops and both lines of album text directly. Those regions were inspected in the combined input; an additional magnified crop was unnecessary. `Catalog-Album-Detail.png`, `Catalog-Singles-zh-Hans.png`, `Catalog-Empty-Albums.png` and four `Catalog-Albums-*-AXXXL.png` captures preserve the other interaction states.

- **Typography:** native SF/PingFang and semantic SwiftUI sizes retain the title/heading/secondary-text hierarchy. Long content wraps; functional Dynamic Type continues to grow. The decorative brand is capped at xxxLarge. No truncation blocks the selected category in the final AX menu.
- **Spacing/layout:** 22-point side margins, 16-point column gap, square album covers, 14-point cover corners and 18-point grid row spacing follow the gallery composition. The revised header rhythm keeps both normal-size rows' labels above the OS tab bar. AX uses a scrollable single column and an explicit category menu. Native tab-bar shape/status-bar insets are retained rather than imitated.
- **Colors:** the existing midnight navy background, light primary text, muted blue-grey text and lavender selection/accent match the selected Orbit direction. Search now uses the same readable muted foreground as secondary labels.
- **Images:** supplied brand/background remain sharp. Representative source covers are rendered square without stretching, using the same cover component and clipping as the live catalog. Illustrated cat covers in the concept are not fabricated as real album releases; the product uses actual catalog artwork. This content substitution is intentional.
- **Copy:** category labels/search match the concept in Simplified Chinese and are complete in Traditional Chinese, English and Japanese. Counts derive from the visible ordered membership. The Mock fixture's two-song counts and album names are test data, not production publication claims. The fixture notice is Mock-only.

The final three category UI tests passed, including four locales at the largest accessibility text size, category menu selection, ordered album navigation, song-detail handoff, no native audio controls, search/clear, singles and empty albums. Earlier version-note and existing discovery/detail UI tests also passed. Model/API tests 36/36 and paired public-content tests 64/64 passed. Production-configuration compilation passed; this is local Xcode 27.1 beta evidence, not stable CI or physical iPhone acceptance.

No actionable P0/P1/P2 remains in the captured design states. Larger real catalogs and physical-device layout remain release acceptance work. No publication or installation was performed.

final result: passed
