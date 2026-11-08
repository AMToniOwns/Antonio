import Foundation

/// Tunable thresholds. Defaults are the Phase 0 values (§3.3); the test run tunes them.
public struct DetectorConfig: Hashable, Codable, Sendable {
    /// A candidate with no driving evidence is dropped after this long.
    public var candidateTimeout: TimeInterval = 120
    /// A candidate is dropped after this long even with evidence (stuck in a car park with the
    /// engine running), so GPS can't stay on indefinitely. Assisted candidates are exempt.
    public var maxCandidateDuration: TimeInterval = 600
    /// Stopped this long ends the trip (3–5 min in Phase 0).
    public var stopTimeout: TimeInterval = 240
    /// Fixes faster than this count as driving evidence and resume a stopped trip.
    public var drivingSpeed: Double = 6           // m/s, ~13 mph
    /// Fixes slower than this count as stopped.
    public var stoppedSpeed: Double = 2           // m/s, ~4.5 mph
    /// Consecutive fast fixes needed as driving evidence on their own.
    public var fastFixesNeeded = 3
    /// A candidate must move this far from where it started before it becomes a trip.
    public var minimumDisplacement: Double = 300  // metres
    public var maxHorizontalAccuracy: Double = 65
    /// Fixes older than this when delivered are dropped (stale cached locations).
    public var maxFixAge: TimeInterval = 10
    /// A fix implying a faster jump than this from the last accepted fix is dropped...
    public var maxImpliedSpeed: Double = 70       // m/s
    /// ...unless this many in a row are, in which case the last accepted fix was the outlier.
    public var maxConsecutiveJumpRejections = 3
    /// Gaps up to this long are joined in a straight line; longer ones are left for estimation.
    public var straightLineGapLimit: TimeInterval = 120
    /// No fixes for this long while Driving means the phone was parked (or killed): the next
    /// fix starts a new trip instead of joining this one.
    public var maxResumeGap: TimeInterval = 600
    /// "Automotive + stationary" keeps a trip alive in traffic, but not for longer than this.
    public var maxTrafficHold: TimeInterval = 1200
    /// Derive speed from consecutive fixes when the OS reports none, if they're this close.
    public var derivedSpeedWindow: TimeInterval = 30
    /// A last stop older or further from the first fix than this isn't used as the start.
    public var maxLastStopAge: TimeInterval = 12 * 3600
    public var maxLastStopDistance: Double = 3000
    /// An arrival visit ends a trip only if it's this close to the latest position.
    public var visitMatchRadius: Double = 250
    /// Motion samples older than this (by delivery) don't override fix speeds.
    public var motionFreshness: TimeInterval = 300
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

    public struct Stop: Hashable, Codable, Sendable {
        public var coordinate: Coordinate
        public var at: Date

        public init(coordinate: Coordinate, at: Date) {
            self.coordinate = coordinate
            self.at = at
        }
    }

    public struct Candidate: Hashable, Codable, Sendable {
        public var since: Date
        public var reason: WakeReason
        /// Started by the user's Shortcuts automation: no timeout, ends on `assistedStop`.
        public var assisted: Bool
        public var hasDrivingEvidence: Bool
        /// When evidence was last *received* (not when the motion it describes began).
        public var lastEvidenceAt: Date
        public var fastFixes: Int
        public var fixes: [LocationFix]
        /// Best guess at when the drive really began (motion history, visit departure).
        public var startHint: Date?
    }

    public struct TripInProgress: Hashable, Codable, Sendable {
        public var startedAt: Date
        public var startCoordinate: Coordinate
        public var startIsUncertain: Bool
        public var startedBy: WakeReason
        public var points: [LocationFix]
        /// Start of the current run of slow fixes, for the traffic-hold limit.
        public var slowSince: Date?
        /// Stops inside the trip that ended by driving off again.
        public var stops: [DateInterval]

        var lastPointTime: Date { points.last?.timestamp ?? startedAt }
    }

    public var phase: Phase = .idle
    public var lastStop: Stop?
    /// The latest motion sample and when it was delivered.
    public var lastMotion: MotionSample?
    public var lastMotionReceivedAt: Date?
    var jumpRejections = 0

    public init() {}
}

/// The trip state machine (Phase 0 §3.3). Pure: events in, effects out, no clocks and no
/// Core Location. Feed it every event in delivery order and carry out the effects it returns
/// (see docs/phase1/adapter-contract.md).
public struct TripDetector: Sendable {
    public static let version = "td-0.2.0"

