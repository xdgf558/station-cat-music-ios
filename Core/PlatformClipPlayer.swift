import Foundation
import AVFoundation
import Observation
import UniformTypeIdentifiers

/// Public video only, bounded Range requests and no credentials, redirects,
/// URLCache or disk persistence. The website rechecks publication on each read.
actor PlatformClipChannel {
    private let url: URL
    private let transport: any MediaHTTPTransport
    private var head: (size: Int64, etag: String, mime: String)?
    init(url: URL, transport: any MediaHTTPTransport = NativeMediaTransport()) throws {
        guard PlatformContentURL.valid(url) else { throw APIError.invalidRequest }
        self.url = url; self.transport = transport
    }
    private func request(_ method: String, range: String? = nil) -> URLRequest {
        var value = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        value.httpMethod = method; value.httpShouldHandleCookies = false
        value.setValue("video/mp4, video/webm", forHTTPHeaderField: "Accept")
        if let range { value.setValue(range, forHTTPHeaderField: "Range") }
        return value
    }
    func metadata() async throws -> (size: Int64, mime: String) {
        try Task.checkCancellation()
        if let head { return (head.size, head.mime) }
        let result = try await transport.send(request("HEAD"))
        try Task.checkCancellation()
        guard result.status == 200 else { throw APIError.rejected(result.status) }
        guard result.data.isEmpty, let size = result.header("content-length").flatMap(Int64.init),
              size > 0, size <= 268_435_456, let etag = result.header("etag"),
              !etag.isEmpty, etag.utf8.count <= 256,
              let mime = result.header("content-type"), ["video/mp4", "video/webm"].contains(mime) else { throw APIError.invalidPayload }
        if let head { guard head.size == size, head.etag == etag, head.mime == mime else { throw APIError.staleResponse } }
        self.head = (size, etag, mime)
        return (size, mime)
    }
    func read(start: Int64, length: Int) async throws -> Data {
        let info = try await metadata()
        guard start >= 0, start < info.size, (1...NativeMediaLimits.rangeBytes).contains(length), let head else { throw APIError.invalidRequest }
        let count = min(length, Int(info.size - start))
        let result = try await transport.send(request("GET", range: "bytes=\(start)-\(start + Int64(count) - 1)"))
        try Task.checkCancellation()
        guard result.status == 206 else { throw APIError.rejected(result.status) }
        guard result.header("content-type") == head.mime, result.header("etag") == head.etag,
              result.header("content-range") == "bytes \(start)-\(start + Int64(count) - 1)/\(head.size)",
              result.header("content-length") == String(count), result.data.count == count else { throw APIError.invalidPayload }
        return result.data
    }
}

@MainActor final class PlatformClipLoader: NSObject, @preconcurrency AVAssetResourceLoaderDelegate {
    private let channel: PlatformClipChannel
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var stopped = false
    private let failure: @MainActor () -> Void
    init(channel: PlatformClipChannel, failure: @escaping @MainActor () -> Void) { self.channel = channel; self.failure = failure }
    func asset() -> AVURLAsset {
        let asset = AVURLAsset(url: URL(string: "stationcat-clip://item/\(UUID().uuidString)/video")!)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return asset
    }
    func cancel() { stopped = true; for task in tasks.values { task.cancel() }; tasks = [:] }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard !stopped, tasks.count < 4 else { request.finishLoading(with: APIError.unavailable); return true }
        let id = ObjectIdentifier(request)
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.tasks.removeValue(forKey: id) }
            do {
                let info = try await self.channel.metadata()
                try Task.checkCancellation(); guard !self.stopped else { throw CancellationError() }
                if let content = request.contentInformationRequest {
                    content.contentType = UTType(mimeType: info.mime)?.identifier
                    content.contentLength = info.size; content.isByteRangeAccessSupported = true
                }
                if let data = request.dataRequest {
                    var offset = max(data.currentOffset, data.requestedOffset)
                    guard offset >= 0, offset <= info.size, data.requestedLength >= 0,
                          data.requestedOffset <= Int64.max - Int64(data.requestedLength) else { throw APIError.invalidRequest }
                    let end = data.requestsAllDataToEndOfResource ? info.size : min(info.size, data.requestedOffset + Int64(data.requestedLength))
                    while offset < end {
                        let chunk = try await self.channel.read(start: offset, length: Int(min(Int64(NativeMediaLimits.rangeBytes), end - offset)))
                        try Task.checkCancellation(); guard !self.stopped else { throw CancellationError() }
                        data.respond(with: chunk); offset += Int64(chunk.count)
                    }
                }
                try Task.checkCancellation(); request.finishLoading()
            } catch {
                request.finishLoading(with: error)
                if !Task.isCancelled, !self.stopped { self.failure() }
            }
        }
        return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) { tasks.removeValue(forKey: ObjectIdentifier(request))?.cancel() }
}

/// A separate, foreground-only video session. It cannot select a music track,
/// request a native playback grant, or publish remote transport/Now Playing state.
@MainActor @Observable final class PlatformClipPlayer {
    private(set) var player: AVPlayer?
    private(set) var selectedID: String?
    private(set) var loading = false
    private(set) var failed = false
    private(set) var muted = true
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var loader: PlatformClipLoader?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    private var generation = 0
    @ObservationIgnored private let transport: any MediaHTTPTransport
    init(transport: any MediaHTTPTransport = NativeMediaTransport()) { self.transport = transport }

    func play(_ clip: PlatformClip, track: Track, locale: String, provider: any PlatformMusicProviding) {
        stop(); selectedID = clip.id; loading = true
        let ticket = generation
        task = Task { [weak self] in
            do {
                // Revalidate before every explicit start, never use a saved
                // platform URL or old clip list as playback authorization.
                let current = try await provider.clips(track, locale: locale)
                guard current.contains(clip), clip.trackID == track.id else { throw APIError.staleResponse }
                try Task.checkCancellation()
                guard let self, self.generation == ticket else { return }
                let channel = try PlatformClipChannel(url: clip.mediaURL, transport: self.transport)
                let loader = PlatformClipLoader(channel: channel) { [weak self] in self?.fail(ticket) }
                let item = AVPlayerItem(asset: loader.asset())
                self.loader = loader
                self.observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    let failed = item.status == .failed, ready = item.status == .readyToPlay
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == ticket else { return }
                        if failed { self.fail(ticket) }
                        else if ready { self.loading = false }
                    }
                }
                let player = AVPlayer(playerItem: item)
                player.isMuted = true
                self.player = player
                player.play() // Only reached from the user's explicit clip button.
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(ticket)
            }
        }
    }
    func toggleMute() { muted.toggle(); player?.isMuted = muted }
    func stop() {
        generation += 1; task?.cancel(); task = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        observation = nil; loader?.cancel(); loader = nil
        selectedID = nil; loading = false; failed = false; muted = true
    }
    private func fail(_ ticket: Int) {
        guard generation == ticket else { return }
        let id = selectedID; stop(); selectedID = id; failed = true
    }
}
