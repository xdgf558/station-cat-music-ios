# Quiet Orbit visual assets

Selected by the user as option 3 on 2026-09-24. Implemented in native SwiftUI.

- `OrbitRecord`: generated 1024-square vinyl/tonearm artwork. The tonearm is baked in, so the whole image must not rotate. Dynamic cover is placed at normalized center (0.488, 0.492), diameter 0.49. A gentle edge mask blends the background; this is not a screenshot of controls.
- `OrbitBackground`: generated 1024 × 1536 midnight/planet raster, JPEG.
- `OrbitCover`: generated 1024-square rooftop person-and-cat artwork, JPEG. Generic fallback only; no fabricated catalog data or embedded song title.
- `OrbitBrand`: downsample of the user's chosen final cat/headphones AppIcon. Original user source was `ChatGPT Image 2026年9月23日 21_49_05.png`; the approved full-bleed icon removes the original outer mask/background framing for the system icon mask.
- Fonts: native system fonts and system CJK fallback. Interface symbols: Apple SF Symbols used through SwiftUI.

Resources reside in `Resources/Assets.xcassets`. Existing artwork host/security/cache policy remains in Core. No production data, account credentials or authentication screenshots are included in previews.
