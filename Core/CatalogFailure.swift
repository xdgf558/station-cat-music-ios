import Foundation

/// Allow-listed diagnostics only: never retain response bodies, URLs or credentials.
nonisolated enum CatalogFailure: String, Equatable, Sendable {
    case timeout, offline, connection, service, configuration, payload, unknown
    init(_ error: Error) {
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: self = .timeout
            case .notConnectedToInternet, .dataNotAllowed: self = .offline
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .networkConnectionLost,
                 .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid: self = .connection
            default: self = .unknown
            }
        } else if let api = error as? APIError {
            switch api {
            case .networkDisabled: self = .configuration
            case .rejected, .unavailable: self = .service
            case .invalidPayload: self = .payload
            default: self = .unknown
            }
        } else if error is DecodingError { self = .payload }
        else { self = .unknown }
    }
    var messageKey: String { "startupFailure." + rawValue }
}
