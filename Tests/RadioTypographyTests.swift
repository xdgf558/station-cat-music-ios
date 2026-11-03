import XCTest
import SwiftUI
import CoreText
@testable import StationCatMusic

final class RadioTypographyTests: XCTestCase {
    func testBundledChineseSerifHasRealVariableWeightsAndChineseGlyphs() {
        for (weight, value) in [(Font.Weight.regular, 400.0), (.bold, 700.0), (.black, 900.0)] {
            let font = RadioTypography.serif(size: 34, weight: weight)
            XCTAssertEqual(CTFontCopyFamilyName(font) as String, "Noto Serif SC")
            let axes = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
            XCTAssertEqual(axes?[NSNumber(value: 0x77676874)]?.doubleValue, value)
            var characters = Array("电台唱片架筆記本你唔使硬撑".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count))
            XCTAssertFalse(glyphs.contains(0))
        }
    }
}
