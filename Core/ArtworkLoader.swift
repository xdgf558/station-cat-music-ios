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
        let requestStarted = ContinuousClock.now
        let (bytes, response) = try await network.bytes(for: request)
        let responseReceived = ContinuousClock.now, responseTime = Date()
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
        let storedAt = Date()
        if let expires = ArtworkFreshness.expiration(response, responseTime: responseTime, storedAt: storedAt,
                responseDelay: ArtworkFreshness.seconds(requestStarted.duration(to: responseReceived)),
                residentTime: ArtworkFreshness.seconds(responseReceived.duration(to: .now))) {
            try? cache?.store(data, url: url, expires: expires, now: storedAt)
        }
        return image
    }
}

/// Conservative subset of RFC 9111 §§4.1/4.2.3. URL-only keys cannot match Vary.
nonisolated enum ArtworkFreshness {
    static func seconds(_ value: Duration) -> Double {
        Double(value.components.seconds) + Double(value.components.attoseconds) / 1e18
    }
    static func expiration(_ response: HTTPURLResponse, responseTime: Date, storedAt: Date,
                           responseDelay: Double, residentTime: Double) -> Date? {
        guard response.value(forHTTPHeaderField: "Set-Cookie") == nil,
              (response.value(forHTTPHeaderField: "Vary") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              responseDelay.isFinite, responseDelay >= 0, residentTime.isFinite, residentTime >= 0,
              storedAt >= responseTime else { return nil }
        let fields = (response.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let directives = fields.map { $0.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) } }
        guard fields.contains("public"), !directives.contains(where: { ["no-store", "no-cache", "private"].contains($0.first ?? "") }) else { return nil }
        let ages = directives.filter { $0.first == "max-age" }
        guard ages.count == 1, ages[0].count == 2,
              let lifetime = deltaSeconds(ages[0][1]), lifetime > 0,
              let age = deltaSeconds(response.value(forHTTPHeaderField: "Age") ?? "0"),
              let rawDate = response.value(forHTTPHeaderField: "Date") else { return nil }
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(secondsFromGMT: 0); date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"; date.isLenient = false
        guard let generated = date.date(from: rawDate) else { return nil }
        let apparentAge = max(0, responseTime.timeIntervalSince(generated))
        let correctedAge = max(apparentAge, age + responseDelay)
        let currentAge = correctedAge + max(residentTime, storedAt.timeIntervalSince(responseTime))
        let remaining = min(86400, lifetime - currentAge)
        return remaining > 0 ? storedAt.addingTimeInterval(remaining) : nil
    }
    private static func deltaSeconds(_ raw: String) -> Double? {
        // Ambiguous/invalid freshness is a miss, not a reason to extend a response's life.
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let result = Double(value), result.isFinite else { return nil }
        return result
    }
}
