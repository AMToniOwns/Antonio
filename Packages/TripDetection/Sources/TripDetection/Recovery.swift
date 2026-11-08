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
}

public enum RecoveryPlanner {
    /// Turns Core Motion history into drives the live layer missed.
    ///
    /// - Parameters:
    ///   - history: samples oldest first, as `queryActivityStarting(from:to:)` returns them.
    ///     Each sample lasts until the next one starts; the last lasts until `now`.
    ///   - knownTrips: time ranges of trips already stored (any status).
    ///   - visits: recent visits, to suggest start and end points.
    ///   - minimumDuration: shorter automotive runs are ignored.
    ///   - mergeGap: automotive runs separated by less than this are one drive (lights, jams).
    public static func recover(history: [MotionSample], knownTrips: [DateInterval], visits: [Visit],
                               now: Date, minimumDuration: TimeInterval = 180,
                               mergeGap: TimeInterval = 120) -> [RecoveredInterval] {
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

        // 2. Drop short runs and runs mostly covered by known trips.
        return runs.compactMap { run in
            guard run.duration >= minimumDuration else { return nil }
            let covered = coveredDuration(of: run, by: knownTrips)
            guard covered / run.duration <= 0.5 else { return nil }
            let from = visits.filter { ($0.departure ?? .distantFuture) <= run.start }
                .max { ($0.departure ?? .distantPast) < ($1.departure ?? .distantPast) }?.coordinate
            let to = visits.filter { ($0.arrival ?? .distantPast) >= run.end }
                .min { ($0.arrival ?? .distantFuture) < ($1.arrival ?? .distantFuture) }?.coordinate
            return RecoveredInterval(start: run.start, end: run.end, from: from, to: to)
        }
    }

    /// Length of `interval` covered by the union of `others`.
    static func coveredDuration(of interval: DateInterval, by others: [DateInterval]) -> TimeInterval {
        let clipped = others.compactMap { interval.intersection(with: $0) }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var cursor = interval.start
        for piece in clipped {
            let start = max(piece.start, cursor)
            if piece.end > start {
                total += piece.end.timeIntervalSince(start)
                cursor = piece.end
            }
        }
        return total
    }
}
