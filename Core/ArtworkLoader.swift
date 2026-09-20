import Foundation
import ImageIO

/// Bounded download, cache I/O and ImageIO work stay off MainActor.
actor ArtworkLoader {
    static let maximumBytes = 2_097_152
    private let protocolClasses: [AnyClass]?
    private let cache: ArtworkCache?
    private var generation = 0
    init(protocolClasses: [AnyClass]? = nil, cacheDirectory: URL? = nil, cacheMaximumBytes: Int = 150 * 1024 * 1024) {
        self.protocolClasses = protocolClasses
        self.cache = cacheDirectory.map { ArtworkCache(directory: $0, maximumBytes: cacheMaximumBytes) }
    }
    func clearCache() throws {
        generation += 1 // An already-started download cannot repopulate the cleared cache.
        try cache?.clear()
    }
    private func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
    private func expiration(_ response: HTTPURLResponse, now: Date) -> Date? {
        // Honor explicit server freshness only. Never persist private/no-store or cookie responses.
        guard response.value(forHTTPHeaderField: "Set-Cookie") == nil else { return nil }
        let fields = (response.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.contains("public"), !fields.contains(where: { ["no-store", "no-cache", "private"].contains(String($0.split(separator: "=").first ?? "")) }),
              let field = fields.first(where: { $0.hasPrefix("max-age=") }),
              let seconds = Double(field.dropFirst(8)), seconds.isFinite, seconds > 0 else { return nil }
        let age = Double(response.value(forHTTPHeaderField: "Age") ?? "0") ?? seconds
        guard age.isFinite, age >= 0 else { return nil }
        let remaining = min(86400, seconds - age)
        return remaining > 0 ? now.addingTimeInterval(remaining) : nil
    }
    func load(_ url: URL, allowedHost: String) async throws -> CGImage? {
        try Task.checkCancellation()
        guard url.scheme == "https", url.host == allowedHost, url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443 else { return nil }
        let ticket = generation
        if let data = try? cache?.read(url, now: Date()), let image = decode(data) { return image }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 5
        if let protocolClasses { config.protocolClasses = protocolClasses }
        let network = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { network.invalidateAndCancel() }
        var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await network.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true,
              response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") == true,
              response.expectedContentLength <= Int64(Self.maximumBytes) else { return nil }
        var data = Data()
        data.reserveCapacity(min(Self.maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumBytes else { return nil }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard ticket == generation, let image = decode(data) else { return nil }
        if let expires = expiration(response, now: Date()) { try? cache?.store(data, url: url, expires: expires, now: Date()) }
        return image
    }
}
