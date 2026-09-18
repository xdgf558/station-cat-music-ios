import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Only attached when the separately gated native music client exists.
/// No audio URL or bearer is ever handed to Now Playing or a remote receiver.
@MainActor final class SystemPlayback: PlaybackSystem {
    private weak var playback: PlaybackService?
    private let session = AVAudioSession.sharedInstance()
    private let commands = MPRemoteCommandCenter.shared()
    private let info = MPNowPlayingInfoCenter.default()
    private var observers: [NSObjectProtocol] = []
    private var targets: [(MPRemoteCommand, Any)] = []
    private var active = true
    private var audioActive = false
    private var snapshot: PlaybackSnapshot?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?
    private let artworkLoader = ArtworkLoader()
    private let artworkHost: String
    init(playback: PlaybackService, artworkHost: String) {
        self.playback = playback; self.artworkHost = artworkHost
        register(commands.playCommand, .play); register(commands.pauseCommand, .pause)
        register(commands.togglePlayPauseCommand, .toggle); register(commands.nextTrackCommand, .next)
        register(commands.previousTrackCommand, .previous)
        let seek = commands.changePlaybackPositionCommand
        let token = seek.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent, event.positionTime.isFinite else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak self] in guard let self, self.active else { return }; self.playback?.handle(.seek(position)) }
            return .success
        }
        targets.append((seek, token))
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let resume = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            MainActor.assumeIsolated {
                guard let self, self.active else { return }
                if raw == AVAudioSession.InterruptionType.began.rawValue { self.playback?.interruptionBegan() }
                else if raw == AVAudioSession.InterruptionType.ended.rawValue { self.playback?.interruptionEnded(shouldResume: resume) }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated { guard let self, self.active else { return }; if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self.playback?.routeDisconnected() } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, self.active else { return }; self.audioActive = false; self.playback?.mediaServicesReset() }
        })
        publish(nil)
    }
    private func register(_ command: MPRemoteCommand, _ action: PlaybackCommand) {
        let token = command.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in guard let self, self.active else { return }; self.playback?.handle(action) }
            return .success
        }
        targets.append((command, token))
    }
    func activate() throws {
        guard active else { throw APIError.unavailable }
        if !audioActive {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true); audioActive = true
        }
    }
    func deactivate() {
        guard audioActive else { return }; audioActive = false
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
    func publish(_ value: PlaybackSnapshot?) {
        guard active else { return }
        snapshot = value
        commands.playCommand.isEnabled = value != nil && value?.playing == false
        commands.pauseCommand.isEnabled = value?.canPause == true
        commands.togglePlayPauseCommand.isEnabled = value != nil
        commands.nextTrackCommand.isEnabled = value?.canNext == true
        commands.previousTrackCommand.isEnabled = value?.canPrevious == true
        commands.changePlaybackPositionCommand.isEnabled = value?.canSeek == true
        let url = value?.track.coverUrl
        if artworkURL != url {
            artworkTask?.cancel(); artwork = nil; artworkURL = url
            if let url, url.scheme == "https", url.host == artworkHost, url.user == nil, url.password == nil,
               url.port == nil || url.port == 443 {
                artworkTask = Task { [weak self] in
                    do {
                        guard let loader = self?.artworkLoader,
                              let image = try await loader.load(url),
                              !Task.isCancelled, let self, self.active, self.artworkURL == url else { return }
                        let thumbnail = UIImage(cgImage: image)
                        self.artwork = MPMediaItemArtwork(boundsSize: thumbnail.size) { _ in thumbnail }; self.writeInfo()
                    } catch { /* Artwork never gates or retries audio. */ }
                }
            }
        }
        if value == nil { artworkTask?.cancel(); artwork = nil; artworkURL = nil }
        writeInfo()
    }
    private func writeInfo() {
        guard let snapshot else { info.nowPlayingInfo = nil; return }
        var fields: [String: Any] = [MPMediaItemPropertyTitle: snapshot.track.title, MPMediaItemPropertyArtist: snapshot.track.artist,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.position,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.playing ? 1.0 : 0.0, MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        if let artwork { fields[MPMediaItemPropertyArtwork] = artwork }
        info.nowPlayingInfo = fields
    }
    func shutdown() {
        guard active else { return }; deactivate(); publish(nil); active = false
        artworkTask?.cancel(); artworkTask = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        targets.forEach { $0.0.removeTarget($0.1) }; targets = []; playback = nil
    }
}
