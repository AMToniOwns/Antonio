import Foundation

/// Tunable thresholds. Defaults are the Phase 0 values (§3.3); the test run tunes them.
public struct DetectorConfig: Hashable, Codable, Sendable {
    public var candidateTimeout: TimeInterval = 120
    public var stopTimeout: TimeInterval = 240
    public var drivingSpeed: Double = 6           // m/s
    public var stoppedSpeed: Double = 2           // m/s
    public var fastFixesNeeded = 3
    public var minimumDisplacement: Double = 300  // metres from the last stop
    public var maxHorizontalAccuracy: Double = 65
    public var maxFixAge: TimeInterval = 10
    public var maxImpliedSpeed: Double = 70       // m/s
    public var straightLineGapLimit: TimeInterval = 120
    public var minimumTripMetres: Double = 482.8  // 0.3 miles
    public var motionHistoryWindow: TimeInterval = 300
    public var stopRegionRadius: Double = 150

    public init() {}
}

/// The detector's persisted state. Codable so it survives a background relaunch.
public struct DetectorState: Hashable, Codable, Sendable {
    public enum Phase: Hashable, Codable, Sendable {
        case idle
        case candidate(Candidate)
        case driving(TripInProgress)
        case stopping(TripInProgress, since: Date)
    }

    public struct Candidate: Hashable, Codable, Sendable {
        public var since: Date
        public var reason: WakeReason
        public var hasDrivingEvidence: Bool
        public var fastFixes: Int
        public var lastEvidenceAt: Date
        public var fixes: [LocationFix]
    }

    public struct TripInProgress: Hashable, Codable, Sendable {
        public var startedAt: Date
        public var startCoordinate: Coordinate
        public var startedBy: WakeReason
        public var points: [LocationFix]
        public var measuredMetres: Double
        public var gaps: [DistanceGap]
    }

    public var phase: Phase = .idle
    public var lastStop: Coordinate?
    /// The latest motion sample, used to tell "stopped at lights" from "parked".
    public var lastMotion: MotionSample?

    public init() {}
}

/// The trip state machine (Phase 0 §3.3). Pure: events in, effects out, no clocks and no
/// Core Location. Feed it every event in delivery order and carry out the effects it returns.
public struct TripDetector: Sendable {
    public static let version = "td-0.1.0"

    public private(set) var state: DetectorState
    public let config: DetectorConfig

    public init(state: DetectorState = DetectorState(), config: DetectorConfig = DetectorConfig()) {
        self.state = state
        self.config = config
    }

    public mutating func handle(_ event: DetectionEvent) -> [DetectionEffect] {
        var effects: [DetectionEffect] = []
        let before = state

        switch event {
        case let .wake(reason, at):
            if case .idle = state.phase {
                startCandidate(reason: reason, at: at, effects: &effects)
            }

        case let .relaunched(at):
            // Restore live tracking first: the session must be recreated straight after relaunch.
            switch state.phase {
            case .idle:
                startCandidate(reason: .significantLocationChange, at: at, effects: &effects)
            case .candidate:
                effects.append(.startLive)
                effects.append(.scheduleTimer(.candidateTimeout, at: at + config.candidateTimeout))
            case .driving:
                effects.append(.startLive)
            case let .stopping(_, since):
                effects.append(.startLive)
                effects.append(.scheduleTimer(.stopTimeout, at: since + config.stopTimeout))
            }

        case let .fix(fix, receivedAt):
            guard accepts(fix, receivedAt: receivedAt) else { break }
            handleFix(fix, effects: &effects)

        case let .motion(sample, _):
            state.lastMotion = sample
            handleMotion([sample], effects: &effects)

        case let .motionHistory(samples, _):
            if let last = samples.last { state.lastMotion = last }
            handleMotion(samples, effects: &effects)

        case let .visit(visit, receivedAt):
            if visit.arrival != nil, visit.departure == nil {
                switch state.phase {
                case let .stopping(trip, since):
                    finish(trip, endedAt: since, effects: &effects)
                case let .driving(trip):
                    finish(trip, endedAt: visit.arrival ?? receivedAt, effects: &effects)
                default:
                    state.lastStop = visit.coordinate
                }
            }

        case let .timerFired(id, at):
            handleTimer(id, at: at, effects: &effects)

        case let .authorizationChanged(auth, precise, _):
            switch auth {
            case .always: break
            case .whenInUse: effects.append(.notify(.permissionDowngraded))
            case .denied: effects.append(.notify(.locationDenied))
            case .notDetermined: break
            }
            if !precise { effects.append(.notify(.preciseLocationOff)) }

        case let .assistedStart(at):
            switch state.phase {
            case .idle:
                startCandidate(reason: .assisted, at: at, effects: &effects)
                markEvidence(at: at)
            case var .candidate(c):
                c.hasDrivingEvidence = true
                c.lastEvidenceAt = at
                state.phase = .candidate(c)
            default: break
            }
            promoteCandidateIfReady(effects: &effects)

        case let .assistedStop(at):
            switch state.phase {
            case let .driving(trip): finish(trip, endedAt: at, effects: &effects)
            case let .stopping(trip, since): finish(trip, endedAt: since, effects: &effects)
            case .candidate: abandonCandidate(effects: &effects)
            case .idle: break
            }
        }

        if shouldPersist(before: before) { effects.append(.persist(state)) }
        return effects
    }

