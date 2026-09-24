import XCTest
@testable import StationCatMusic

final class CatalogFailureTests: XCTestCase {
    func testClassifiesNetworkWithoutMislabelingServiceOrConfiguration() {
        XCTAssertEqual(CatalogFailure(URLError(.timedOut)), .timeout)
        XCTAssertEqual(CatalogFailure(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(CatalogFailure(URLError(.dataNotAllowed)), .offline)
        XCTAssertEqual(CatalogFailure(URLError(.cannotFindHost)), .connection)
        XCTAssertEqual(CatalogFailure(URLError(.networkConnectionLost)), .connection)
        XCTAssertEqual(CatalogFailure(URLError(.serverCertificateUntrusted)), .connection)
        XCTAssertEqual(CatalogFailure(APIError.rejected(403)), .service)
        XCTAssertEqual(CatalogFailure(APIError.rejected(503)), .service)
        XCTAssertEqual(CatalogFailure(APIError.networkDisabled), .configuration)
        XCTAssertEqual(CatalogFailure(APIError.invalidPayload), .payload)
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Private body must not appear"))
        XCTAssertEqual(CatalogFailure(decoding), .payload)
        XCTAssertEqual(CatalogFailure(NSError(domain: "private", code: 1)), .unknown)
    }
}
