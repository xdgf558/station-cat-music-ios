import XCTest
import ImageIO
import UniformTypeIdentifiers
import MediaPlayer
import UIKit
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
    func testNowPlayingArtworkCanBeRequestedFromMediaPlayerBackgroundQueue() async throws {
        let playback = PlaybackService()
        let system = SystemPlayback(playback: playback, artworkHost: "artwork.test",
            artworkLoader: ArtworkLoader(protocolClasses: [ArtworkFixtureProtocol.self]))
        defer { system.shutdown(); playback.shutdown() }
        let track = Track(id: UUID().uuidString, title: "Background artwork regression", artist: "Fixture",
            durationSeconds: 180, audioVersion: 1, access: .free, coverUrl: URL(string: "https://artwork.test/near-limit")!)
        system.publish(PlaybackSnapshot(track: track, position: 0, duration: 180, playing: false,
            canNext: false, canPrevious: false, canSeek: false, canPause: false))
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil,
              ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let artwork = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)
        let reference = BackgroundArtworkReference(artwork: artwork)
        let widths = await Task.detached {
            dispatchPrecondition(condition: .notOnQueue(.main))
            return [32, 128, 512].map { size in
                reference.artwork.image(at: CGSize(width: size, height: size))?.cgImage?.width
            }
        }.value
        XCTAssertEqual(widths, [512, 512, 512])
        system.shutdown()
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }
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
            let image = try await loader.load(URL(string: "https://artwork.test/near-limit")!, allowedHost: "artwork.test")
            XCTAssertNotNil(image); XCTAssertEqual(image?.width, 512); XCTAssertEqual(image?.height, 512)
        }
        let final = last.duration(to: .now).components
        maxGap = max(maxGap, Double(final.seconds) + Double(final.attoseconds) / 1e18)
        XCTAssertGreaterThan(beats, 0)
        XCTAssertLessThan(maxGap, 0.10, "Cover processing must not monopolize the main actor")
        print("M4_ARTWORK_HEARTBEAT_PASSED: bytes=\(size); downloads=3; beats=\(beats); maxGap=\(maxGap)")
    }
    func testStreamingSizeLimitAndMimeRemainEnforced() async throws {
        let loader = ArtworkLoader(protocolClasses: [ArtworkFixtureProtocol.self])
        let oversized = try await loader.load(URL(string: "https://artwork.test/oversized")!, allowedHost: "artwork.test")
        XCTAssertNil(oversized)
        let wrongType = try await loader.load(URL(string: "https://artwork.test/wrong-type")!, allowedHost: "artwork.test")
        XCTAssertNil(wrongType)
    }
}

// Test-only transfer of a fully initialized, read-only MediaPlayer object to its
// documented request surface. No MainActor model or mutable UI crosses threads.
private final class BackgroundArtworkReference: @unchecked Sendable {
    let artwork: MPMediaItemArtwork
    init(artwork: MPMediaItemArtwork) { self.artwork = artwork }
}

