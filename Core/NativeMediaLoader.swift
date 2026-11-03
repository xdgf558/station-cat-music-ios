import Foundation
import AVFoundation
import UniformTypeIdentifiers

#if DEBUG
// Bounded process-local observations; never records URLs, identifiers or payloads.
nonisolated enum NativeMediaProbeTrace {
    enum Phase: String, Encodable, Sendable {
        case transportStart = "transport_start", transportHeaders = "transport_headers"
        case transportBodyComplete = "transport_body_complete", transportBodyEnd = "transport_body_end"
        case transportEnd = "transport_end"
        case loaderRequest = "loader_request", loaderTaskStart = "loader_task_start"
        case loaderSizeStart = "loader_size_start", loaderSizeReady = "loader_size_ready"
        case loaderMetadataReady = "loader_metadata_ready", loaderRespond = "loader_respond"
        case loaderFinish = "loader_finish", loaderError = "loader_error"
        case loaderDidCancel = "loader_did_cancel", loaderCancelAll = "loader_cancel_all"
    }
    enum ErrorCategory: String, Encodable, Sendable {
        case cancelled, api, url, avFoundation, coreMedia, posix, osStatus, cocoa, other
    }
    struct Event: Encodable, Sendable {
        let sequence: Int
        let at: Double
        let phase: Phase
        let status: Int?
        let expectedLength: Int64?
        let bytes: Int?
        let offset: Int64?
        let length: Int?
        let allToEnd: Bool?
        let hasInfo: Bool?
        let hasData: Bool?
        let tasks: Int?
        let cancelled: Bool?
        let errorCategory: ErrorCategory?
        let errorCode: Int?
    }
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var entries = [Event]()
        func reset() { lock.lock(); defer { lock.unlock() }; entries.removeAll(keepingCapacity: true) }
        func events() -> [Event] { lock.lock(); defer { lock.unlock() }; return entries }
        func append(_ make: (Int) -> Event) {
            lock.lock(); defer { lock.unlock() }
            guard entries.count < 96 else { return }
            entries.append(make(entries.count + 1))
        }
    }
    private static let storage = Storage()
    static func reset() { storage.reset() }
    static func events() -> [Event] { storage.events() }
    static func record(_ phase: Phase, status: Int? = nil, expectedLength: Int64? = nil,
                       bytes: Int? = nil, offset: Int64? = nil, length: Int? = nil,
                       allToEnd: Bool? = nil, hasInfo: Bool? = nil, hasData: Bool? = nil,
                       tasks: Int? = nil, cancelled: Bool? = nil, error: (any Error)? = nil) {
        let category: ErrorCategory?
        var code: Int?
        if let error {
            let native = error as NSError
            code = native.code
            if error is CancellationError { category = .cancelled }
            else if let api = error as? APIError {
                category = .api
                if case .rejected(let status) = api { code = status }
            } else {
                switch native.domain {
                case NSURLErrorDomain: category = .url
                case "AVFoundationErrorDomain": category = .avFoundation
                case "CoreMediaErrorDomain": category = .coreMedia
                case NSPOSIXErrorDomain: category = .posix
                case NSOSStatusErrorDomain: category = .osStatus
                case NSCocoaErrorDomain: category = .cocoa
                default: category = .other
                }
            }
        } else { category = nil; code = nil }
        storage.append { sequence in
            Event(sequence: sequence, at: Date().timeIntervalSince1970, phase: phase,
                  status: status, expectedLength: expectedLength, bytes: bytes, offset: offset,
                  length: length, allToEnd: allToEnd, hasInfo: hasInfo, hasData: hasData,
                  tasks: tasks, cancelled: cancelled, errorCategory: category, errorCode: code)
        }
    }
}
#endif