    // MARK: - Fix filtering

    private func accepts(_ fix: LocationFix, receivedAt: Date) -> Bool {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= config.maxHorizontalAccuracy else { return false }
        guard receivedAt.timeIntervalSince(fix.timestamp) <= config.maxFixAge else { return false }
        if let previous = lastAcceptedFix {
            let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { return false }
            if previous.coordinate.distance(to: fix.coordinate) / dt > config.maxImpliedSpeed { return false }
        }
        return true
    }

    private var lastAcceptedFix: LocationFix? {
        switch state.phase {
        case .idle: return nil
        case let .candidate(c): return c.fixes.last
        case let .driving(t), let .stopping(t, _): return t.points.last
        }
    }

    // MARK: - Transitions

    private mutating func startCandidate(reason: WakeReason, at: Date, effects: inout [DetectionEffect]) {
        state.phase = .candidate(.init(since: at, reason: reason, hasDrivingEvidence: false,
                                       fastFixes: 0, lastEvidenceAt: at, fixes: []))
        effects.append(.startLive)
        effects.append(.queryMotionHistory(from: at - config.motionHistoryWindow))
        effects.append(.scheduleTimer(.candidateTimeout, at: at + config.candidateTimeout))
    }

    private mutating func markEvidence(at: Date) {
        guard case var .candidate(c) = state.phase else { return }
        c.hasDrivingEvidence = true
        c.lastEvidenceAt = at
        state.phase = .candidate(c)
    }

    private mutating func handleFix(_ fix: LocationFix, effects: inout [DetectionEffect]) {
        switch state.phase {
        case .idle:
            break

        case var .candidate(c):
            c.fixes.append(fix)
            if fix.hasValidSpeed, fix.speed > config.drivingSpeed {
                c.fastFixes += 1
                if c.fastFixes >= config.fastFixesNeeded {
                    c.hasDrivingEvidence = true
                    c.lastEvidenceAt = fix.timestamp
                }
            } else {
                c.fastFixes = 0
            }
            state.phase = .candidate(c)
            promoteCandidateIfReady(effects: &effects)

        case var .driving(trip):
            append(fix, to: &trip)
            if isStopped(fix) {
                state.phase = .stopping(trip, since: fix.timestamp)
                effects.append(.scheduleTimer(.stopTimeout, at: fix.timestamp + config.stopTimeout))
            } else {
                state.phase = .driving(trip)
            }

        case .stopping(var trip, let since):
            append(fix, to: &trip)
            if isMovingAgain(fix) {
                state.phase = .driving(trip)
                effects.append(.cancelTimer(.stopTimeout))
            } else if fix.timestamp.timeIntervalSince(since) >= config.stopTimeout {
                // Timers may not fire while suspended; a late fix ends the trip just as well.
                finish(trip, endedAt: since, effects: &effects)
            } else {
                state.phase = .stopping(trip, since: since)
            }
        }
    }

    private mutating func handleMotion(_ samples: [MotionSample], effects: inout [DetectionEffect]) {
        guard let driving = samples.last(where: { $0.isConfidentDriving }) else {
            // Not driving any more: let a slow fix move Driving to Stopping.
            return
        }
        switch state.phase {
        case .candidate:
            markEvidence(at: driving.startDate)
            promoteCandidateIfReady(effects: &effects)
        case let .stopping(trip, _):
            if let last = samples.last, last.isConfidentDriving {
                state.phase = .driving(trip)
                effects.append(.cancelTimer(.stopTimeout))
            }
        default:
            break
        }
    }