    public private(set) var state: DetectorState
    public let config: DetectorConfig

    public init(state: DetectorState = DetectorState(), config: DetectorConfig = DetectorConfig()) {
        self.state = state
        self.config = config
    }

    /// Feeds `events` in order and returns every effect, for replaying recorded traces.
    public static func replay(_ events: [DetectionEvent], from state: DetectorState = DetectorState(),
                              config: DetectorConfig = DetectorConfig()) -> (effects: [DetectionEffect], state: DetectorState) {
        var detector = TripDetector(state: state, config: config)
        let effects = events.flatMap { detector.handle($0) }
        return (effects, detector.state)
    }

    public mutating func handle(_ event: DetectionEvent) -> [DetectionEffect] {
        var effects: [DetectionEffect] = []
        let before = state

        switch event {
        case let .wake(reason, at):
            effects.append(.runRecovery)
            if case .idle = state.phase {
                startCandidate(reason: reason, at: at, assisted: reason == .assisted, effects: &effects)
            }

        case let .relaunched(at):
            handleRelaunch(at: at, effects: &effects)

        case let .fix(fix, receivedAt):
            if let reason = rejection(for: fix, receivedAt: receivedAt) {
                effects.append(.log(.fixRejected(reason)))
            } else {
                handleFix(fix, effects: &effects)
            }

        case let .motion(sample, receivedAt):
            state.lastMotion = sample
            state.lastMotionReceivedAt = receivedAt
            handleMotion(sample, receivedAt: receivedAt, effects: &effects)

        case let .motionHistory(samples, receivedAt):
            guard let latest = samples.last else { break }
            state.lastMotion = latest
            state.lastMotionReceivedAt = receivedAt
            // Only a drive that's still happening counts; older drives are recovery's job.
            if latest.isConfidentDriving, case var .candidate(c) = state.phase {
                c.hasDrivingEvidence = true
                c.lastEvidenceAt = receivedAt
                c.startHint = earliest(c.startHint, Self.runStart(endingWith: samples))
                state.phase = .candidate(c)
                promoteCandidateIfReady(effects: &effects)
            }

        case let .visit(visit, receivedAt):
            handleVisit(visit, receivedAt: receivedAt, effects: &effects)

        case let .timerFired(id, at):
            handleTimer(id, at: at, effects: &effects)

        case let .authorizationChanged(auth, precise, at):
            switch auth {
            case .always, .notDetermined: break
            case .whenInUse: effects.append(.notify(.permissionDowngraded))
            case .denied:
                effects.append(.notify(.locationDenied))
                closeEverything(at: at, effects: &effects)
            }
            if !precise { effects.append(.notify(.preciseLocationOff)) }

        case let .assistedStart(at):
            switch state.phase {
            case .idle:
                startCandidate(reason: .assisted, at: at, assisted: true, effects: &effects)
            case var .candidate(c):
                c.assisted = true
                c.hasDrivingEvidence = true
                c.lastEvidenceAt = at
                state.phase = .candidate(c)
                effects.append(.cancelTimer(.candidateTimeout))
                promoteCandidateIfReady(effects: &effects)
            case .driving, .stopping:
                break
            }

        case let .assistedStop(at):
            closeEverything(at: at, effects: &effects)
        }

        if shouldPersist(before: before) { effects.append(.persist(state)) }
        return effects
    }

    // MARK: - Relaunch

    private mutating func handleRelaunch(at: Date, effects: inout [DetectionEffect]) {
        switch state.phase {
        case .idle:
            break // Opening the app isn't a drive; `.wake` follows if a location event caused it.

        case let .candidate(c):
            if c.assisted || at.timeIntervalSince(c.since) < config.maxCandidateDuration {
                effects.append(.startLive)
                effects.append(.queryMotionHistory(from: at - config.motionHistoryWindow))
                if !c.assisted {
                    let due = max(c.since, c.lastEvidenceAt) + config.candidateTimeout
                    effects.append(.scheduleTimer(.candidateTimeout, at: due))
                }
            } else {
                abandonCandidate(effects: &effects)
            }

        case let .driving(trip):
            let silence = at.timeIntervalSince(trip.lastPointTime)
            if silence > config.maxResumeGap {
                effects.append(.log(.staleTripClosedOnRelaunch(seconds: silence)))
                finish(trip, endedAt: trip.lastPointTime, trimAfter: nil, effects: &effects)
            } else {
                // Restore live tracking first: the session must be recreated straight after relaunch.
                effects.append(.startLive)
                effects.append(.scheduleTimer(.silenceWatchdog, at: trip.lastPointTime + config.stopTimeout))
            }

        case let .stopping(trip, since):
            if at.timeIntervalSince(since) >= config.stopTimeout {
                effects.append(.log(.staleTripClosedOnRelaunch(seconds: at.timeIntervalSince(since))))
                finish(trip, endedAt: since, trimAfter: since, effects: &effects)
            } else {
                effects.append(.startLive)
                effects.append(.scheduleTimer(.stopTimeout, at: since + config.stopTimeout))
            }
        }
        effects.append(.runRecovery)
    }

