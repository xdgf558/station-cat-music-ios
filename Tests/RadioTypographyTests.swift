import XCTest
import SwiftUI
import CoreText
import UIKit
@testable import StationCatMusic

final class RadioTypographyTests: XCTestCase {
    func testBundledChineseSerifHasRealVariableWeightsAndChineseGlyphs() {
        for locale in ["zh-Hans", "zh-Hans-HK", "en"] {
            for (weight, value) in [(Font.Weight.regular, 400.0), (.bold, 700.0), (.black, 900.0)] {
                let font = RadioTypography.serif(size: 34, weight: weight, locale: Locale(identifier: locale))
                XCTAssertEqual(CTFontCopyFamilyName(font) as String, "Noto Serif SC")
                let axes = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
                XCTAssertEqual(axes?[NSNumber(value: 0x77676874)]?.doubleValue, value)
                assertGlyphs("电台唱片架筆記本你唔使硬撑", font: font)
            }
        }
    }

    func testTraditionalChineseAndJapaneseSelectTheirRegionalFaces() {
        for locale in ["zh-Hant", "zh-TW", "zh-HK", "zh-MO"] {
            let regular = RadioTypography.serif(size: 24, weight: .regular, locale: Locale(identifier: locale))
            let bold = RadioTypography.serif(size: 24, weight: .bold, locale: Locale(identifier: locale))
            assertTraditionalFace(regular)
            assertTraditionalFace(bold)
            assertGlyphs("骨直令返邊電臺筆記", font: regular)
        }
        for locale in ["ja", "ja-JP"] {
            let regular = RadioTypography.serif(size: 24, weight: .regular, locale: Locale(identifier: locale))
            let bold = RadioTypography.serif(size: 24, weight: .bold, locale: Locale(identifier: locale))
            XCTAssertEqual(CTFontCopyPostScriptName(regular) as String, "HiraMinProN-W3")
            XCTAssertEqual(CTFontCopyPostScriptName(bold) as String, "HiraMinProN-W6")
            assertGlyphs("骨直令返辺曲片あいう", font: regular)
        }
    }

    func testNativeRegionalFallbackKeepsTheRequestedRegionAndPointSize() {
        for weight in [400.0, 700.0] {
            let traditional = RadioTypography.nativeRegionalFallback(size: 43, weight: weight, language: "zh-Hant")
            assertTraditionalFace(traditional)
            XCTAssertEqual(CTFontGetSize(traditional), 43)
            assertGlyphs("骨直令返邊電臺筆記", font: traditional)
            let japanese = RadioTypography.nativeRegionalFallback(size: 43, weight: weight, language: "ja")
            XCTAssertEqual(CTFontCopyFamilyName(japanese) as String, "Hiragino Mincho ProN")
            XCTAssertEqual(CTFontGetSize(japanese), 43)
            assertGlyphs("骨直令返辺曲片あいう", font: japanese)
        }
    }

    @MainActor func testCachePreservesTheActualScaledSizeWeightAndLocale() {
        let base = RadioTypography.serif(size: 34, weight: .regular, locale: Locale(identifier: "zh-Hans"))
        let repeated = RadioTypography.serif(size: 34, weight: .regular, locale: Locale(identifier: "en"))
        XCTAssertTrue((base as AnyObject) === (repeated as AnyObject), "Equivalent family requests reuse the immutable font")
        let scaledSize = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 34,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        let scaled = RadioTypography.serif(size: scaledSize, weight: .black, locale: Locale(identifier: "zh-Hans"))
        XCTAssertGreaterThan(scaledSize, 34)
        XCTAssertEqual(CTFontGetSize(scaled), scaledSize)
        XCTAssertEqual((CTFontCopyVariation(scaled) as? [NSNumber: NSNumber])?[NSNumber(value: 0x77676874)]?.doubleValue, 900)
        let traditional = RadioTypography.serif(size: scaledSize, weight: .bold, locale: Locale(identifier: "zh-Hant"))
        XCTAssertEqual(CTFontGetSize(traditional), scaledSize)
        assertTraditionalFace(traditional)
    }

    func testConcurrentCacheMissCreatesTheSharedFontOnlyOnce() {
        let cache = RadioTypography.Cache()
        let count = CreationCount()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            _ = cache.font(for: "same-font") {
                count.increment()
                return CTFontCreateWithName("TimesNewRomanPSMT" as CFString, 24, nil)
            }
        }
        XCTAssertEqual(count.value, 1)
        _ = cache.font(for: "other-size") {
            count.increment()
            return CTFontCreateWithName("TimesNewRomanPSMT" as CFString, 48, nil)
        }
        XCTAssertEqual(count.value, 2)
    }

    private func assertGlyphs(_ text: String, font: CTFont, file: StaticString = #filePath, line: UInt = #line) {
        var characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count), file: file, line: line)
        XCTAssertFalse(glyphs.contains(0), file: file, line: line)
    }

    private func assertTraditionalFace(_ font: CTFont, file: StaticString = #filePath, line: UInt = #line) {
        let name = CTFontCopyPostScriptName(font) as String
        XCTAssertTrue(name.contains("TC"), "Expected a Traditional Chinese face, got \(name)", file: file, line: line)
        XCTAssertNotEqual(CTFontCopyFamilyName(font) as String, "Noto Serif SC", file: file, line: line)
    }

    private final class CreationCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func increment() { lock.withLock { count += 1 } }
    }
}
