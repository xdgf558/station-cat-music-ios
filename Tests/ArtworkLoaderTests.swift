import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import StationCatMusic

private final class ArtworkFixtureProtocol: URLProtocol, @unchecked Sendable {
    // Created before timing starts; no external network or bundled copyrighted art.
    static let nearLimit: Data = {
        let side = 700
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        var seed: UInt32 = 17
        for i in pixels.indices where i % 4 != 3 {
            seed = seed &* 1664525 &+ 1013904223; pixels[i] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); precondition(CGImageDestinationFinalize(destination))
        var bytes = output as Data
        precondition(bytes.count < 2_097_136)
        // PNG permits trailing bytes; retain real PNG decoding with a near-capacity body.
        bytes.append(Data(repeating: 0, count: 2_097_136 - bytes.count))
        return bytes
    }()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "artwork.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = Self.nearLimit
        if request.url?.path == "/oversized" { body.append(Data(repeating: 0, count: 17)) }
        let mime = request.url?.path == "/wrong-type" ? "text/plain" : "image/png"
        // Omit Content-Length to exercise the streaming limit, not just the header check.
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for offset in stride(from: 0, to: body.count, by: 65_536) {
            client?.urlProtocol(self, didLoad: body.subdata(in: offset..<min(body.count, offset + 65_536)))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class ArtworkLoaderTests: XCTestCase {
    func testNearCapacityDownloadAndDecodeKeepMainActorResponsive() async throws {
        let size = await Task.detached { ArtworkFixtureProtocol.nearLimit.count }.value
        XCTAssertEqual(size, 2_097_136)
        let loader = ArtworkLoader(protocolClasses: [ArtworkFixtureProtocol.self])
        var beats = 0, maxGap = 0.0
        var last = ContinuousClock.now
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
                let now = ContinuousClock.now
                let gap = last.duration(to: now).components
                maxGap = max(maxGap, Double(gap.seconds) + Double(gap.attoseconds) / 1e18)
                last = now; beats += 1
            }
        }
        defer { heartbeat.cancel() }
        for _ in 0..<3 {
            let image = try await loader.load(URL(string: "https://artwork.test/near-limit")!)
            XCTAssertNotNil(image); XCTAssertEqual(image?.width, 256); XCTAssertEqual(image?.height, 256)
        }
        let final = last.duration(to: .now).components
        maxGap = max(maxGap, Double(final.seconds) + Double(final.attoseconds) / 1e18)
        XCTAssertGreaterThan(beats, 0)
        XCTAssertLessThan(maxGap, 0.10, "Cover processing must not monopolize the main actor")
        print("M4_ARTWORK_HEARTBEAT_PASSED: bytes=\(size); downloads=3; beats=\(beats); maxGap=\(maxGap)")
    }
    func testStreamingSizeLimitAndMimeRemainEnforced() async throws {
        let loader = ArtworkLoader(protocolClasses: [ArtworkFixtureProtocol.self])
        let oversized = try await loader.load(URL(string: "https://artwork.test/oversized")!)
        XCTAssertNil(oversized)
        let wrongType = try await loader.load(URL(string: "https://artwork.test/wrong-type")!)
        XCTAssertNil(wrongType)
    }
}