    // MARK: - Fixes

    private mutating func rejection(for fix: LocationFix, receivedAt: Date) -> FixRejection? {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= config.maxHorizontalAccuracy else { return .inaccurate }
        guard receivedAt.timeIntervalSince(fix.timestamp) <= config.maxFixAge else { return .stale }
        guard let previous = lastAcceptedFix else { return nil }
        let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return .outOfOrder }
        if previous.coordinate.distance(to: fix.coordinate) / dt > config.maxImpliedSpeed {
            state.jumpRejections += 1
            if state.jumpRejections < config.maxConsecutiveJumpRejections { return .impliedSpeed }
            // Several "impossible" jumps in a row mean the last accepted fix was the outlier:
            // drop it, so it adds no distance, and take this one.
            dropLastAcceptedFix()
        }
        state.jumpRejections = 0
        return nil
    }

    private mutating func dropLastAcceptedFix() {
        switch state.phase {
        case .idle: break
        case var .candidate(c):
            if !c.fixes.isEmpty { c.fixes.removeLast() }
            state.phase = .candidate(c)
        case var .driving(t):
            if t.points.count > 1 { t.points.removeLast() }
            state.phase = .driving(t)
        case .stopping(var t, let since):
            if t.points.count > 1 { t.points.removeLast() }
            state.phase = .stopping(t, since: since)
        }
    }

    private var lastAcceptedFix: LocationFix? {
        switch state.phase {
        case .idle: return nil
        case let .candidate(c): return c.fixes.last
        case let .driving(t), let .stopping(t, _): return t.points.last
        }
    }

    private mutating func handleFix(_ fix: LocationFix, effects: inout [DetectionEffect]) {
        switch state.phase {
        case .idle:
            break

        case var .candidate(c):
            let speed = effectiveSpeed(of: fix, after: c.fixes.last)
            c.fixes.append(fix)
            if let speed, speed > config.drivingSpeed {
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
            let silence = fix.timestamp.timeIntervalSince(trip.lastPointTime)
            if silence > config.maxResumeGap {
                // Parked (or killed) and now moving again: that was the end of one trip, and
                // this fix may be the start of another.
                effects.append(.log(.tripSplitAfterSilence(seconds: silence)))
                finish(trip, endedAt: trip.lastPointTime, trimAfter: nil, effects: &effects)
                startCandidate(reason: .significantLocationChange, at: fix.timestamp, assisted: false, effects: &effects)
                handleFix(fix, effects: &effects)
                return
            }
            let speed = effectiveSpeed(of: fix, after: trip.points.last)
            trip.points.append(fix)
            if let speed, speed < config.stoppedSpeed {
                if trip.slowSince == nil { trip.slowSince = fix.timestamp }
                if inTrafficHold(trip, at: fix.timestamp) {
                    state.phase = .driving(trip)
                } else {
                    state.phase = .stopping(trip, since: trip.slowSince ?? fix.timestamp)
                    effects.append(.scheduleTimer(.stopTimeout, at: (trip.slowSince ?? fix.timestamp) + config.stopTimeout))
                }
            } else {
                if let speed, speed >= config.stoppedSpeed { trip.slowSince = nil }
                state.phase = .driving(trip)
            }

        case .stopping(var trip, let since):
            // Check the clock first: if the stop timer never fired, this fix is the next drive.
            if fix.timestamp.timeIntervalSince(since) >= config.stopTimeout {
                finish(trip, endedAt: since, trimAfter: since, effects: &effects)
                if let speed = effectiveSpeed(of: fix, after: nil), speed > config.drivingSpeed {
                    startCandidate(reason: .significantLocationChange, at: fix.timestamp, assisted: false, effects: &effects)
                    handleFix(fix, effects: &effects)
                }
                return
            }
            let speed = effectiveSpeed(of: fix, after: trip.points.last)
            trip.points.append(fix)
            if let speed, resumes(at: speed, at: fix.timestamp) {
                resume(&trip, stoppedSince: since, at: fix.timestamp, effects: &effects)
            } else {
                state.phase = .stopping(trip, since: since)
            }
        }
    }

    /// The fix's own speed if the OS reported one, else distance over time from the previous fix.
    private func effectiveSpeed(of fix: LocationFix, after previous: LocationFix?) -> Double? {
        if fix.hasValidSpeed { return fix.speed }
        guard let previous else { return nil }
        let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0, dt <= config.derivedSpeedWindow else { return nil }
        return previous.coordinate.distance(to: fix.coordinate) / dt
    }

    // MARK: - Motion

    private mutating func handleMotion(_ sample: MotionSample, receivedAt: Date, effects: inout [DetectionEffect]) {
        switch state.phase {
        case var .candidate(c):
            guard sample.isConfidentDriving else { return }
            c.hasDrivingEvidence = true
            c.lastEvidenceAt = receivedAt
            state.phase = .candidate(c)
            promoteCandidateIfReady(effects: &effects)

        case let .driving(trip):
            // Out of the car with no further fixes (distance filter): start the stop timer now.
            guard !sample.kinds.contains(.automotive), sample.confidence >= .medium,
                  sample.kinds.isDisjoint(with: [.unknown]) else { return }
            let since = min(receivedAt, max(trip.lastPointTime, sample.startDate))
            state.phase = .stopping(trip, since: since)
            effects.append(.log(.stoppingFromMotion))
            effects.append(.scheduleTimer(.stopTimeout, at: since + config.stopTimeout))

        case .stopping(var trip, let since):
            guard sample.isConfidentDriving, !sample.kinds.contains(.stationary) else { return }
            resume(&trip, stoppedSince: since, at: receivedAt, effects: &effects)

        case .idle:
            break
        }
    }

    // MARK: - Visits

    private mutating func handleVisit(_ visit: Visit, receivedAt: Date, effects: inout [DetectionEffect]) {
        switch state.phase {
        case let .driving(trip), let .stopping(trip, _):
            // Only an arrival here, after this trip began, ends it; visits are often late.
            guard visit.departure == nil, let arrival = visit.arrival, arrival >= trip.startedAt,
                  let last = trip.points.last,
                  last.coordinate.distance(to: visit.coordinate) <= config.visitMatchRadius else {
                effects.append(.log(.visitIgnored))
                return
            }
            if case let .stopping(_, since) = state.phase {
                finish(trip, endedAt: since, trimAfter: since, effects: &effects)
            } else {
                finish(trip, endedAt: max(trip.startedAt, min(arrival, last.timestamp)), trimAfter: nil, effects: &effects)
            }

        case .idle, .candidate:
            let at = visit.departure ?? visit.arrival ?? receivedAt
            if state.lastStop.map({ at >= $0.at }) ?? true {
                state.lastStop = .init(coordinate: visit.coordinate, at: at)
            }
            if let departure = visit.departure, case var .candidate(c) = state.phase,
               departure <= c.since, c.since.timeIntervalSince(departure) <= config.maxCandidateDuration {
                c.startHint = earliest(c.startHint, departure)
                state.phase = .candidate(c)
            }
        }
    }

    // MARK: - Timers

    private mutating func handleTimer(_ id: TimerID, at: Date, effects: inout [DetectionEffect]) {
        switch (id, state.phase) {
        case (.candidateTimeout, .candidate(var c)):
            guard !c.assisted else { return }
            if at.timeIntervalSince(c.since) >= config.maxCandidateDuration {
                effects.append(.log(.candidateExpired))
                abandonCandidate(effects: &effects)
                return
            }
            // Core Motion only reports changes: if it still says automotive, evidence is current.
            if let motion = state.lastMotion, motion.isConfidentDriving, c.hasDrivingEvidence {
                c.lastEvidenceAt = at
                state.phase = .candidate(c)
            }
            let reference = c.hasDrivingEvidence ? c.lastEvidenceAt : c.since
            if at.timeIntervalSince(reference) >= config.candidateTimeout {
                effects.append(.log(.candidateAbandoned(evidence: c.hasDrivingEvidence)))
                abandonCandidate(effects: &effects)
            } else {
                effects.append(.scheduleTimer(.candidateTimeout, at: reference + config.candidateTimeout))
            }

        case let (.stopTimeout, .stopping(trip, since)):
            if at.timeIntervalSince(since) >= config.stopTimeout {
                finish(trip, endedAt: since, trimAfter: since, effects: &effects)
            } else {
                effects.append(.scheduleTimer(.stopTimeout, at: since + config.stopTimeout))
            }

        case let (.silenceWatchdog, .driving(trip)):
            let silence = at.timeIntervalSince(trip.lastPointTime)
            if silence < config.stopTimeout {
                effects.append(.scheduleTimer(.silenceWatchdog, at: trip.lastPointTime + config.stopTimeout))
            } else if inTrafficHold(trip, at: at) {
                effects.append(.log(.trafficHold))
                effects.append(.scheduleTimer(.silenceWatchdog, at: at + config.stopTimeout))
            } else {
                finish(trip, endedAt: trip.lastPointTime, trimAfter: nil, effects: &effects)
            }

        default:
            break // stale timer
        }
    }

    // MARK: - Transitions

    private mutating func startCandidate(reason: WakeReason, at: Date, assisted: Bool, effects: inout [DetectionEffect]) {
        state.phase = .candidate(.init(since: at, reason: reason, assisted: assisted, hasDrivingEvidence: assisted,
                                       lastEvidenceAt: at, fastFixes: 0, fixes: [], startHint: nil))
        effects.append(.startLive)
        effects.append(.queryMotionHistory(from: at - config.motionHistoryWindow))
        if !assisted {
            effects.append(.scheduleTimer(.candidateTimeout, at: at + config.candidateTimeout))
        }
    }

    private mutating func promoteCandidateIfReady(effects: inout [DetectionEffect]) {
        guard case let .candidate(c) = state.phase, c.hasDrivingEvidence,
              let first = c.fixes.first, let latest = c.fixes.last else { return }

        var anchor = first.coordinate
        var uncertain = !c.assisted // assisted starts at the car; SLC wakes are hundreds of metres in
        var ignoredStop: Diagnostic?
        if let stop = state.lastStop {
            let age = first.timestamp.timeIntervalSince(stop.at)
            let distance = stop.coordinate.distance(to: first.coordinate)
            if age <= config.maxLastStopAge, distance <= config.maxLastStopDistance {
                anchor = stop.coordinate
                uncertain = false
            } else {
                ignoredStop = .lastStopIgnored(ageSeconds: age, metres: distance)
            }
        }
        guard anchor.distance(to: latest.coordinate) >= config.minimumDisplacement else { return }
        if let ignoredStop { effects.append(.log(ignoredStop)) }

        let trip = DetectorState.TripInProgress(startedAt: min(c.startHint ?? c.since, c.since),
                                                startCoordinate: anchor, startIsUncertain: uncertain,
                                                startedBy: c.reason, points: c.fixes, slowSince: nil, stops: [])
        state.phase = .driving(trip)
        effects.append(.cancelTimer(.candidateTimeout))
        effects.append(.scheduleTimer(.silenceWatchdog, at: latest.timestamp + config.stopTimeout))
    }

    private mutating func resume(_ trip: inout DetectorState.TripInProgress, stoppedSince: Date, at: Date,
                                 effects: inout [DetectionEffect]) {
        trip.stops.append(DateInterval(start: stoppedSince, end: max(stoppedSince, at)))
        trip.slowSince = nil
        state.phase = .driving(trip)
        effects.append(.log(.resumedFromStop(seconds: at.timeIntervalSince(stoppedSince))))
        effects.append(.cancelTimer(.stopTimeout))
        effects.append(.scheduleTimer(.silenceWatchdog, at: trip.lastPointTime + config.stopTimeout))
    }

    private mutating func abandonCandidate(effects: inout [DetectionEffect]) {
        state.phase = .idle
        effects.append(.cancelTimer(.candidateTimeout))
        effects.append(.stopLive)
    }

    /// Ends whatever is in progress (assisted stop, permission denied).
    private mutating func closeEverything(at: Date, effects: inout [DetectionEffect]) {
        switch state.phase {
        case let .driving(trip): finish(trip, endedAt: max(trip.startedAt, min(at, trip.lastPointTime)), trimAfter: nil, effects: &effects)
        case let .stopping(trip, since): finish(trip, endedAt: since, trimAfter: since, effects: &effects)
        case .candidate: abandonCandidate(effects: &effects)
        case .idle: break
        }
    }

    /// Emits the trip. With `trimAfter`, points after that moment (walking away from the car,
    /// a late fix) are dropped so they don't add distance or move the end point.
    private mutating func finish(_ trip: DetectorState.TripInProgress, endedAt: Date, trimAfter: Date?,
                                 effects: inout [DetectionEffect]) {
        var points = trip.points
        if let trimAfter {
            let kept = points.filter { $0.timestamp <= trimAfter }
            points = kept.isEmpty ? Array(points.prefix(1)) : kept
        }
        let end = points.last?.coordinate ?? trip.startCoordinate
        let ended = max(trip.startedAt, endedAt)
        state.phase = .idle
        state.lastStop = .init(coordinate: end, at: ended)
        effects.append(.cancelTimer(.stopTimeout))
        effects.append(.cancelTimer(.silenceWatchdog))
        effects.append(.stopLive)
        effects.append(.setStopRegion(centre: end, radiusMetres: config.stopRegionRadius))

        guard let first = points.first else { return }
        let (measured, gaps) = measure(points)
        let segment = TripSegment(startedAt: trip.startedAt, endedAt: ended,
                                  startDateLocal: LocalDate.string(for: trip.startedAt),
                                  startCoordinate: trip.startCoordinate, startIsUncertain: trip.startIsUncertain,
                                  endCoordinate: end, firstFixCoordinate: first.coordinate,
                                  measuredMetres: measured, gaps: gaps,
                                  stops: trip.stops.filter { $0.end <= ended }, points: points,
                                  startedBy: trip.startedBy, detectorVersion: Self.version, config: config)
        // The 0.3-mile minimum is judged on the best estimate of the whole drive: what was
        // measured, plus straight lines for the lead-in and any gaps (a lower bound on the road
        // distance), so a trip isn't dropped just because part of it couldn't be measured.
        let roughTotal = measured + trip.startCoordinate.distance(to: first.coordinate)
            + gaps.reduce(0) { $0 + $1.from.distance(to: $1.to) }
        if roughTotal >= config.minimumTripMetres {
            effects.append(.emitTrip(segment))
        } else {
            effects.append(.log(.tripTooShort(metres: roughTotal)))
        }
    }

    // MARK: - Helpers

    /// Measured distance from consecutive points, and the gaps too long to join.
    private func measure(_ points: [LocationFix]) -> (Double, [DistanceGap]) {
        var metres = 0.0
        var gaps: [DistanceGap] = []
        for (previous, fix) in zip(points, points.dropFirst()) {
            if fix.timestamp.timeIntervalSince(previous.timestamp) <= config.straightLineGapLimit {
                metres += previous.coordinate.distance(to: fix.coordinate)
            } else {
                gaps.append(DistanceGap(from: previous.coordinate, to: fix.coordinate,
                                        start: previous.timestamp, end: fix.timestamp))
            }
        }
        return (metres, gaps)
    }

    /// Automotive + stationary (lights, a jam) keeps the trip going, for up to `maxTrafficHold`.
    private func inTrafficHold(_ trip: DetectorState.TripInProgress, at: Date) -> Bool {
        guard let motion = state.lastMotion, motion.isConfidentDriving else { return false }
        return at.timeIntervalSince(trip.slowSince ?? trip.lastPointTime) < config.maxTrafficHold
    }

    /// Whether a fix while stopped means the drive carried on. Crawling counts, unless Core
    /// Motion recently said the user is on foot or on a bike.
    private func resumes(at speed: Double, at time: Date) -> Bool {
        if speed > config.drivingSpeed { return true }
        guard speed >= config.stoppedSpeed else { return false }
        if let motion = state.lastMotion, let received = state.lastMotionReceivedAt,
           time.timeIntervalSince(received) <= config.motionFreshness,
           !motion.kinds.isDisjoint(with: [.walking, .running, .cycling]) {
            return false
        }
        return true
    }

    /// Start of the confident-automotive run at the end of `samples` (oldest first).
    static func runStart(endingWith samples: [MotionSample]) -> Date? {
        var start: Date?
        for sample in samples.reversed() {
            guard sample.isConfidentDriving else { break }
            start = sample.startDate
        }
        return start
    }

    private func earliest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): return min(a, b)
        default: return a ?? b
        }
    }

    /// Persist on every phase change, a new last stop, and every 30th trip point: enough to
    /// resume after a relaunch without writing once a second while driving.
    private func shouldPersist(before: DetectorState) -> Bool {
        guard state != before else { return false }
        if state.phase.kind != before.phase.kind || state.lastStop != before.lastStop { return true }
        switch state.phase {
        case let .driving(t), let .stopping(t, _): return t.points.count % 30 == 0
        case let .candidate(c): return c.fixes.count <= 1
        case .idle: return true
        }
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
