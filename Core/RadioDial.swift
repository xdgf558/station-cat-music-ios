import Foundation

/// Visual catalog positions, not broadcast frequencies or a playback schedule.
nonisolated enum RadioDial {
    static let frequencies: [Double] = [88.6, 91.2, 94.7, 98.3, 102.5, 106.1]
    static func dragged(from start: Double, translation: Double) -> Double {
        guard start.isFinite, translation.isFinite else { return frequencies[0] }
        return min(108, max(87.5, start - translation / 70))
    }
    static func nearest(_ value: Double, count: Int) -> Int? {
        guard value.isFinite, count > 0 else { return nil }
        return frequencies.prefix(min(count, frequencies.count)).indices.min {
            abs(frequencies[$0] - value) < abs(frequencies[$1] - value)
        }
    }
    static func adjacent(_ index: Int, by delta: Int, count: Int) -> Int? {
        let count = min(count, frequencies.count)
        guard count > 0 else { return nil }
        let bounded = min(count - 1, max(0, index))
        let step = delta % count
        return (bounded + step + count) % count
    }
}
