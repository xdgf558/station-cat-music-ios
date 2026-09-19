import Foundation

nonisolated struct PlaybackQueue: Sendable {
    enum RepeatMode: String, CaseIterable, Sendable { case off, all, one }
    struct Entry: Identifiable, Equatable, Sendable { let id: UUID; let track: Track }
    private(set) var entries: [Entry] = []
    private(set) var order: [UUID] = []
    private(set) var currentID: UUID?
    private(set) var history: [UUID] = []
    private(set) var shuffled = false
    var repeatMode: RepeatMode = .off
    var current: Track? { entries.first { $0.id == currentID }?.track }
    var currentIndex: Int? { order.firstIndex { $0 == currentID } }
    var orderedEntries: [Entry] { let values = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) }); return order.compactMap { values[$0] } }
    var canNext: Bool { guard let i = currentIndex else { return false }; return i + 1 < order.count || repeatMode == .all }
    var canPrevious: Bool { !history.isEmpty }
    mutating func replace(_ tracks: [Track], startingAt index: Int) {
        clear(); guard tracks.indices.contains(index), tracks.count <= 500 else { return }
        entries = tracks.map { Entry(id: UUID(), track: $0) }; order = entries.map(\.id); currentID = entries[index].id
    }
    mutating func clear() { entries = []; order = []; currentID = nil; history = []; shuffled = false; repeatMode = .off }
    mutating func setShuffle(_ enabled: Bool) {
        guard enabled != shuffled, let currentID else { return }; shuffled = enabled
        if enabled { order = [currentID] + entries.map(\.id).filter { $0 != currentID }.shuffled() }
        else { order = entries.map(\.id) }
    }
    mutating func advance(natural: Bool = false) -> Track? {
        guard let id = currentID, let i = currentIndex else { return nil }
        if natural && repeatMode == .one { return current }
        let next = i + 1 < order.count ? order[i + 1] : repeatMode == .all ? order.first : nil
        guard let next else { return nil }
        history.append(id); if history.count > 500 { history.removeFirst() }; currentID = next
        return current
    }
    mutating func previous() -> Track? {
        guard let last = history.popLast() else { return nil }; currentID = last; return current
    }
    mutating func choose(_ id: UUID) -> Track? {
        guard entries.contains(where: { $0.id == id }) else { return nil }
        if let currentID, currentID != id { history.append(currentID); if history.count > 500 { history.removeFirst() } }
        currentID = id; return current
    }
    mutating func remove(_ id: UUID) -> Bool {
        guard id != currentID else { return false }
        entries.removeAll { $0.id == id }; order.removeAll { $0 == id }; history.removeAll { $0 == id }; return true
    }
}

nonisolated enum PlaybackCommand: Sendable { case play, pause, toggle, next, previous, seek(Double) }
nonisolated struct PlaybackSnapshot: Equatable, Sendable {
    let track: Track
    let position: Double
    let duration: Double
    let playing: Bool
    let canNext: Bool
    let canPrevious: Bool
    let canSeek: Bool
    let canPause: Bool
}
@MainActor protocol PlaybackSystem: AnyObject {
    func activate() throws
    func deactivate()
    func publish(_ snapshot: PlaybackSnapshot?)
    func shutdown()
}
