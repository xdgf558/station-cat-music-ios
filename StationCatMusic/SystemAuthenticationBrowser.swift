import AuthenticationServices
import UIKit

@MainActor final class SystemAuthenticationBrowser: NSObject, AuthenticationBrowser, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var activeID: UUID?
    func authorize(url: URL, callback: URL) async throws -> URL {
        guard session == nil, let host = callback.host else { throw APIError.invalidRequest }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.activeID = id
                let session = ASWebAuthenticationSession(url: url, callback: .https(host: host, path: callback.path)) { [weak self] url, error in
                    Task { @MainActor in
                        if let url { self?.finish(.success(url), id: id) }
                        else if let cancelled = error as? ASWebAuthenticationSessionError, cancelled.code == .canceledLogin {
                            self?.finish(.failure(CancellationError()), id: id)
                        } else { self?.finish(.failure(error ?? APIError.invalidPayload), id: id) }
                    }
                }
                session.prefersEphemeralWebBrowserSession = true
                session.presentationContextProvider = self
                self.session = session
                if !session.start() { finish(.failure(APIError.unavailable), id: id) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.activeID == id else { return }
                self?.session?.cancel(); self?.finish(.failure(CancellationError()), id: id)
            }
        }
    }
    private func finish(_ result: Result<URL, Error>, id: UUID) {
        guard activeID == id else { return }
        let continuation = continuation; self.continuation = nil; session = nil; activeID = nil
        continuation?.resume(with: result)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? UIWindow()
    }
}