private final class CacheFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var held: [String: @Sendable () -> Void] = [:]
    func started(_ path: String) { lock.lock(); defer { lock.unlock() }; counts[path, default: 0] += 1 }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[path, default: 0] }
    func hold(_ path: String, _ work: @escaping @Sendable () -> Void) { lock.lock(); defer { lock.unlock() }; held[path] = work }
    func isHeld(_ path: String) -> Bool { lock.lock(); defer { lock.unlock() }; return held[path] != nil }
    func release(_ path: String) { lock.lock(); let work = held.removeValue(forKey: path); lock.unlock(); work?() }
}
private final class CachedArtworkProtocol: URLProtocol, @unchecked Sendable {
    static let state = CacheFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "artwork.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path; Self.state.started(path)
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = TimeZone(secondsFromGMT: 0); date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        var headers = ["Content-Type": "image/png", "Cache-Control": "public, max-age=3600", "Date": date.string(from: Date())]
        if path.contains("vary-star") { headers["Vary"] = "*" }
        if path.contains("vary-language") { headers["Vary"] = "Accept-Language" }
        if path.contains("old-date") { headers["Date"] = date.string(from: Date().addingTimeInterval(-7200)) }
        if path.contains("no-date") { headers.removeValue(forKey: "Date") }
        if path.contains("no-store") { headers["Cache-Control"] = "public, max-age=3600, no-store" }
        if path.contains("short-ttl") { headers["Cache-Control"] = "public, max-age=3" }
        if path.contains("private") { headers["Cache-Control"] = "private, max-age=3600" }
        if path.contains("cookie") { headers["Set-Cookie"] = "fixture=not-a-credential" }
        if path.contains("old-age") { headers["Age"] = "3600" }
        if path.contains("missing") { headers.removeValue(forKey: "Cache-Control") }
        if path.contains("bad-mime") { headers["Content-Type"] = "application/octet-stream" }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path.contains("held") { Self.state.hold(path) { [self] in finish() } } else { finish() }
    }
    private func finish() {
        let data = request.url!.path.contains("corrupt") ? Data("not an image".utf8) : ArtworkFixtureProtocol.nearLimit
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class ArtworkCacheTests: XCTestCase {
    func directory() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }
    func testConcurrentViewsShareDownloadAndDecodedImageDespiteOneCancellation() async throws {
        let path = "/held-shared-" + UUID().uuidString, state = CachedArtworkProtocol.state
        let url = URL(string: "https://artwork.test" + path)!
        let loader = ArtworkLoader(protocolClasses: [CachedArtworkProtocol.self])
        let first = Task { try await loader.load(url, allowedHost: "artwork.test") }
        for _ in 0..<200 { if state.isHeld(path) { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(state.isHeld(path))
        let others = (0..<4).map { _ in Task { try await loader.load(url, allowedHost: "artwork.test") } }
        defer { state.release(path); first.cancel(); others.forEach { $0.cancel() } }
        await Task.yield(); first.cancel(); state.release(path)
        do { _ = try await first.value; XCTFail("Cancelled view received an image") } catch {}
        let firstShared = try await others[0].value
        let image = try XCTUnwrap(firstShared)
        for other in others.dropFirst() { let value = try await other.value; XCTAssertTrue(value === image) }
        let warm = try await loader.load(url, allowedHost: "artwork.test")
        XCTAssertTrue(warm === image); XCTAssertEqual(state.count(path), 1)
        let refused = try await loader.load(url, allowedHost: "wrong.test")
        XCTAssertNil(refused)
        try await loader.clearCache()
        // Use an ordinary URL for clear/reload, avoiding another intentionally held response.
        let reload = URL(string: "https://artwork.test/clear-" + UUID().uuidString)!
        _ = try await loader.load(reload, allowedHost: "artwork.test")
        try await loader.clearCache()
        _ = try await loader.load(reload, allowedHost: "artwork.test")
        XCTAssertEqual(state.count(reload.path), 2)
    }
    func testDecodedMemoryBudgetAndFreshnessAreBounded() async throws {
        let loader = ArtworkLoader(protocolClasses: [CachedArtworkProtocol.self], memoryMaximumBytes: 1_048_576)
        let a = URL(string: "https://artwork.test/memory-a-" + UUID().uuidString)!
        let b = URL(string: "https://artwork.test/memory-b-" + UUID().uuidString)!
        _ = try await loader.load(a, allowedHost: "artwork.test")
        _ = try await loader.load(b, allowedHost: "artwork.test")
        _ = try await loader.load(a, allowedHost: "artwork.test")
        XCTAssertEqual(CachedArtworkProtocol.state.count(a.path), 2)
        let short = URL(string: "https://artwork.test/short-ttl-" + UUID().uuidString)!
        let first = try await loader.load(short, allowedHost: "artwork.test")
        let cached = try await loader.load(short, allowedHost: "artwork.test")
        XCTAssertNotNil(first); XCTAssertTrue(first === cached)
        try await Task.sleep(for: .seconds(3.1))
        _ = try await loader.load(short, allowedHost: "artwork.test")
        XCTAssertEqual(CachedArtworkProtocol.state.count(short.path), 2)
    }
    func testPublicCoverReusedAfterLoaderRelaunchAndVersionIsPartOfKey() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let path = "/cache-" + UUID().uuidString
        let first = URL(string: "https://artwork.test" + path + "?v=1")!
        let second = URL(string: "https://artwork.test" + path + "?v=2")!
        let loader = ArtworkLoader(protocolClasses: [CachedArtworkProtocol.self], cacheDirectory: dir)
        let image = try await loader.load(first, allowedHost: "artwork.test"); XCTAssertNotNil(image)
        let reopened = ArtworkLoader(protocolClasses: [CachedArtworkProtocol.self], cacheDirectory: dir)
        let cached = try await reopened.load(first, allowedHost: "artwork.test"); XCTAssertNotNil(cached)
        XCTAssertEqual(CachedArtworkProtocol.state.count(path), 1)
        let changed = try await reopened.load(second, allowedHost: "artwork.test"); XCTAssertNotNil(changed)
        XCTAssertEqual(CachedArtworkProtocol.state.count(path), 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2)
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]); XCTAssertEqual(values.isExcludedFromBackup, true)
    }
    func testPrivateUncacheableAndInvalidResponsesNeverPersist() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let loader = ArtworkLoader(protocolClasses: [CachedArtworkProtocol.self], cacheDirectory: dir)
        for kind in ["no-store", "private", "cookie", "old-age", "missing", "bad-mime", "corrupt", "vary-star", "vary-language", "old-date", "no-date"] {
            let url = URL(string: "https://artwork.test/" + kind + UUID().uuidString)!
            _ = try await loader.load(url, allowedHost: "artwork.test")
            _ = try await loader.load(url, allowedHost: "artwork.test")
            XCTAssertEqual(CachedArtworkProtocol.state.count(url.path), 2, "Uncacheable response leaked into decoded memory cache")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 0)
        let refused = try await loader.load(URL(string: "https://artwork.test/refused")!, allowedHost: "different.test")
        XCTAssertNil(refused); XCTAssertEqual(CachedArtworkProtocol.state.count("/refused"), 0)
    }
    func testClearDuringDownloadCannotRepopulateCache() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let path = "/held-" + UUID().uuidString, state = CachedArtworkProtocol.state
        let loader = ArtworkLoader(protocolClasses: [CachedArtworkProtocol.self], cacheDirectory: dir)
        let task = Task { try await loader.load(URL(string: "https://artwork.test" + path)!, allowedHost: "artwork.test") }
        defer { state.release(path); task.cancel() }
        for _ in 0..<200 { if state.isHeld(path) { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(state.isHeld(path))
        try await loader.clearCache(); state.release(path)
        let image = try await task.value; XCTAssertNil(image)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 0)
    }
    func testDiskLRUBudgetTTLAndCorruptionRecovery() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ArtworkCache(directory: dir, maximumBytes: 1400, maximumFiles: 2)
        let now = Date(), data = Data(repeating: 5, count: 400)
        let a = URL(string: "https://artwork.test/a")!, b = URL(string: "https://artwork.test/b")!, c = URL(string: "https://artwork.test/c")!
        try cache.store(data, url: a, expires: now.addingTimeInterval(100), now: now)
        try cache.store(data, url: b, expires: now.addingTimeInterval(100), now: now.addingTimeInterval(1))
        XCTAssertEqual(try cache.read(a, now: now.addingTimeInterval(2)), data)
        try cache.store(data, url: c, expires: now.addingTimeInterval(100), now: now.addingTimeInterval(3))
        XCTAssertNil(try cache.read(b, now: now.addingTimeInterval(4)))
        XCTAssertEqual(try cache.read(a, now: now.addingTimeInterval(4)), data)
        XCTAssertNil(try cache.read(a, now: now.addingTimeInterval(101)))
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) { try Data("broken".utf8).write(to: file) }
        XCTAssertNil(try cache.read(c, now: now.addingTimeInterval(4)))
        try cache.clear(); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
    func testByteBudgetAppliesEvenBelowFileCountLimitAndRejectsOversizedEntry() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ArtworkCache(directory: dir, maximumBytes: 700, maximumFiles: 10)
        let now = Date(), data = Data(repeating: 1, count: 400)
        let a = URL(string: "https://artwork.test/bytes-a")!, b = URL(string: "https://artwork.test/bytes-b")!
        try cache.store(data, url: a, expires: now.addingTimeInterval(60), now: now)
        try cache.store(data, url: b, expires: now.addingTimeInterval(60), now: now.addingTimeInterval(1))
        XCTAssertNil(try cache.read(a, now: now.addingTimeInterval(2)))
        XCTAssertEqual(try cache.read(b, now: now.addingTimeInterval(2)), data)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
        let total = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(total, 700)
        try cache.store(Data(repeating: 2, count: 701), url: a, expires: now.addingTimeInterval(60), now: now)
        XCTAssertEqual(try cache.read(b, now: now.addingTimeInterval(2)), data)
    }
    func testClearNeverDeletesNeighborOrFollowsSymlink() throws {
        let dir = directory(), outside = directory(); defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let original = Data("private journal".utf8); try original.write(to: outside)
        try FileManager.default.createSymbolicLink(at: dir.appending(path: "fake.art"), withDestinationURL: outside)
        try original.write(to: dir.appending(path: "state.json"))
        try ArtworkCache(directory: dir).clear()
        XCTAssertEqual(try Data(contentsOf: outside), original)
        XCTAssertEqual(try Data(contentsOf: dir.appending(path: "state.json")), original)
    }
}