nonisolated struct MediaHTTPResult: Sendable {
    let status: Int; let data: Data; let headers: [String: String]
    func header(_ name: String) -> String? { headers[name.lowercased()] }
}
nonisolated protocol MediaHTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> MediaHTTPResult }
nonisolated enum NativeMediaLimits { static let rangeBytes = 524_288 }
actor NativeMediaTransport: MediaHTTPTransport {
    private let session: URLSession
    init(protocolClasses: [AnyClass]? = nil) {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.urlCache = nil; c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 5; c.timeoutIntervalForResource = 5
        if let protocolClasses { c.protocolClasses = protocolClasses }
        session = URLSession(configuration: c, delegate: RejectRedirects(), delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> MediaHTTPResult {
#if DEBUG
        NativeMediaProbeTrace.record(.transportStart)
        defer { NativeMediaProbeTrace.record(.transportEnd, cancelled: Task.isCancelled) }
#endif
        let (bytes, response) = try await session.bytes(for: request)
#if DEBUG
        NativeMediaProbeTrace.record(.transportHeaders, status: (response as? HTTPURLResponse)?.statusCode,
                                    expectedLength: response.expectedContentLength)
#endif
        defer { bytes.task.cancel() }
        guard let r = response as? HTTPURLResponse, r.url == request.url else { throw APIError.invalidPayload }
        var data = Data()
#if DEBUG
        // Snapshot the partial count on every exit without adding per-byte work.
        defer { NativeMediaProbeTrace.record(.transportBodyEnd, bytes: data.count, cancelled: Task.isCancelled) }
#endif
        // One bounded 512 KiB range, including error bodies. Never persist media.
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < NativeMediaLimits.rangeBytes else { throw APIError.invalidPayload }; data.append(byte)
        }
#if DEBUG
        NativeMediaProbeTrace.record(.transportBodyComplete, bytes: data.count, cancelled: Task.isCancelled)
#endif
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
    private var validatedHead: MediaHTTPResult?
    private var prefix: Data?
    init(authorization: AuthorizedPlayback, authorizer: any PlaybackAuthorizing, transport: any MediaHTTPTransport,
         lifetime: Double) {
        self.authorization = authorization; self.authorizer = authorizer; self.transport = transport
        deadline = ContinuousClock().now.advanced(by: .seconds(max(0, lifetime)))
    }
    func send(method: String, start: Int64? = nil, length: Int? = nil) async throws -> MediaHTTPResult {
        guard method == "HEAD" || method == "GET", ContinuousClock().now < deadline else { throw APIError.requiresAuthentication }
        if method == "GET" { guard let start, start >= 0, let length, (1...NativeMediaLimits.rangeBytes).contains(length), start <= Int64.max - Int64(length) else { throw APIError.invalidRequest } }
        // One five-second budget including the optional single 401 refresh.
        let gate = MediaRequestGate()
        return try await withTaskCancellationHandler(operation: {
            try await gate.run { try await self.perform(method: method, start: start, length: length) }
        }, onCancel: { Task { await gate.cancel() } })
    }

    private func perform(method: String, start: Int64?, length: Int?) async throws -> MediaHTTPResult {
        for attempt in 0...1 {
            try Task.checkCancellation()
            guard await authorizer.isCurrent(authorization), ContinuousClock().now < deadline else { throw APIError.staleResponse }
            try Task.checkCancellation()
            let bearer = try await authorizer.bearer(for: authorization, refresh: attempt == 1)
            // Credential refresh can outlive the caller or the old grant deadline.
            // Do not start a late network request after either boundary changed.
            try Task.checkCancellation()
            guard await authorizer.isCurrent(authorization), ContinuousClock().now < deadline else { throw APIError.staleResponse }
            try Task.checkCancellation()
            var request = URLRequest(url: authorization.grant.playbackUrl); request.httpMethod = method; request.timeoutInterval = 5
            if authorization.grant.authMode == .sessionBearer {
                guard let bearer else { throw APIError.requiresAuthentication }
                request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
            }
            if let start, let length { request.setValue("bytes=\(start)-\(start + Int64(length) - 1)", forHTTPHeaderField: "Range") }
            // Metadata is immutable within one grant/object identity. Reuse only
            // after the same cancellation, account and deadline checks above.
            // Keep only the first bounded range in RAM for AVFoundation's tiny
            // probing reads. Never share it between grants or persist audio.
            let result: MediaHTTPResult
            if method == "HEAD", let validatedHead { result = validatedHead }
            else if method == "GET", let prefix, let start, let length,
                    start + Int64(length) <= Int64(prefix.count), let head = validatedHead {
                var headers = head.headers
                headers["content-range"] = "bytes \(start)-\(start + Int64(length) - 1)/\(head.header("content-length")!)"
                headers["content-length"] = String(length)
                result = MediaHTTPResult(status: 206, data: prefix.subdata(in: Int(start)..<(Int(start) + length)), headers: headers)
            }
            else { result = try await transport.send(request) }
            try Task.checkCancellation()
            guard await authorizer.isCurrent(authorization), ContinuousClock().now < deadline else { throw APIError.staleResponse }
            try Task.checkCancellation()
            if result.status == 401, attempt == 0, authorization.grant.authMode == .sessionBearer { continue }
            guard result.status == (method == "HEAD" ? 200 : 206), result.header("content-type") == "audio/mpeg",
                  let etag = result.header("etag"), !etag.isEmpty else { throw APIError.rejected(result.status) }
            if let identity { guard identity == etag else { throw APIError.staleResponse } } else { identity = etag }
            return result
        }
        throw APIError.requiresAuthentication
    }
    func size() async throws -> Int64 {
        if validatedHead == nil {
            let result = try await send(method: "GET", start: 0, length: NativeMediaLimits.rangeBytes)
            guard let range = result.header("content-range"), let value = range.split(separator: "/").last,
                  let size = Int64(value), size > 0, size <= 33_554_432 else { throw APIError.invalidPayload }
            let count = min(Int(size), NativeMediaLimits.rangeBytes)
            guard range == "bytes 0-\(count - 1)/\(size)", result.data.count == count,
                  result.header("content-length") == String(count) else { throw APIError.invalidPayload }
            var headers = result.headers; headers["content-length"] = String(size); headers.removeValue(forKey: "content-range")
            prefix = result.data
            validatedHead = MediaHTTPResult(status: 200, data: Data(), headers: headers)
        }
        let result = try await send(method: "HEAD")
        guard let value = result.header("content-length"), let size = Int64(value), size > 0, size <= 33_554_432, result.data.isEmpty else { throw APIError.invalidPayload }
        validatedHead = result
        return size
    }
    func metadata() async throws -> (size: Int64, etag: String) {
        // Renewal validates the new grant/object without fetching the MP3 header
        // again. The old AVPlayerItem can retain its already decoded buffers.
        let result = try await send(method: "HEAD")
        guard let value = result.header("content-length"), let size = Int64(value), size > 0,
              size <= 33_554_432, result.data.isEmpty, let etag = result.header("etag") else { throw APIError.invalidPayload }
        validatedHead = result
        return (size, etag)
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
    private var channel: AuthorizedMediaChannel
    private var generation = 0
    private let onFailure: @MainActor () -> Void
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var cancelled = false
    init(channel: AuthorizedMediaChannel, onFailure: @escaping @MainActor () -> Void) { self.channel = channel; self.onFailure = onFailure }
    func renew(with replacement: AuthorizedMediaChannel) async throws {
        let previous = channel, ticket = generation
        let a = previous.authorization, b = replacement.authorization
        guard !cancelled, a.scope == b.scope, a.context?.epoch == b.context?.epoch,
              a.context?.sessionID == b.context?.sessionID,
              a.grant.trackID == b.grant.trackID, a.grant.audioVersion == b.grant.audioVersion,
              a.grant.variant == b.grant.variant, a.grant.authMode == b.grant.authMode,
              a.grant.durationSeconds == b.grant.durationSeconds,
              a.grant.previewSourceStartSeconds == b.grant.previewSourceStartSeconds else { throw APIError.staleResponse }
        let old = try await previous.metadata(), fresh = try await replacement.metadata()
        try Task.checkCancellation()
        guard !cancelled, generation == ticket, old.size == fresh.size, old.etag == fresh.etag else { throw APIError.staleResponse }
        channel = replacement; generation += 1
    }
    func read(start: Int64, length: Int, total: Int64) async throws -> Data {
        // An in-flight old-grant response is never delivered after rotation.
        // Retry only that read at the same offset against the confirmed new grant.
        for attempt in 0...1 {
            try Task.checkCancellation(); guard !cancelled else { throw CancellationError() }
            let ticket = generation
            do {
                let data = try await channel.read(start: start, length: length, total: total)
                try Task.checkCancellation(); guard !cancelled else { throw CancellationError() }
                if ticket != generation { if attempt == 0 { continue }; throw APIError.staleResponse }
                return data
            } catch {
                try Task.checkCancellation(); guard !cancelled else { throw CancellationError() }
                if ticket != generation && attempt == 0 { continue }
                throw error
            }
        }
        throw APIError.staleResponse
    }
    func asset() -> AVURLAsset {
        // Only AVFoundation sees this scheme. Network I/O exclusively uses the validated grant URL.
        let asset = AVURLAsset(url: URL(string: "stationcat-media://item/\(UUID().uuidString)/audio.mp3")!)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return asset
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
#if DEBUG
        NativeMediaProbeTrace.record(.loaderRequest, offset: request.dataRequest?.requestedOffset,
            length: request.dataRequest?.requestedLength, allToEnd: request.dataRequest?.requestsAllDataToEndOfResource,
            hasInfo: request.contentInformationRequest != nil, hasData: request.dataRequest != nil,
            tasks: tasks.count, cancelled: cancelled)
#endif
        guard !cancelled, tasks.count < 4 else {
#if DEBUG
            NativeMediaProbeTrace.record(.loaderFinish, tasks: tasks.count, cancelled: cancelled, error: APIError.unavailable)
#endif
            request.finishLoading(with: APIError.unavailable); return true
        }
        let id = ObjectIdentifier(request)
        tasks[id] = Task { [weak self] in
#if DEBUG
            NativeMediaProbeTrace.record(.loaderTaskStart, cancelled: Task.isCancelled)
#endif
            guard let self else { return }
            defer { self.tasks.removeValue(forKey: id) }
            do {
#if DEBUG
                NativeMediaProbeTrace.record(.loaderSizeStart, tasks: self.tasks.count, cancelled: Task.isCancelled)
#endif
                let size = try await self.channel.size(); try Task.checkCancellation()
#if DEBUG
                NativeMediaProbeTrace.record(.loaderSizeReady, expectedLength: size, tasks: self.tasks.count, cancelled: Task.isCancelled)
#endif
                if let info = request.contentInformationRequest {
                    info.contentType = UTType.mp3.identifier; info.contentLength = size; info.isByteRangeAccessSupported = true
#if DEBUG
                    NativeMediaProbeTrace.record(.loaderMetadataReady, expectedLength: size, hasInfo: true, tasks: self.tasks.count)
#endif
                }
                if let data = request.dataRequest {
                    let initial = max(data.requestedOffset, data.currentOffset)
                    guard initial >= 0, initial <= size, data.requestedLength >= 0,
                          data.requestedOffset <= Int64.max - Int64(data.requestedLength) else { throw APIError.invalidRequest }
                    let end = data.requestsAllDataToEndOfResource ? size : min(size, data.requestedOffset + Int64(data.requestedLength))
                    var offset = initial
                    while offset < end {
                        try Task.checkCancellation()
                        let chunk = try await self.read(start: offset, length: Int(min(Int64(NativeMediaLimits.rangeBytes), end - offset)), total: size)
                        try Task.checkCancellation(); guard !self.cancelled else { throw CancellationError() }
                        data.respond(with: chunk)
#if DEBUG
                        NativeMediaProbeTrace.record(.loaderRespond, bytes: chunk.count, offset: offset, tasks: self.tasks.count, cancelled: Task.isCancelled)
#endif
                        offset += Int64(chunk.count)
                    }
                }
                try Task.checkCancellation(); request.finishLoading()
#if DEBUG
                NativeMediaProbeTrace.record(.loaderFinish, tasks: self.tasks.count, cancelled: Task.isCancelled)
#endif
            } catch {
#if DEBUG
                NativeMediaProbeTrace.record(.loaderError, tasks: self.tasks.count, cancelled: Task.isCancelled, error: error)
#endif
                request.finishLoading(with: error)
#if DEBUG
                NativeMediaProbeTrace.record(.loaderFinish, tasks: self.tasks.count, cancelled: Task.isCancelled, error: error)
#endif
                if !Task.isCancelled && !self.cancelled { self.onFailure() }
            }
        }
        return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
#if DEBUG
        NativeMediaProbeTrace.record(.loaderDidCancel, offset: request.dataRequest?.requestedOffset,
            length: request.dataRequest?.requestedLength, tasks: tasks.count, cancelled: true)
#endif
        tasks.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }
    func cancelAll() {
#if DEBUG
        NativeMediaProbeTrace.record(.loaderCancelAll, tasks: tasks.count, cancelled: true)
#endif
        cancelled = true; for task in tasks.values { task.cancel() }; tasks.removeAll()
    }
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
