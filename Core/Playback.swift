import Foundation
import AVFoundation
import Observation

nonisolated struct PlaybackBoundary: Sendable {
    private(set) var deadline: Double?
    private(set) var sequence = 0
    private(set) var requiresExplicitResume = false
    mutating func install(serverNow: Double, validUntil: Double, sent: Double, received: Double, sequence: Int) throws {
        guard sequence == self.sequence, [serverNow, validUntil, sent, received].allSatisfy(\.isFinite), received >= sent else { throw APIError.staleResponse }
        let budget = validUntil - serverNow - (received - sent) - 2
        guard budget > 0 else { throw APIError.requiresAuthentication }
        deadline = received + budget
    }
    mutating func expire(at now: Double) -> Bool {
        guard let deadline, now >= deadline else { return false }
        self.deadline = nil; sequence += 1; requiresExplicitResume = true
        return true
    }
    mutating func deny() { deadline = nil; sequence += 1; requiresExplicitResume = true }
    mutating func userResumed() { requiresExplicitResume = false }
}
@MainActor protocol PlaybackClock { var now: Double { get } }
@MainActor struct ContinuousPlaybackClock: PlaybackClock {
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now
    var now: Double {
        let c = origin.duration(to: clock.now).components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
@MainActor protocol MediaLoading { func cancelAll() }
@MainActor final class UnavailableMediaLoader: MediaLoading { func cancelAll() {} }
@MainActor @Observable final class PlaybackService {
    enum State: Equatable { case idle, selected, verificationRequired, authorizing, playing, paused, completed }
    private(set) var selectedTrack: Track?
    private(set) var state: State = .idle
    private(set) var boundary = PlaybackBoundary()
    private(set) var autoAdvance = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var previewOffset: Double = 0
    private var activeVariant = "full"
    @ObservationIgnored private var seekSerial = 0
    @ObservationIgnored private var isSeeking = false
    private var authorizer: (any PlaybackAuthorizing)?
    @ObservationIgnored private var nativeLoader: NativeMediaLoader?
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var renewalTask: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    let identity = UUID()
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let clock: any PlaybackClock
    @ObservationIgnored private let transport: any MediaHTTPTransport
    @ObservationIgnored private let loader: any MediaLoading
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    init(clock: any PlaybackClock = ContinuousPlaybackClock(), loader: any MediaLoading = UnavailableMediaLoader(), transport: any MediaHTTPTransport = NativeMediaTransport()) { self.clock = clock; self.loader = loader; self.transport = transport }
    var hasAudioSource: Bool { player.currentItem != nil }
    var isPlaying: Bool { player.rate > 0 }
    func select(_ track: Track) { boundary.deny(); stop(); selectedTrack = track; position = 0; duration = track.durationSeconds; previewOffset = 0; activeVariant = "full"; state = .selected }
    func configure(authorizer: any PlaybackAuthorizing) { deny(); self.authorizer = authorizer }
    func requestPlay(variant: String? = nil) { begin(variant: variant ?? ((state == .paused || state == .completed) ? activeVariant : "full"), renewal: false) }
    private func begin(variant: String, renewal: Bool) {
        guard let track = selectedTrack, let authorizer else { state = .verificationRequired; return }
        // Every explicit resume obtains a fresh URL and a fresh hard deadline.
        let resumePosition = (renewal || state == .paused) && activeVariant == variant ? position : 0
        if renewal {
            guard state == .playing, boundary.deadline != nil else { return }
        } else { boundary.deny(); stop(); state = .authorizing }
        let sequence = boundary.sequence, sent = clock.now
        authorizationTask = Task { [weak self] in
            do {
                let authorization = try await authorizer.authorize(track: track, variant: variant)
                guard let self, !Task.isCancelled, self.boundary.sequence == sequence,
                      self.selectedTrack == track, await authorizer.isCurrent(authorization) else { return }
                let received = self.clock.now, grant = authorization.grant
                try self.installBoundary(serverNow: authorization.serverNow.timeIntervalSince1970,
                    validUntil: grant.playbackValidUntil.timeIntervalSince1970, sent: sent, received: received, sequence: sequence)
                guard let deadline = self.boundary.deadline else { throw APIError.requiresAuthentication }
                let channel = AuthorizedMediaChannel(authorization: authorization, authorizer: authorizer,
                    transport: self.transport, lifetime: deadline - self.clock.now)
                let loader = NativeMediaLoader(channel: channel) { [weak self] in
                    guard self?.boundary.sequence == sequence else { return }; self?.deny()
                }
                self.nativeLoader?.cancelAll(); self.progressTask?.cancel(); self.renewalTask?.cancel()
                self.nativeLoader = loader
                if renewal { self.capturePosition() }
                self.activeVariant = grant.variant; self.duration = grant.durationSeconds; self.previewOffset = grant.previewSourceStartSeconds ?? 0; self.position = min(renewal ? self.position : resumePosition, grant.durationSeconds)
                self.removeEndObserver()
                let item = AVPlayerItem(asset: loader.asset())
                self.player.replaceCurrentItem(with: item)
                self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
                    MainActor.assumeIsolated {
                        guard let self, let item, self.player.currentItem === item, self.boundary.sequence == sequence else { return }
                        self.completeNaturally()
                    }
                }
                self.boundary.userResumed(); self.state = .playing
                if self.position > 0 { self.seekCurrentItem(to: self.position) }
                else { self.isSeeking = false; self.player.play() }
                let renewAfter = grant.revalidateAt.timeIntervalSince(authorization.serverNow) - (received - sent) - 2
                if renewAfter > 1 && self.clock.now + renewAfter < deadline {
                    self.renewalTask = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(renewAfter)) } catch { return }
                        guard let self, self.boundary.sequence == sequence, self.state == .playing else { return }
                        self.begin(variant: variant, renewal: true)
                    }
                }
                self.progressTask = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                        guard let self, self.boundary.sequence == sequence else { return }
                        self.checkDeadline()
                        self.capturePosition()
                        if self.player.currentItem?.status == .failed { self.deny(); return }
                    }
                }
            } catch {
                guard let self, self.boundary.sequence == sequence, !Task.isCancelled else { return }; self.deny()
            }
        }
    }
    private func removeEndObserver() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver = nil
    }
    private func completeNaturally() {
        boundary.deny(); stop(); position = 0; state = .completed
    }
    private func capturePosition() {
        guard !isSeeking, player.currentItem != nil else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite { position = max(0, min(duration, seconds)) }
    }
    func pause() { capturePosition(); boundary.deny(); stop(); state = .paused }
    func seek(to seconds: Double) {
        checkDeadline()
        guard state == .playing, boundary.deadline != nil, seconds.isFinite else { return }
        seekCurrentItem(to: max(0, min(duration, seconds)))
    }
    private func seekCurrentItem(to seconds: Double) {
        guard let item = player.currentItem else { return }
        seekSerial += 1; let ticket = seekSerial, sequence = boundary.sequence
        position = seconds; isSeeking = true; player.pause()
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
            Task { @MainActor in
                guard let self, let item, self.player.currentItem === item, self.seekSerial == ticket, self.boundary.sequence == sequence else { return }
                self.isSeeking = false; self.checkDeadline()
                guard self.state == .playing, self.boundary.deadline != nil else { return }
                guard finished else { self.deny(); return }
                self.player.play()
            }
        }
    }
    func installBoundary(serverNow: Double, validUntil: Double, sent: Double, received: Double, sequence: Int) throws {
        try boundary.install(serverNow: serverNow, validUntil: validUntil, sent: sent, received: received, sequence: sequence)
        deadlineTask?.cancel()
        guard let deadline = boundary.deadline else { return }
        let remaining = max(0, deadline - clock.now)
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            self?.checkDeadline()
        }
    }
    func checkDeadline() { if boundary.expire(at: clock.now) { stop(); state = .verificationRequired } }
    func deny() { boundary.deny(); stop(); state = .verificationRequired }
    func stop() { seekSerial += 1; isSeeking = false; removeEndObserver(); renewalTask?.cancel(); renewalTask = nil; authorizationTask?.cancel(); authorizationTask = nil; progressTask?.cancel(); progressTask = nil; nativeLoader?.cancelAll(); nativeLoader = nil; player.pause(); loader.cancelAll(); player.replaceCurrentItem(with: nil); autoAdvance = false; deadlineTask?.cancel(); deadlineTask = nil }
}
