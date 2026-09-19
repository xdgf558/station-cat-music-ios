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
    var autoAdvance: Bool { state == .playing && (queue.canNext || queue.repeatMode == .one) }
    private(set) var queue = PlaybackQueue()
    private(set) var noticeKey: String?
    private(set) var sleepDeadline: Double?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var system: (any PlaybackSystem)?
    @ObservationIgnored var onListen: ((Track, String, Double, Double, String) -> Void)?
    private var listenMeter = AudibleListenMeter()
    private var listenID = UUID().uuidString
    @ObservationIgnored var onSelection: ((Track?) -> Void)?
    private var interrupted = false
    private var interruptionResumeDeadline: Double?
    private var queueAttempts = Set<UUID>()
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
    @ObservationIgnored private var player = PlaybackService.makePlayer()
    private static func makePlayer() -> AVPlayer { let value = AVPlayer(); value.allowsExternalPlayback = false; return value }
    @ObservationIgnored private let clock: any PlaybackClock
    @ObservationIgnored private let transport: any MediaHTTPTransport
    @ObservationIgnored private let loader: any MediaLoading
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    init(clock: any PlaybackClock = ContinuousPlaybackClock(), loader: any MediaLoading = UnavailableMediaLoader(), transport: any MediaHTTPTransport = NativeMediaTransport()) { self.clock = clock; self.loader = loader; self.transport = transport }
    var hasAudioSource: Bool { player.currentItem != nil }
    var isPlaying: Bool { player.rate > 0 }
    func attachSystem(_ value: any PlaybackSystem) { system?.shutdown(); system = value; publish() }
    private func publish() {
        guard let track = selectedTrack else { system?.publish(nil); return }
        system?.publish(PlaybackSnapshot(track: track, position: position, duration: duration, playing: isPlaying,
            canNext: queue.canNext, canPrevious: queue.canPrevious || position > 3, canSeek: [.playing, .paused, .completed].contains(state), canPause: state == .playing || state == .authorizing))
    }
    private func cancelInterruptionIntent() { interruptionResumeDeadline = nil }
    private func selectItem(_ track: Track) {
        boundary.deny(); stop(); selectedTrack = track; position = 0; duration = track.durationSeconds
        previewOffset = 0; activeVariant = "automatic"; state = .selected
        listenMeter = AudibleListenMeter(); listenID = UUID().uuidString
        onSelection?(track); publish()
    }
    func select(_ track: Track) { cancelInterruptionIntent(); queue.replace([track], startingAt: 0); queueAttempts = []; selectItem(track) }
    func setQueue(_ tracks: [Track], startingAt index: Int, play: Bool = true) {
        cancelInterruptionIntent(); queue.replace(tracks, startingAt: index); queueAttempts = []
        guard let track = queue.current else { clear(); return }; selectItem(track)
        if play { requestPlay() }
    }
    func chooseQueueEntry(_ id: UUID) {
        cancelInterruptionIntent(); guard let track = queue.choose(id) else { return }; queueAttempts = []; selectItem(track); requestPlay()
    }
    func removeQueueEntry(_ id: UUID) { _ = queue.remove(id); publish() }
    func setShuffle(_ enabled: Bool) { queue.setShuffle(enabled); publish() }
    func setRepeat(_ mode: PlaybackQueue.RepeatMode) { queue.repeatMode = mode; publish() }
    func next() {
        cancelInterruptionIntent(); queueAttempts = []
        guard let track = queue.advance() else { pause(); return }; selectItem(track); requestPlay()
    }
    func previous() {
        cancelInterruptionIntent(); queueAttempts = []
        if position > 3 { if state == .playing { seek(to: 0) } else { position = 0; requestPlay() }; return }
        guard let track = queue.previous() else { return }; selectItem(track); requestPlay()
    }
    func handle(_ command: PlaybackCommand) {
        switch command {
        case .play: if state != .playing && state != .authorizing { requestPlay() }
        case .pause: pause()
        case .toggle: if state == .playing || state == .authorizing { pause() } else { requestPlay() }
        case .next: next()
        case .previous: previous()
        case .seek(let seconds): seek(to: seconds)
        }
    }
    func configure(authorizer: any PlaybackAuthorizing) { clear(); self.authorizer = authorizer }
    func requestPlay(variant: String? = nil) {
        cancelInterruptionIntent(); queueAttempts = []; noticeKey = nil
        // A missing interruption-ended notification must not trap explicit user playback.
        // Audio-session activation below remains authoritative and may reject the attempt.
        interrupted = false
        begin(variant: variant ?? activeVariant, renewal: false)
    }
    private func begin(variant: String, renewal: Bool) {
        guard !interrupted, let track = selectedTrack, let authorizer else { state = .verificationRequired; publish(); return }
        if !renewal {
            if let id = queue.currentID { guard queueAttempts.insert(id).inserted else { noticeKey = "queueUnavailable"; deny(); return } }
            if track.access == .unavailable { skipUnavailable(); return }
        }
        // Every explicit resume obtains a fresh URL and a fresh hard deadline.
        if state == .completed { listenMeter = AudibleListenMeter(); listenID = UUID().uuidString }
        let resumePosition = (renewal || state == .paused) && activeVariant == variant ? position : 0
        if renewal {
            guard state == .playing, boundary.deadline != nil else { return }
        } else { boundary.deny(); stop(); state = .authorizing; publish() }
        let sequence = boundary.sequence, sent = clock.now
        authorizationTask = Task { [weak self] in
            do {
                let resolvedVariant = variant == "automatic" ? try await authorizer.preferredVariant(for: track) : variant
                try Task.checkCancellation()
                let authorization = try await authorizer.authorize(track: track, variant: resolvedVariant)
                guard let self, !Task.isCancelled, self.boundary.sequence == sequence,
                      self.selectedTrack == track, await authorizer.isCurrent(authorization) else { return }
                guard !Task.isCancelled, self.boundary.sequence == sequence, self.selectedTrack == track else { return }
                let received = self.clock.now, grant = authorization.grant
                try self.installBoundary(serverNow: authorization.serverNow.timeIntervalSince1970,
                    validUntil: grant.playbackValidUntil.timeIntervalSince1970, sent: sent, received: received, sequence: sequence)
                guard let deadline = self.boundary.deadline else { throw APIError.requiresAuthentication }
                try self.system?.activate()
                guard self.clock.now < deadline else { throw APIError.requiresAuthentication }
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
                else { self.isSeeking = false; self.player.play() }; self.publish()
                let renewAfter = grant.revalidateAt.timeIntervalSince(authorization.serverNow) - (received - sent) - 2
                if renewAfter > 1 && self.clock.now + renewAfter < deadline {
                    self.renewalTask = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(renewAfter)) } catch { return }
                        guard let self, self.boundary.sequence == sequence, self.state == .playing else { return }
                        self.begin(variant: grant.variant, renewal: true)
                    }
                }
                self.progressTask = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                        guard let self, self.boundary.sequence == sequence else { return }
                        self.checkDeadline()
                        self.capturePosition()
                        if self.listenMeter.sample(wall: self.clock.now, media: self.position,
                            playing: self.state == .playing && !self.isSeeking && self.player.timeControlStatus == .playing && !self.player.isMuted && self.player.volume > 0), let track = self.selectedTrack {
                            self.onListen?(track, self.activeVariant, self.listenMeter.seconds, self.position, self.listenID)
                        }
                        self.checkSleepTimer(); self.publish()
                        if self.player.currentItem?.status == .failed { self.deny(); return }
                    }
                }
            } catch {
                guard let self, self.boundary.sequence == sequence, !Task.isCancelled else { return }
                if !renewal, let error = error as? APIError, [APIError.rejected(403), .rejected(404)].contains(error) { self.skipUnavailable() }
                else { self.deny() }
            }
        }
    }
    private func removeEndObserver() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver = nil
    }
    private func completeNaturally() {
        let completedID = queue.currentID, completedVariant = activeVariant
        boundary.deny(); stop(); position = 0; state = .completed
        checkSleepTimer()
        guard noticeKey != "sleepFinished" else { publish(); return }
        queueAttempts = []
        if let track = queue.advance(natural: true) {
            selectItem(track)
            if queue.currentID == completedID { activeVariant = completedVariant }
            begin(variant: activeVariant, renewal: false)
        } else { publish() }
    }
    private func capturePosition() {
        guard !isSeeking, player.currentItem != nil else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite { position = max(0, min(duration, seconds)) }
    }
    func pause() { cancelInterruptionIntent(); pauseForSystem() }
    private func pauseForSystem() { capturePosition(); boundary.deny(); stop(); state = .paused; publish() }
    func seek(to seconds: Double) {
        listenMeter.resetProgress()
        cancelInterruptionIntent(); checkDeadline()
        guard seconds.isFinite else { return }
        if state == .paused || state == .completed { position = max(0, min(duration, seconds)); state = .paused; publish(); return }
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
                self.player.play(); self.publish()
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
    func checkDeadline() { if boundary.expire(at: clock.now) { stop(); state = .verificationRequired; cancelInterruptionIntent(); publish() } }
    func deny() { cancelInterruptionIntent(); boundary.deny(); stop(); state = .verificationRequired; publish() }
    private func skipUnavailable() {
        noticeKey = "queueSkipped"
        guard queueAttempts.count < queue.entries.count, let track = queue.advance(),
              let id = queue.currentID, !queueAttempts.contains(id) else { noticeKey = "queueUnavailable"; deny(); return }
        selectItem(track); begin(variant: activeVariant, renewal: false)
    }
    func interruptionBegan() {
        guard !interrupted else { return }
        interrupted = true
        interruptionResumeDeadline = state == .playing ? boundary.deadline : nil
        pauseForSystem()
    }
    func interruptionEnded(shouldResume: Bool) {
        guard interrupted else { return }; interrupted = false
        let valid = interruptionResumeDeadline.map { clock.now < $0 } ?? false
        interruptionResumeDeadline = nil
        checkSleepTimer()
        if shouldResume && valid && state == .paused && noticeKey != "sleepFinished" { requestPlay() }
    }
    func routeDisconnected() { noticeKey = "headphonesDisconnected"; pause() }
    func mediaServicesReset() {
        capturePosition(); deny(); interrupted = false
        player = Self.makePlayer(); state = selectedTrack == nil ? .idle : .paused; noticeKey = "mediaReset"; publish()
    }
    func setSleepTimer(seconds: Double?) {
        sleepTask?.cancel(); sleepTask = nil; sleepDeadline = nil
        guard let seconds, seconds.isFinite, seconds > 0, seconds <= 86400 else { return }
        sleepDeadline = clock.now + seconds
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.checkSleepTimer()
        }
    }
    func checkSleepTimer() {
        guard let end = sleepDeadline, clock.now >= end else { return }
        setSleepTimer(seconds: nil); pause(); noticeKey = "sleepFinished"; publish()
    }
    func becameActive() { checkDeadline(); checkSleepTimer(); publish() }
    func clear() {
        cancelInterruptionIntent(); boundary.deny(); stop(); setSleepTimer(seconds: nil)
        queue.clear(); queueAttempts = []; selectedTrack = nil; position = 0; duration = 0; state = .idle; noticeKey = nil
        onSelection?(nil); system?.publish(nil)
    }
    func shutdown() { clear(); system?.shutdown(); system = nil; onSelection = nil }
    func stop() { seekSerial += 1; isSeeking = false; removeEndObserver(); renewalTask?.cancel(); renewalTask = nil; authorizationTask?.cancel(); authorizationTask = nil; progressTask?.cancel(); progressTask = nil; nativeLoader?.cancelAll(); nativeLoader = nil; player.pause(); loader.cancelAll(); player.replaceCurrentItem(with: nil); deadlineTask?.cancel(); deadlineTask = nil; system?.deactivate() }
}
