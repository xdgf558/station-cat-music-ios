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
    enum State: Equatable { case idle, selected, verificationRequired }
    private(set) var selectedTrack: Track?
    private(set) var state: State = .idle
    private(set) var boundary = PlaybackBoundary()
    private(set) var autoAdvance = false
    let identity = UUID()
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let clock: any PlaybackClock
    @ObservationIgnored private let loader: any MediaLoading
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    init(clock: any PlaybackClock = ContinuousPlaybackClock(), loader: any MediaLoading = UnavailableMediaLoader()) { self.clock = clock; self.loader = loader }
    var hasAudioSource: Bool { player.currentItem != nil }
    var isPlaying: Bool { player.rate > 0 }
    func select(_ track: Track) { boundary.deny(); stop(); selectedTrack = track; state = .selected }
    // M1 deliberately never installs remote audio. UI selection is not authorization.
    func requestPlay() { state = .verificationRequired }
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
    func stop() { player.pause(); loader.cancelAll(); player.replaceCurrentItem(with: nil); autoAdvance = false; deadlineTask?.cancel(); deadlineTask = nil }
}
