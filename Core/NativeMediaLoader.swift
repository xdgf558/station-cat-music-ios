import Foundation
import AVFoundation
import UniformTypeIdentifiers

nonisolated struct MediaHTTPResult: Sendable {
    let status: Int; let data: Data; let headers: [String: String]
    func header(_ name: String) -> String? { headers[name.lowercased()] }
}
nonisolated protocol MediaHTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> MediaHTTPResult }
actor NativeMediaTransport: MediaHTTPTransport {
    private let session: URLSession
    init() {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.urlCache = nil; c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 5; c.timeoutIntervalForResource = 5
        session = URLSession(configuration: c, delegate: RejectRedirects(), delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let r = response as? HTTPURLResponse, r.url == request.url else { throw APIError.invalidPayload }
        var data = Data()
        // At most one 64 KiB audio range or a bounded error body. Never persist media.
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 65_536 else { throw APIError.invalidPayload }; data.append(byte)
        }
        let headers = Dictionary(uniqueKeysWithValues: r.allHeaderFields.map { (String(describing: $0.key).lowercased(), String(describing: $0.value)) })
        return MediaHTTPResult(status: r.statusCode, data: data, headers: headers)
    }
}
// Independent per-item channel. URLs are validated before constructing this value.
// Each HTTP request carries its own current Bearer; the grant never substitutes for it.
actor AuthorizedMediaChannel {
    let authorization: AuthorizedPlayback
    private let authorizer: any PlaybackAuthorizing
    private let transport: any MediaHTTPTransport
    private let deadline: ContinuousClock.Instant
    private var identity: String?
    init(authorization: AuthorizedPlayback, authorizer: any PlaybackAuthorizing, transport: any MediaHTTPTransport,
         lifetime: Double) {
        self.authorization = authorization; self.authorizer = authorizer; self.transport = transport
        deadline = ContinuousClock().now.advanced(by: .seconds(max(0, lifetime)))
    }
    func send(method: String, start: Int64? = nil, length: Int? = nil) async throws -> MediaHTTPResult {
        guard method == "HEAD" || method == "GET", ContinuousClock().now < deadline else { throw APIError.requiresAuthentication }
        if method == "GET" { guard let start, start >= 0, let length, (1...65_536).contains(length), start <= Int64.max - Int64(length) else { throw APIError.invalidRequest } }
        // One five-second budget including the optional single 401 refresh.
        let gate = MediaRequestGate()
        return try await withTaskCancellationHandler(operation: {
            try await gate.run { try await self.perform(method: method, start: start, length: length) }
        }, onCancel: { Task { await gate.cancel() } })
    }

    private func perform(method: String, start: Int64?, length: Int?) async throws -> MediaHTTPResult {
        for attempt in 0...1 {
            try Task.checkCancellation()
            guard ContinuousClock().now < deadline, await authorizer.isCurrent(authorization) else { throw APIError.staleResponse }
            let bearer = try await authorizer.bearer(for: authorization, refresh: attempt == 1)
            var request = URLRequest(url: authorization.grant.playbackUrl); request.httpMethod = method; request.timeoutInterval = 5
            if authorization.grant.authMode == .sessionBearer {
                guard let bearer else { throw APIError.requiresAuthentication }
                request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
            }
            if let start, let length { request.setValue("bytes=\(start)-\(start + Int64(length) - 1)", forHTTPHeaderField: "Range") }
            let result = try await transport.send(request)
            try Task.checkCancellation()
            guard ContinuousClock().now < deadline, await authorizer.isCurrent(authorization) else { throw APIError.staleResponse }
            if result.status == 401, attempt == 0, authorization.grant.authMode == .sessionBearer { continue }
            guard result.status == (method == "HEAD" ? 200 : 206), result.header("content-type") == "audio/mpeg",
                  let etag = result.header("etag"), !etag.isEmpty else { throw APIError.rejected(result.status) }
            if let identity { guard identity == etag else { throw APIError.staleResponse } } else { identity = etag }
            return result
        }
        throw APIError.requiresAuthentication
    }
    func size() async throws -> Int64 {
        let result = try await send(method: "HEAD")
        guard let value = result.header("content-length"), let size = Int64(value), size > 0, size <= 33_554_432, result.data.isEmpty else { throw APIError.invalidPayload }
        return size
    }
    func read(start: Int64, length: Int, total: Int64) async throws -> Data {
        guard total > start, length > 0 else { throw APIError.invalidRequest }
        let n = min(length, Int(total - start)), result = try await send(method: "GET", start: start, length: n)
        guard result.header("content-range") == "bytes \(start)-\(start + Int64(n) - 1)/\(total)",
              result.header("content-length") == String(n), result.data.count == n else { throw APIError.invalidPayload }
        return result.data
    }
}

