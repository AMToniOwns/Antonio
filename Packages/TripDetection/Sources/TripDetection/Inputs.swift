import Foundation

/// A point on the Earth in degrees.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres (haversine, mean Earth radius).
    public func distance(to other: Coordinate) -> Double {
        let r = 6_371_008.8
        let φ1 = latitude * .pi / 180, φ2 = other.latitude * .pi / 180
        let dφ = φ2 - φ1
        let dλ = (other.longitude - longitude) * .pi / 180
        let a = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}

/// One location reading, as Core Location reports it. Negative `speed` or `speedAccuracy`
/// means the value is unknown, matching `CLLocation`.
public struct LocationFix: Hashable, Codable, Sendable {
    public var timestamp: Date
    public var coordinate: Coordinate
    public var horizontalAccuracy: Double
    public var speed: Double
    public var speedAccuracy: Double

    public init(timestamp: Date, coordinate: Coordinate, horizontalAccuracy: Double,
                speed: Double = -1, speedAccuracy: Double = -1) {
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
    }

    var hasValidSpeed: Bool { speed >= 0 && speedAccuracy >= 0 }
}

/// A Core Motion activity sample. Several kinds can be true at once (e.g. automotive and
/// stationary while waiting at lights).
public struct MotionSample: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case automotive, stationary, walking, running, cycling, unknown }
    public enum Confidence: Int, Codable, Sendable, Comparable {
        case low, medium, high
        public static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }
    }

    public var startDate: Date
    public var kinds: Set<Kind>
    public var confidence: Confidence

    public init(startDate: Date, kinds: Set<Kind>, confidence: Confidence) {
        self.startDate = startDate
        self.kinds = kinds
        self.confidence = confidence
    }

    var isConfidentDriving: Bool { kinds.contains(.automotive) && confidence >= .medium }
}

/// A Core Location visit. `departure` is nil while the phone is still there.
public struct Visit: Hashable, Codable, Sendable {
    public var coordinate: Coordinate
    public var arrival: Date?
    public var departure: Date?

    public init(coordinate: Coordinate, arrival: Date?, departure: Date?) {
        self.coordinate = coordinate
        self.arrival = arrival
        self.departure = departure
    }
}

public enum WakeReason: String, Codable, Sendable {
    case significantLocationChange, visitDeparture, regionExit, assisted, appOpened
}

public enum Authorization: String, Codable, Sendable {
    case always, whenInUse, denied, notDetermined
}

/// Everything the platform layer tells the detector. Each event carries the time it was
/// delivered, so the detector never reads a clock and replays are exact.
public enum DetectionEvent: Hashable, Codable, Sendable {
    /// The OS woke the app because the phone moved (or the user started assisted mode).
    case wake(WakeReason, at: Date)
    /// The process started (any reason) and restored its state. Send first, before any other
    /// event; send `.wake` as well if the launch was caused by a location event.
    case relaunched(at: Date)
    case fix(LocationFix, receivedAt: Date)
    case motion(MotionSample, receivedAt: Date)
    /// Result of querying motion history (oldest first), e.g. the last 5 minutes on wake.
    case motionHistory([MotionSample], receivedAt: Date)
    case visit(Visit, receivedAt: Date)
    case timerFired(TimerID, at: Date)
    case authorizationChanged(Authorization, preciseLocation: Bool, at: Date)
    case assistedStart(at: Date)
    case assistedStop(at: Date)
}

public enum TimerID: String, Codable, Sendable {
    /// Ends a candidate that never shows driving evidence.
    case candidateTimeout
    /// Ends a trip that has been stopped for `stopTimeout`.
    case stopTimeout
    /// Ends a trip when fixes stop arriving altogether: a parked phone with a distance filter
    /// sends nothing, so no "stopped" fix ever comes.
    case silenceWatchdog
}
