import XCTest
@testable import StationCatMusic

final class RadioDialTests: XCTestCase {
    func testDialUsesSevenPointsPerTenthAndClampsToTheScale() {
        XCTAssertEqual(RadioDial.dragged(from: 88.6, translation: -7), 88.7, accuracy: 0.0001)
        XCTAssertEqual(RadioDial.dragged(from: 88.6, translation: 10000), 87.5)
        XCTAssertEqual(RadioDial.dragged(from: 88.6, translation: -10000), 108)
        XCTAssertEqual(RadioDial.dragged(from: .nan, translation: 0), 88.6)
    }
    func testSnappingOnlyUsesTheCurrentRealCatalogAndWraps() {
        XCTAssertNil(RadioDial.nearest(90, count: 0))
        XCTAssertEqual(RadioDial.nearest(106, count: 2), 1)
        XCTAssertEqual(RadioDial.nearest(94.8, count: 6), 2)
        XCTAssertEqual(RadioDial.adjacent(0, by: -1, count: 3), 2)
        XCTAssertEqual(RadioDial.adjacent(2, by: 1, count: 3), 0)
        XCTAssertNil(RadioDial.adjacent(0, by: 1, count: 0))
    }
}
