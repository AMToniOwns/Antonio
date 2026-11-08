import Foundation

/// A stretch of a trip with no usable fixes for longer than the straight-line limit. The
/// platform layer estimates its road distance (e.g. with `MKDirections`) and marks the trip
/// as estimated.
public struct DistanceGap: Hashable, Codable, Sendable {
    public var from: Coordinate
    public var to: Coordinate
    public var start: Date
    public var end: Date

    public init(from: Coordinate, to: Coordinate, start: Date, end: Date) {
        self.from = from
        self.to = to
        self.start = start
        self.end = end
    }
}

/// A finished drive, ready to be stored as an unconfirmed journey.
public struct TripSegment: Hashable, Codable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    /// UK local date of `startedAt` (`YYYY-MM-DD`): the date the rate engine uses.
    public var startDateLocal: String
    /// Where the trip is taken to have begun: a recent nearby last stop, else the first fix.
    public var startCoordinate: Coordinate
    /// True when the real start is unknown: no usable last stop, so the drive probably began
    /// before the first fix (SLC wakes several hundred metres in).
    public var startIsUncertain: Bool
    public var endCoordinate: Coordinate
    /// The first accepted live fix. The stretch from `startCoordinate` to here was driven
    /// before live tracking began; the platform layer estimates it (Phase 0 §3.3).
    public var firstFixCoordinate: Coordinate
    /// Metres measured from accepted fixes, including straight-line joins of short gaps.
    public var measuredMetres: Double
    /// Gaps the platform layer must estimate; empty for a fully measured trip.
    public var gaps: [DistanceGap]
    /// Stops inside the trip that didn't end it (drop-offs shorter than the stop timer).
    public var stops: [DateInterval]
    public var points: [LocationFix]
    public var startedBy: WakeReason
    public var detectorVersion: String
    /// The thresholds the trip was detected with, for comparing tunings in the test run.
    public var config: DetectorConfig

    public init(startedAt: Date, endedAt: Date, startDateLocal: String, startCoordinate: Coordinate,
                startIsUncertain: Bool, endCoordinate: Coordinate, firstFixCoordinate: Coordinate,
                measuredMetres: Double, gaps: [DistanceGap], stops: [DateInterval], points: [LocationFix],
                startedBy: WakeReason, detectorVersion: String, config: DetectorConfig) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startDateLocal = startDateLocal
        self.startCoordinate = startCoordinate
        self.startIsUncertain = startIsUncertain
        self.endCoordinate = endCoordinate
        self.firstFixCoordinate = firstFixCoordinate
        self.measuredMetres = measuredMetres
        self.gaps = gaps
        self.stops = stops
        self.points = points
        self.startedBy = startedBy
        self.detectorVersion = detectorVersion
        self.config = config
    }

    /// True when some of the distance has to be estimated rather than measured.
    public var needsEstimate: Bool {
        !gaps.isEmpty || startIsUncertain || startCoordinate != firstFixCoordinate
    }
}

public enum Notice: String, Codable, Sendable {
    case permissionDowngraded, preciseLocationOff, locationDenied
}

/// Why the detector did something unremarkable-looking. Written to the tracking log so the
/// debug timeline (council D8) and the test-run analysis can explain every decision.
public enum Diagnostic: Hashable, Codable, Sendable {
    case fixRejected(FixRejection)
    case candidateAbandoned(evidence: Bool)
    case candidateExpired
    case tripTooShort(metres: Double)
    case tripSplitAfterSilence(seconds: Double)
    case staleTripClosedOnRelaunch(seconds: Double)
    case stoppingFromMotion
    case resumedFromStop(seconds: Double)
    case visitIgnored
    case lastStopIgnored(ageSeconds: Double, metres: Double)
    case trafficHold
}

public enum FixRejection: String, Codable, Sendable {
    case inaccurate, stale, outOfOrder, impliedSpeed
}

/// Everything the detector asks the platform layer to do.
public enum DetectionEffect: Hashable, Codable, Sendable {
    case startLive
    case stopLive
    /// Query Core Motion history from this date until now; reply with `.motionHistory`.
    case queryMotionHistory(from: Date)
    /// Run `RecoveryPlanner` over the last 7 days of motion history (every launch and wake).
    case runRecovery
    case setStopRegion(centre: Coordinate, radiusMetres: Double)
    /// Schedule `id` for `at`; a time in the past means "as soon as possible". Rescheduling
    /// an id replaces the earlier one.
    case scheduleTimer(TimerID, at: Date)
    case cancelTimer(TimerID)
    /// Save the state so a relaunch can restore it before anything else happens.
    case persist(DetectorState)
    case emitTrip(TripSegment)
    case notify(Notice)
    case log(Diagnostic)
}
