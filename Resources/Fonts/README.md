# Radio serif fonts

The app ships one unchanged, complete Noto Serif SC variable file. `SOURCE.json` records its fixed Google Fonts commit, original filename, size and hashes; `METADATA.pb` and `OFL.txt` preserve the upstream metadata and SIL Open Font License 1.1. There is no added TC/JP font download or second/third 25 MB bundled file.

## Locale and glyph selection

`RadioTypography.serif(size:weight:locale:)` requires an explicit locale. `RadioFont` obtains it from SwiftUI's locale environment; the direct lyric renderer passes the app locale too. Simplified Chinese and English use the bundled SC face with an explicit `wght` axis. Traditional Chinese first tries the operating system's Songti TC family when available, otherwise uses a language-aware native TC face. Japanese selects the available Hiragino Mincho ProN family. A region does not override an explicitly requested Hans script.

The bundled font's metadata identifies `primary_script: Hans`. A read-only inspection of its GSUB script/language records found the `ZHS` language system for `hani`/`kana`, with no `JAN` or `ZHT` records. Presence of a Unicode character in this font does not establish a Traditional Chinese or Japanese regional glyph. Changing the SwiftUI locale while retaining this SC face is therefore not used as a regional-font fix.

Apple's [System Fonts catalog](https://developer.apple.com/fonts/system-fonts/) lists Songti TC Light, Regular and Bold, and Hiragino Mincho ProN W3 and W6 for iOS. This catalog is not proof that every listed face is preinstalled. The runtime checks the requested named UIFont. Available TC faces use Light/Regular/Bold; JP uses W3 for regular/lighter text and W6 for semibold/heavier text. These are supplied family weights, not invented 900-weight axes. If a named face is absent, a native serif's [language-aware Core Text cascade](https://developer.apple.com/documentation/coretext/ctfontcreateforstringwithlanguage(_:_:_:_:)) chooses a regional font; the bundled SC face is never used as the TC/JP fallback.

An independent probe on the current **iOS 26.4 Simulator** confirmed both `SongtiTC-{Light,Regular,Bold}` and `STSongti-TC-{Light,Regular,Bold}` are unavailable. Its Traditional Chinese fallback is **PingFang TC**, which has native TC glyphs but is **sans serif**. `HiraMinProN-W3` and `HiraMinProN-W6` are available for Japanese. This deliberate compromise prioritizes correct regional glyphs and finite package size over claiming an unavailable TC serif; it does not install/download fonts or claim identical rendering on a physical device. Ignored local probe records are kept under `evidence/radio-review/`.

No Apple font file is copied into the project or redistributed. The bundled Noto file remains unchanged and retains its original license.

## Reuse and scaling

An NSCache with `countLimit = 96` reuses immutable CTFont instances. A lock covers lookup, miss creation and insertion, so simultaneous views requesting the same key do not repeatedly construct a descriptor. The key includes the resolved regional family, exact scaled point-size bits and requested weight. The cache does not store a pre-scaled SwiftUI Font, so changes to Dynamic Type or locale select the appropriate instance rather than reusing an old size or regional face.

Apple documents that [font objects are immutable and safe to use from multiple threads](https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/CustomTextProcessing/CustomTextProcessing.html). NSCache can evict entries, including under memory pressure; a later miss safely recreates the font.

`RadioTypographyTests` covers the bundled SC axis/glyphs, available JP faces, TC region selection without requiring an unavailable serif, the native language fallback path, exact accessibility-scaled sizes, and concurrent same-key reuse. Simulator results and four-language native screenshots are recorded separately by the release workflow; these tests do not establish physical-device rendering or distribution acceptance.
