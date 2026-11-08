import Foundation

/// A stretch of a trip with no usable fixes for longer than the straight-line limit. The
/// platform layer estimates its road distance (e.g. with `MKDirections`) and marks the trip
/// as estimated.
public struct DistanceGap: Hashable, Codable, Sendable {
    public var from: Coordinate
    public var to: Coordinate
    public var start: Date
    public var end: Date
}

/// A finished drive, ready to be stored as an unconfirmed journey.
public struct TripSegment: Hashable, Codable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    /// Where the trip is taken to have begun: the last stop if known, else the first fix.
    public var startCoordinate: Coordinate
    public var endCoordinate: Coordinate
    /// The first accepted live fix. The stretch from `startCoordinate` to here was driven
    /// before live tracking began; the platform layer estimates it (§3.3 "Start point").
    public var firstFixCoordinate: Coordinate
    /// Metres measured from accepted fixes, including straight-line joins of short gaps.
    public var measuredMetres: Double
    /// Gaps the platform layer must estimate; empty for a fully measured trip.
    public var gaps: [DistanceGap]
    public var points: [LocationFix]
    public var startedBy: WakeReason
    public var detectorVersion: String

    /// True when some of the distance has to be estimated rather than measured.
    public var needsEstimate: Bool { !gaps.isEmpty || startCoordinate != firstFixCoordinate }
}

public enum Notice: String, Codable, Sendable {
    case permissionDowngraded, preciseLocationOff, locationDenied
}

/// Everything the detector asks the platform layer to do.
public enum DetectionEffect: Hashable, Codable, Sendable {
    case startLive
    case stopLive
    /// Query Core Motion history from this date until now; reply with `.motionHistory`.
    case queryMotionHistory(from: Date)
    case setStopRegion(centre: Coordinate, radiusMetres: Double)
    case scheduleTimer(TimerID, at: Date)
    case cancelTimer(TimerID)
    /// Save the state so a relaunch can restore it before anything else happens.
    case persist(DetectorState)
    case emitTrip(TripSegment)
    case notify(Notice)
}