@MainActor final class NativeMediaLoader: NSObject, @preconcurrency AVAssetResourceLoaderDelegate, MediaLoading {
    private let channel: AuthorizedMediaChannel
    private let onFailure: @MainActor () -> Void
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var cancelled = false
    init(channel: AuthorizedMediaChannel, onFailure: @escaping @MainActor () -> Void) { self.channel = channel; self.onFailure = onFailure }
    func asset() -> AVURLAsset {
        // Only AVFoundation sees this scheme. Network I/O exclusively uses the validated grant URL.
        let asset = AVURLAsset(url: URL(string: "stationcat-media://item/\(UUID().uuidString)/audio.mp3")!)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return asset
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard !cancelled, tasks.count < 4 else { request.finishLoading(with: APIError.unavailable); return true }
        let id = ObjectIdentifier(request)
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.tasks.removeValue(forKey: id) }
            do {
                let size = try await self.channel.size(); try Task.checkCancellation()
                if let info = request.contentInformationRequest {
                    info.contentType = UTType.mp3.identifier; info.contentLength = size; info.isByteRangeAccessSupported = true
                }
                if let data = request.dataRequest {
                    let initial = max(data.requestedOffset, data.currentOffset)
                    guard initial >= 0, initial <= size, data.requestedLength >= 0,
                          data.requestedOffset <= Int64.max - Int64(data.requestedLength) else { throw APIError.invalidRequest }
                    let end = data.requestsAllDataToEndOfResource ? size : min(size, data.requestedOffset + Int64(data.requestedLength))
                    var offset = initial
                    while offset < end {
                        try Task.checkCancellation()
                        let chunk = try await self.channel.read(start: offset, length: Int(min(65_536, end - offset)), total: size)
                        try Task.checkCancellation(); guard !self.cancelled else { throw CancellationError() }
                        data.respond(with: chunk); offset += Int64(chunk.count)
                    }
                }
                try Task.checkCancellation(); request.finishLoading()
            } catch {
                request.finishLoading(with: error)
                if !Task.isCancelled && !self.cancelled { self.onFailure() }
            }
        }
        return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) { tasks.removeValue(forKey: ObjectIdentifier(request))?.cancel() }
    func cancelAll() { cancelled = true; for task in tasks.values { task.cancel() }; tasks.removeAll() }
}

// Return on deadline even if a coalesced credential refresh is still completing its
// durable journal. A cancelled/late worker cannot deliver bytes or resume playback.
private actor MediaRequestGate {
    private var continuation: CheckedContinuation<MediaHTTPResult, Error>?
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var finished = false
    func run(_ operation: @escaping @Sendable () async throws -> MediaHTTPResult) async throws -> MediaHTTPResult {
        guard !finished else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            work = Task {
                do { let result = try await operation(); self.complete(.success(result)) }
                catch { self.complete(.failure(error)) }
            }
            timer = Task {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self.complete(.failure(APIError.unavailable))
            }
        }
    }
    private func complete(_ result: Result<MediaHTTPResult, Error>) {
        guard !finished else { return }; finished = true
        let waiting = continuation; continuation = nil
        work?.cancel(); work = nil; timer?.cancel(); timer = nil
        waiting?.resume(with: result)
    }
    func cancel() { complete(.failure(CancellationError())) }
}
