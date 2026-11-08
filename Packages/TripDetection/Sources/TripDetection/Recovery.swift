import Foundation

/// A drive found in motion history that no recorded trip covers. It becomes a *recovered*,
/// unconfirmed journey; it never counts until the user confirms it (council D3).
public struct RecoveredInterval: Hashable, Codable, Sendable {
    public var start: Date
    public var end: Date
    /// The visits either side, if known: the platform layer suggests miles with `MKDirections`
    /// between them, flagged as estimated.
    public var from: Coordinate?
    public var to: Coordinate?

    public init(start: Date, end: Date, from: Coordinate?, to: Coordinate?) {
        self.start = start
        self.end = end
        self.from = from
        self.to = to
    }
}

public enum RecoveryPlanner {
    /// Turns Core Motion history into drives the live layer missed.
    ///
    /// Only the parts of each drive that no known trip covers are returned, so a recovered
    /// interval never overlaps a recorded trip and can't double-count it.
    ///
    /// - Parameters:
    ///   - history: samples oldest first, as `queryActivityStarting(from:to:)` returns them.
    ///     Each sample lasts until the next one starts; the last lasts until `now`.
    ///   - knownTrips: time ranges of trips already stored (any status, including in progress).
    ///   - visits: recent visits, to suggest start and end points.
    ///   - minimumDuration: shorter pieces are ignored.
    ///   - mergeGap: automotive runs separated by less than this are one drive. Core Motion can
    ///     report a long jam as stationary only, so this is generous.
    ///   - visitTolerance: visit times are estimates; allow this much slack when matching.
    public static func recover(history: [MotionSample], knownTrips: [DateInterval], visits: [Visit],
                               now: Date, minimumDuration: TimeInterval = 180,
                               mergeGap: TimeInterval = 300,
                               visitTolerance: TimeInterval = 120) -> [RecoveredInterval] {
        // 1. Automotive runs.
        var runs: [DateInterval] = []
        for (i, sample) in history.enumerated() where sample.isConfidentDriving {
            let end = i + 1 < history.count ? history[i + 1].startDate : now
            guard end > sample.startDate else { continue }
            if let last = runs.last, sample.startDate.timeIntervalSince(last.end) <= mergeGap {
                runs[runs.count - 1] = DateInterval(start: last.start, end: max(last.end, end))
            } else {
                runs.append(DateInterval(start: sample.startDate, end: end))
            }
        }

        // 2. Keep only what known trips don't cover.
        let pieces = runs.flatMap { uncovered(part: $0, by: knownTrips) }
            .filter { $0.duration >= minimumDuration }

        // 3. Suggest the visits either side.
        return pieces.map { piece in
            let from = visits.filter { ($0.departure ?? .distantFuture) <= piece.start + visitTolerance }
                .max { ($0.departure ?? .distantPast) < ($1.departure ?? .distantPast) }?.coordinate
            let to = visits.filter { ($0.arrival ?? .distantPast) >= piece.end - visitTolerance }
                .min { ($0.arrival ?? .distantFuture) < ($1.arrival ?? .distantFuture) }?.coordinate
            return RecoveredInterval(start: piece.start, end: piece.end, from: from, to: to)
        }
    }

    /// The parts of `interval` outside every one of `others`.
    static func uncovered(part interval: DateInterval, by others: [DateInterval]) -> [DateInterval] {
        let clipped = others.compactMap { interval.intersection(with: $0) }.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        var cursor = interval.start
        for piece in clipped {
            if piece.start > cursor { result.append(DateInterval(start: cursor, end: piece.start)) }
            cursor = max(cursor, piece.end)
        }
        if interval.end > cursor { result.append(DateInterval(start: cursor, end: interval.end)) }
        return result
    }

    /// Length of `interval` covered by the union of `others`.
    static func coveredDuration(of interval: DateInterval, by others: [DateInterval]) -> TimeInterval {
        interval.duration - uncovered(part: interval, by: others).reduce(0) { $0 + $1.duration }
    }
}
