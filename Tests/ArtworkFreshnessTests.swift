import XCTest
@testable import StationCatMusic

final class ArtworkFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func response(_ fields: [String: String] = [:], generated: Date? = nil) -> HTTPURLResponse {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let defaults = ["Cache-Control": "public, max-age=60", "Date": format.string(from: generated ?? now), "Age": "0"]
        return HTTPURLResponse(url: URL(string: "https://artwork.test/image")!, statusCode: 200, httpVersion: nil, headerFields: defaults.merging(fields) { _, new in new })!
    }
    func testPrivateDeviceCachingStillRejectsCookieVaryAndNoStore() {
        XCTAssertNotNil(ArtworkFreshness.expiration(response(["Cache-Control":"private, max-age=60"]), responseTime: now, storedAt: now, responseDelay: 0, residentTime: 0))
        for fields in [["Set-Cookie":"session=fixture"], ["Vary":"Authorization"], ["Cache-Control":"private, no-store, max-age=60"], ["Cache-Control":"private=Authorization, max-age=60"]] {
            let headers = ["Cache-Control":"private, max-age=60"].merging(fields) { _, new in new }
            XCTAssertNil(ArtworkFreshness.expiration(response(headers), responseTime: now, storedAt: now, responseDelay: 0, residentTime: 0))
        }
    }
    func testVaryAndOldDateAreNotPersisted() {
        for vary in ["*", "Accept-Language", "Accept-Encoding", "*, Accept"] {
            XCTAssertNil(ArtworkFreshness.expiration(response(["Vary": vary]), responseTime: now, storedAt: now, responseDelay: 0, residentTime: 0))
        }
        XCTAssertNil(ArtworkFreshness.expiration(response(generated: now.addingTimeInterval(-120)), responseTime: now, storedAt: now, responseDelay: 0, residentTime: 0))
    }
    func testAgeIncludesHeaderDelayDownloadAndDecodeAndTakesOlderDate() throws {
        let expires = try XCTUnwrap(ArtworkFreshness.expiration(response(["Age": "10"]), responseTime: now, storedAt: now.addingTimeInterval(3), responseDelay: 4, residentTime: 3))
        XCTAssertEqual(expires.timeIntervalSince(now), 46, accuracy: 0.001)
        let older = try XCTUnwrap(ArtworkFreshness.expiration(response(["Age": "10"], generated: now.addingTimeInterval(-30)), responseTime: now, storedAt: now.addingTimeInterval(3), responseDelay: 4, residentTime: 3))
        XCTAssertEqual(older.timeIntervalSince(now), 30, accuracy: 0.001)
        XCTAssertNil(ArtworkFreshness.expiration(response(), responseTime: now, storedAt: now.addingTimeInterval(61), responseDelay: 0, residentTime: 61))
    }
    func testAmbiguousHeadersAndClockRollbackFailClosed() {
        for headers in [["Cache-Control": "public, max-age=60, max-age=600"], ["Cache-Control": "public, max-age=60, private = x"], ["Age": "-1"], ["Age": "1.5"], ["Date": "bad date"]] {
            XCTAssertNil(ArtworkFreshness.expiration(response(headers), responseTime: now, storedAt: now, responseDelay: 0, residentTime: 0))
        }
        XCTAssertNil(ArtworkFreshness.expiration(response(), responseTime: now, storedAt: now.addingTimeInterval(-1), responseDelay: 0, residentTime: 0))
    }
    func testOldCacheFormatIsDiscardedBeforeNetworkReuse() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ArtworkCache(directory: directory)
        let url = URL(string: "https://artwork.test/image")!
        try cache.store(Data([1,2,3]), url: url, expires: now.addingTimeInterval(60), now: now)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let legacy = ArtworkCache.Entry(version: 1, expires: now.addingTimeInterval(60), data: Data([1,2,3]))
        try PropertyListEncoder().encode(legacy).write(to: file)
        XCTAssertNil(try cache.read(url, now: now))
    }
}
