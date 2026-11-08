import Foundation
@testable import TripDetection

/// Builds synthetic event streams: a phone moving due north from Leeds at a set speed.
struct Scenario {
    static let t0 = Date(timeIntervalSince1970: 1_793_000_000) // a weekday in Oct 2026
    static let home = Coordinate(latitude: 53.8, longitude: -1.55)
    static let metresPerDegreeLatitude = 111_195.0

    var detector = TripDetector()
    var effects: [DetectionEffect] = []
    var now = Scenario.t0
    var position = Scenario.home

    init(lastStop: Coordinate? = Scenario.home) {
        var state = DetectorState()
        state.lastStop = lastStop
        detector = TripDetector(state: state)
    }

    @discardableResult
    mutating func send(_ event: DetectionEvent) -> [DetectionEffect] {
        let out = detector.handle(event)
        effects += out
        return out
    }

    mutating func wake(_ reason: WakeReason = .significantLocationChange) {
        send(.wake(reason, at: now))
    }

    /// One fix per second for `seconds`, moving north at `speed` m/s.
    mutating func move(seconds: Int, speed: Double, accuracy: Double = 10) {
        for _ in 0..<seconds {
            now += 1
            position.latitude += speed / Self.metresPerDegreeLatitude
            let fix = LocationFix(timestamp: now, coordinate: position, horizontalAccuracy: accuracy,
                                  speed: speed, speedAccuracy: 0.5)
            send(.fix(fix, receivedAt: now))
        }
    }

    /// Stand still for `seconds`, one fix every `every` seconds.
    mutating func wait(seconds: Int, every: Int = 5) {
        var elapsed = 0
        while elapsed < seconds {
            let step = min(every, seconds - elapsed)
            now += TimeInterval(step)
            elapsed += step
            let fix = LocationFix(timestamp: now, coordinate: position, horizontalAccuracy: 10,
                                  speed: 0, speedAccuracy: 0.5)
            send(.fix(fix, receivedAt: now))
        }
    }

    mutating func motion(_ kinds: Set<MotionSample.Kind>, _ confidence: MotionSample.Confidence = .high) {
        send(.motion(MotionSample(startDate: now, kinds: kinds, confidence: confidence), receivedAt: now))
    }

    var trips: [TripSegment] {
        effects.compactMap { effect -> TripSegment? in
            if case let .emitTrip(trip) = effect { return trip }
            return nil
        }
    }

    var phase: DetectorState.Phase.Kind { detector.state.phase.kind }
}
