import Foundation
import ImageIO

/// Its own executor owns bounded network consumption and ImageIO work.
/// Only the small, immutable thumbnail crosses back to the UI actor.
actor ArtworkLoader {
    static let maximumBytes = 2_097_152
    private let protocolClasses: [AnyClass]?
    init(protocolClasses: [AnyClass]? = nil) { self.protocolClasses = protocolClasses }
    func load(_ url: URL) async throws -> CGImage? {
        try Task.checkCancellation()
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 5
        if let protocolClasses { config.protocolClasses = protocolClasses }
        let network = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { network.invalidateAndCancel() }
        let (bytes, response) = try await network.bytes(from: url)
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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
        try Task.checkCancellation()
        return image
    }
}