    private mutating func promoteCandidateIfReady(effects: inout [DetectionEffect]) {
        guard case let .candidate(c) = state.phase, c.hasDrivingEvidence, let latest = c.fixes.last else { return }
        let anchor = state.lastStop ?? c.fixes[0].coordinate
        guard anchor.distance(to: latest.coordinate) >= config.minimumDisplacement else { return }

        var trip = DetectorState.TripInProgress(startedAt: c.since, startCoordinate: anchor, startedBy: c.reason,
                                                points: [], measuredMetres: 0, gaps: [])
        for fix in c.fixes { append(fix, to: &trip) }
        state.phase = .driving(trip)
        effects.append(.cancelTimer(.candidateTimeout))
    }

    private mutating func handleTimer(_ id: TimerID, at: Date, effects: inout [DetectionEffect]) {
        switch (id, state.phase) {
        case let (.candidateTimeout, .candidate(c)):
            if at.timeIntervalSince(c.lastEvidenceAt) >= config.candidateTimeout || !c.hasDrivingEvidence {
                abandonCandidate(effects: &effects)
            } else {
                effects.append(.scheduleTimer(.candidateTimeout, at: c.lastEvidenceAt + config.candidateTimeout))
            }
        case let (.stopTimeout, .stopping(trip, since)):
            if at.timeIntervalSince(since) >= config.stopTimeout {
                finish(trip, endedAt: since, effects: &effects)
            }
        default:
            break // stale timer
        }
    }

    private mutating func abandonCandidate(effects: inout [DetectionEffect]) {
        state.phase = .idle
        effects.append(.stopLive)
    }

    private mutating func finish(_ trip: DetectorState.TripInProgress, endedAt: Date,
                                 effects: inout [DetectionEffect]) {
        let end = trip.points.last?.coordinate ?? trip.startCoordinate
        state.phase = .idle
        state.lastStop = end
        effects.append(.cancelTimer(.stopTimeout))
        effects.append(.stopLive)
        effects.append(.setStopRegion(centre: end, radiusMetres: config.stopRegionRadius))

        guard let first = trip.points.first else { return }
        let segment = TripSegment(startedAt: trip.startedAt, endedAt: endedAt, startCoordinate: trip.startCoordinate,
                                  endCoordinate: end, firstFixCoordinate: first.coordinate,
                                  measuredMetres: trip.measuredMetres, gaps: trip.gaps, points: trip.points,
                                  startedBy: trip.startedBy, detectorVersion: Self.version)
        let roughTotal = segment.measuredMetres + trip.startCoordinate.distance(to: first.coordinate)
            + trip.gaps.reduce(0) { $0 + $1.from.distance(to: $1.to) }
        if roughTotal >= config.minimumTripMetres {
            effects.append(.emitTrip(segment))
        }
    }

    // MARK: - Helpers

    /// Persist on every phase change, a new last stop, and every 30th trip point. That's
    /// enough to resume after a relaunch without writing once a second while driving.
    private func shouldPersist(before: DetectorState) -> Bool {
        guard state != before else { return false }
        if state.phase.kind != before.phase.kind || state.lastStop != before.lastStop { return true }
        switch state.phase {
        case let .driving(t), let .stopping(t, _): return t.points.count % 30 == 0
        case let .candidate(c): return c.fixes.count <= 1
        case .idle: return true
        }
    }

    private func append(_ fix: LocationFix, to trip: inout DetectorState.TripInProgress) {
        if let previous = trip.points.last {
            let gap = fix.timestamp.timeIntervalSince(previous.timestamp)
            if gap <= config.straightLineGapLimit {
                trip.measuredMetres += previous.coordinate.distance(to: fix.coordinate)
            } else {
                trip.gaps.append(DistanceGap(from: previous.coordinate, to: fix.coordinate,
                                             start: previous.timestamp, end: fix.timestamp))
            }
        }
        trip.points.append(fix)
    }

    private func isStopped(_ fix: LocationFix) -> Bool {
        guard fix.hasValidSpeed, fix.speed < config.stoppedSpeed else { return false }
        // Automotive + stationary (lights, traffic) still counts as driving.
        if let motion = state.lastMotion, motion.kinds.contains(.automotive), motion.confidence >= .medium {
            return false
        }
        return true
    }

    private func isMovingAgain(_ fix: LocationFix) -> Bool {
        fix.hasValidSpeed && fix.speed > config.drivingSpeed
    }
}

extension DetectorState.Phase {
    enum Kind { case idle, candidate, driving, stopping }

    var kind: Kind {
        switch self {
        case .idle: return .idle
        case .candidate: return .candidate
        case .driving: return .driving
        case .stopping: return .stopping
        }
    }
}
