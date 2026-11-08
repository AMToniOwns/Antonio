import Foundation
import Testing
@testable import TripDetection

@Suite struct RecoveryTests {
    let t0 = Scenario.t0
    func sample(_ minutes: Double, _ kinds: Set<MotionSample.Kind>, _ c: MotionSample.Confidence = .high) -> MotionSample {
        MotionSample(startDate: t0 + minutes * 60, kinds: kinds, confidence: c)
    }

    @Test func uncoveredDriveIsRecovered() throws {
        let history = [sample(0, [.stationary]), sample(10, [.automotive]), sample(30, [.walking])]
        let a = Coordinate(latitude: 53.8, longitude: -1.55), b = Coordinate(latitude: 53.9, longitude: -1.5)
        let visits = [Visit(coordinate: a, arrival: t0 - 3600, departure: t0 + 9 * 60),
                      Visit(coordinate: b, arrival: t0 + 31 * 60, departure: nil)]
        let found = RecoveryPlanner.recover(history: history, knownTrips: [], visits: visits, now: t0 + 3600)
        let trip = try #require(found.first)
        #expect(found.count == 1)
        #expect(trip.start == t0 + 600)
        #expect(trip.end == t0 + 1800)
        #expect(trip.from == a)
        #expect(trip.to == b)
    }

    @Test func fullyCoveredDriveIsNotRecovered() {
        let history = [sample(10, [.automotive]), sample(30, [.walking])]
        let known = [DateInterval(start: t0 + 9 * 60, end: t0 + 31 * 60)]
        #expect(RecoveryPlanner.recover(history: history, knownTrips: known, visits: [], now: t0 + 3600).isEmpty)
    }

    @Test func onlyTheUncoveredPartIsRecovered() throws {
        let history = [sample(10, [.automotive]), sample(30, [.walking])]
        let known = [DateInterval(start: t0 + 9 * 60, end: t0 + 25 * 60)] // live tracking began late... and ended early
        let found = RecoveryPlanner.recover(history: history, knownTrips: known, visits: [], now: t0 + 3600)
        let piece = try #require(found.first)
        #expect(found.count == 1)
        #expect(piece.start == t0 + 25 * 60)
        #expect(piece.end == t0 + 30 * 60)
    }

    @Test func uncoveredSliverShorterThanTheMinimumIsDropped() {
        let history = [sample(10, [.automotive]), sample(30, [.walking])]
        let known = [DateInterval(start: t0 + 9 * 60, end: t0 + 28 * 60)] // 2 minutes left over
        #expect(RecoveryPlanner.recover(history: history, knownTrips: known, visits: [], now: t0 + 3600).isEmpty)
    }

    @Test func shortAndLowConfidenceRunsAreIgnored() {
        let history = [sample(0, [.automotive]), sample(2, [.walking]),          // 2 minutes
                       sample(10, [.automotive], .low), sample(30, [.walking])]  // low confidence
        #expect(RecoveryPlanner.recover(history: history, knownTrips: [], visits: [], now: t0 + 3600).isEmpty)
    }

    @Test func runsSplitByAJamAreOneDrive() throws {
        let history = [sample(0, [.automotive]), sample(10, [.stationary]), sample(14, [.automotive]), sample(20, [.walking])]
        let found = RecoveryPlanner.recover(history: history, knownTrips: [], visits: [], now: t0 + 3600)
        let trip = try #require(found.first)
        #expect(found.count == 1)
        #expect(trip.end == t0 + 1200)
    }

    @Test func aDriveStillInProgressIsLeftToTheLiveLayer() {
        let history = [sample(0, [.walking]), sample(50, [.automotive])]
        #expect(RecoveryPlanner.recover(history: history, knownTrips: [], visits: [], now: t0 + 3600).isEmpty)
    }

    @Test func theLeadInBeforeALiveTripIsNotRecovered() {
        // SLC woke the app 3 minutes into the drive; the trip already estimates that stretch.
        let history = [sample(12, [.automotive]), sample(30, [.walking])]
        let known = [DateInterval(start: t0 + 15 * 60, end: t0 + 30 * 60)]
        #expect(RecoveryPlanner.recover(history: history, knownTrips: known, visits: [], now: t0 + 3600).isEmpty)
    }

    @Test func pieceNextToARecordedTripGetsNoEndpointAcrossIt() throws {
        let a = Coordinate(latitude: 53.8, longitude: -1.55), b = Coordinate(latitude: 53.9, longitude: -1.5)
        let visits = [Visit(coordinate: a, arrival: t0 - 3600, departure: t0 + 9 * 60),
                      Visit(coordinate: b, arrival: t0 + 31 * 60, departure: nil)]
        let history = [sample(10, [.automotive]), sample(30, [.walking])]
        let known = [DateInterval(start: t0 + 20 * 60, end: t0 + 30 * 60)] // allowance covers 15–30
        let piece = try #require(RecoveryPlanner.recover(history: history, knownTrips: known, visits: visits, now: t0 + 3600).first)
        #expect(piece.start == t0 + 600)
        #expect(piece.end == t0 + 900)
        #expect(piece.from == a)
        #expect(piece.to == nil) // the user, or the trip's own start, supplies it
    }

    @Test func coverageUsesTheUnionNotTheSum() {
        let run = DateInterval(start: t0, duration: 600)
        let overlapping = [DateInterval(start: t0, duration: 400), DateInterval(start: t0 + 100, duration: 300)]
        #expect(RecoveryPlanner.coveredDuration(of: run, by: overlapping) == 400)
    }
}

@Suite struct EncodingTests {
    @Test func motionKindsAreWrittenSorted() throws {
        let sample = MotionSample(startDate: Scenario.t0, kinds: [.walking, .automotive, .stationary], confidence: .high)
        let json = String(decoding: try JSONEncoder().encode(sample), as: UTF8.self)
        #expect(json.contains(#""kinds":["automotive","stationary","walking"]"#))
        #expect(try JSONDecoder().decode(MotionSample.self, from: Data(json.utf8)) == sample)
    }
}

@Suite struct LocalDateTests {
    func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test func winterIsGMT() {
        #expect(LocalDate.string(for: utc("2026-03-28T23:30:00Z")) == "2026-03-28")
    }

    @Test func summerIsBSTSoLateEveningUTCIsTheNextDay() {
        #expect(LocalDate.string(for: utc("2026-07-01T23:30:00Z")) == "2026-07-02")
    }

    @Test func taxYearBoundaryAtMidnightBST() {
        // 23:30 UTC on 5 April 2026 is 00:30 BST on 6 April: a trip starting then is in 2026–27.
        #expect(LocalDate.string(for: utc("2026-04-05T23:30:00Z")) == "2026-04-06")
        #expect(LocalDate.string(for: utc("2026-04-05T22:30:00Z")) == "2026-04-05")
    }

    @Test func clocksGoBack() {
        // 25 Oct 2026, 01:30 happens twice locally; both are still 25 October.
        #expect(LocalDate.string(for: utc("2026-10-25T00:30:00Z")) == "2026-10-25")
        #expect(LocalDate.string(for: utc("2026-10-25T01:30:00Z")) == "2026-10-25")
    }
}
