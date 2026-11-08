import Foundation
@testable import TripDetection

/// Builds event streams for a phone moving due north from Leeds. Helpers model what iOS
/// actually sends: `move` gives fixes while moving, `waitWithFixes` gives fixes while still
/// (GPS drift past the distance filter), and `park` gives nothing at all.
struct Scenario {
    static let t0 = Date(timeIntervalSince1970: 1_793_000_000) // late October 2026
    static let home = Coordinate(latitude: 53.8, longitude: -1.55)
    static let metresPerDegreeLatitude = 111_195.0

    var detector: TripDetector
    var events: [DetectionEvent] = []
    var effects: [DetectionEffect] = []
    var now = Scenario.t0
    var position = Scenario.home

    init(lastStop: Coordinate? = Scenario.home, lastStopAt: Date = Scenario.t0 - 3600) {
        var state = DetectorState()
        state.lastStop = lastStop.map { DetectorState.Stop(coordinate: $0, at: lastStopAt) }
        detector = TripDetector(state: state)
    }

    @discardableResult
    mutating func send(_ event: DetectionEvent) -> [DetectionEffect] {
        events.append(event)
        let out = detector.handle(event)
        effects += out
        return out
    }

    mutating func wake(_ reason: WakeReason = .significantLocationChange) {
        send(.wake(reason, at: now))
    }

    /// One fix per second for `seconds`, moving north at `speed` m/s. With `reportSpeed`
    /// false the fixes carry speed -1, as weak fixes often do.
    mutating func move(seconds: Int, speed: Double, reportSpeed: Bool = true) {
        for _ in 0..<seconds {
            now += 1
            position.latitude += speed / Self.metresPerDegreeLatitude
            fix(speed: reportSpeed ? speed : -1)
        }
    }

    /// Standing still for `seconds`, one fix every `every` seconds.
    mutating func waitWithFixes(seconds: Int, every: Int = 5, reportSpeed: Bool = true) {
        var elapsed = 0
        while elapsed < seconds {
            let step = min(every, seconds - elapsed)
            now += TimeInterval(step)
            elapsed += step
            fix(speed: reportSpeed ? 0 : -1)
        }
    }

    /// Parked with a distance filter: time passes and nothing is delivered.
    mutating func park(seconds: TimeInterval) {
        now += seconds
    }

    mutating func fix(speed: Double, accuracy: Double = 10) {
        let fix = LocationFix(timestamp: now, coordinate: position, horizontalAccuracy: accuracy,
                              speed: speed, speedAccuracy: speed >= 0 ? 0.5 : -1)
        send(.fix(fix, receivedAt: now))
    }

    mutating func motion(_ kinds: Set<MotionSample.Kind>, _ confidence: MotionSample.Confidence = .high) {
        send(.motion(MotionSample(startDate: now, kinds: kinds, confidence: confidence), receivedAt: now))
    }

    mutating func timer(_ id: TimerID, at: Date) {
        send(.timerFired(id, at: at))
    }

    var trips: [TripSegment] {
        effects.compactMap { effect -> TripSegment? in
            if case let .emitTrip(trip) = effect { return trip }
            return nil
        }
    }

    var logs: [Diagnostic] {
        effects.compactMap { effect -> Diagnostic? in
            if case let .log(diagnostic) = effect { return diagnostic }
            return nil
        }
    }

    var phase: DetectorState.Phase.Kind { detector.state.phase.kind }

    var lastPointTime: Date? {
        switch detector.state.phase {
        case let .driving(t), let .stopping(t, _): return t.points.last?.timestamp
        default: return nil
        }
    }

    /// Drives `seconds` at 13 m/s (~29 mph) from a wake, ending in Driving.
    mutating func startDriving(seconds: Int = 120) {
        wake()
        move(seconds: seconds, speed: 13)
    }
}
