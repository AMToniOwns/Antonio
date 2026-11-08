import Foundation
import Testing
@testable import TripDetection

@Suite struct TripDetectorTests {
    // MARK: Wake and candidate

    @Test func wakeStartsLiveAndQueriesMotionHistory() {
        var s = Scenario()
        let out = s.send(.wake(.significantLocationChange, at: s.now))
        #expect(out.contains(.startLive))
        #expect(out.contains(.queryMotionHistory(from: s.now - 300)))
        #expect(out.contains(.scheduleTimer(.candidateTimeout, at: s.now + 120)))
        #expect(s.phase == .candidate)
    }

    @Test func candidateWithoutEvidenceTimesOut() {
        var s = Scenario()
        s.wake()
        s.wait(seconds: 60)
        s.now += 60
        let out = s.send(.timerFired(.candidateTimeout, at: s.now))
        #expect(out.contains(.stopLive))
        #expect(s.phase == .idle)
        #expect(s.trips.isEmpty)
    }

    @Test func fastFixesAndDisplacementStartDriving() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 10, speed: 13) // 130 m: evidence, but not 300 m yet
        #expect(s.phase == .candidate)
        s.move(seconds: 15, speed: 13) // 325 m
        #expect(s.phase == .driving)
        #expect(s.effects.contains(.cancelTimer(.candidateTimeout)))
    }

    @Test func motionHistoryCountsAsEvidence() {
        var s = Scenario()
        s.wake()
        let sample = MotionSample(startDate: s.now - 200, kinds: [.automotive], confidence: .medium)
        s.send(.motionHistory([sample], receivedAt: s.now))
        // Slow, speed-unknown fixes: only motion history says this is a drive.
        for _ in 0..<40 {
            s.now += 1
            s.position.latitude += 10 / Scenario.metresPerDegreeLatitude
            s.send(.fix(LocationFix(timestamp: s.now, coordinate: s.position, horizontalAccuracy: 10), receivedAt: s.now))
        }
        #expect(s.phase == .driving)
    }

    @Test func lowConfidenceAutomotiveIsNotEvidence() {
        var s = Scenario()
        s.wake()
        s.send(.motionHistory([MotionSample(startDate: s.now, kinds: [.automotive], confidence: .low)], receivedAt: s.now))
        s.move(seconds: 40, speed: 5) // under driving speed
        #expect(s.phase == .candidate)
    }

    // MARK: A whole trip

    @Test func simpleTripIsEmittedWithMeasuredDistance() throws {
        var s = Scenario()
        s.wake()
        s.move(seconds: 600, speed: 13) // 7.8 km
        s.wait(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(s.trips.count == 1)
        #expect(abs(trip.measuredMetres - 7_787) < 20) // 599 joins × 13 m
        #expect(trip.startCoordinate == Scenario.home)
        #expect(trip.startedAt == Scenario.t0)
        #expect(trip.endedAt == Scenario.t0 + 605) // the first stopped fix
        #expect(trip.gaps.isEmpty)
        #expect(trip.detectorVersion == TripDetector.version)
        #expect(s.effects.contains(.stopLive))
        #expect(s.effects.contains(.setStopRegion(centre: trip.endCoordinate, radiusMetres: 150)))
        #expect(s.phase == .idle)
        #expect(s.detector.state.lastStop == trip.endCoordinate)
    }

    @Test func startIsTheLastStopSoTheGapNeedsAnEstimate() throws {
        var s = Scenario()
        s.position.latitude += 400 / Scenario.metresPerDegreeLatitude // SLC woke us 400 m into the drive
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.wait(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.startCoordinate == Scenario.home)
        #expect(trip.firstFixCoordinate != Scenario.home)
        #expect(trip.needsEstimate)
    }

    @Test func noLastStopUsesTheFirstFix() throws {
        var s = Scenario(lastStop: nil)
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.wait(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.startCoordinate == trip.firstFixCoordinate)
        #expect(!trip.needsEstimate)
    }

    @Test func tripShorterThanPointThreeMilesIsDropped() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 30, speed: 13) // 390 m
        s.wait(seconds: 250)
        #expect(s.trips.isEmpty)
        #expect(s.phase == .idle)
    }

    // MARK: Stops

    @Test func trafficLightsDontEndTheTrip() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.motion([.automotive, .stationary])
        s.wait(seconds: 300) // a long jam, longer than the stop timer
        #expect(s.phase == .driving)
        s.move(seconds: 60, speed: 13)
        #expect(s.trips.isEmpty)
    }

    @Test func shortDropOffKeepsOneTrip() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.motion([.walking])
        s.wait(seconds: 180) // under 4 minutes
        #expect(s.phase == .stopping)
        s.motion([.automotive])
        s.move(seconds: 120, speed: 13)
        #expect(s.phase == .driving)
        #expect(s.effects.contains(.cancelTimer(.stopTimeout)))
        s.motion([.walking])
        s.wait(seconds: 250)
        #expect(s.trips.count == 1)
    }

    @Test func stopTimerEndsTheTripWhenNoMoreFixesArrive() throws {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.wait(seconds: 5)
        #expect(s.phase == .stopping)
        let stoppedAt = s.now
        s.send(.timerFired(.stopTimeout, at: stoppedAt + 240))
        let trip = try #require(s.trips.first)
        #expect(trip.endedAt == stoppedAt)
    }

    @Test func lateFixEndsTheTripIfTheTimerNeverFired() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.wait(seconds: 5)
        s.now += 600 // suspended; no timer delivered
        s.send(.fix(LocationFix(timestamp: s.now, coordinate: s.position, horizontalAccuracy: 10,
                                speed: 0, speedAccuracy: 0.5), receivedAt: s.now))
        #expect(s.trips.count == 1)
    }

    @Test func arrivalVisitEndsTheTripAtOnce() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.wait(seconds: 10)
        s.send(.visit(Visit(coordinate: s.position, arrival: s.now - 5, departure: nil), receivedAt: s.now))
        #expect(s.trips.count == 1)
        #expect(s.phase == .idle)
    }

    @Test func staleStopTimerIsIgnored() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.wait(seconds: 5)
        s.move(seconds: 60, speed: 13) // moving again
        s.send(.timerFired(.stopTimeout, at: s.now))
        #expect(s.phase == .driving)
        #expect(s.trips.isEmpty)
    }

    // MARK: Fix filtering and gaps

    @Test func inaccurateStaleAndTeleportingFixesAreDropped() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        guard case let .driving(before) = s.detector.state.phase else { Issue.record("not driving"); return }
        let count = before.points.count

        s.now += 1
        let far = Coordinate(latitude: s.position.latitude + 0.1, longitude: s.position.longitude) // 11 km in 1 s
        s.send(.fix(LocationFix(timestamp: s.now, coordinate: far, horizontalAccuracy: 10, speed: 13, speedAccuracy: 1), receivedAt: s.now))
        s.send(.fix(LocationFix(timestamp: s.now, coordinate: s.position, horizontalAccuracy: 100, speed: 13, speedAccuracy: 1), receivedAt: s.now))
        s.send(.fix(LocationFix(timestamp: s.now - 30, coordinate: s.position, horizontalAccuracy: 10, speed: 13, speedAccuracy: 1), receivedAt: s.now))
        s.send(.fix(LocationFix(timestamp: s.now, coordinate: s.position, horizontalAccuracy: -1), receivedAt: s.now))

        guard case let .driving(after) = s.detector.state.phase else { Issue.record("not driving"); return }
        #expect(after.points.count == count)
    }

    @Test func longGapIsRecordedForEstimationNotInvented() throws {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        // Tunnel: 3 minutes with no fixes, 2.3 km further on.
        s.now += 180
        s.position.latitude += 2_340 / Scenario.metresPerDegreeLatitude
        s.move(seconds: 60, speed: 13)
        s.wait(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.gaps.count == 1)
        #expect(trip.needsEstimate)
        #expect(trip.measuredMetres < 3_000) // the tunnel isn't counted as measured
    }

    @Test func shortGapIsJoinedInAStraightLine() throws {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.now += 60
        s.position.latitude += 780 / Scenario.metresPerDegreeLatitude
        s.move(seconds: 60, speed: 13)
        s.wait(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.gaps.isEmpty)
        #expect(abs(trip.measuredMetres - (119 * 13 + 780 + 13 + 59 * 13)) < 20)
    }

    // MARK: Relaunch and persistence

    @Test func relaunchMidTripRestartsLiveAndCarriesOn() throws {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        // The app is killed; the platform restores the last persisted state.
        let saved = try #require(s.effects.reversed().compactMap { effect -> DetectorState? in
            if case let .persist(state) = effect { return state }
            return nil
        }.first)
        let data = try JSONEncoder().encode(saved)
        var restored = Scenario()
        restored.detector = TripDetector(state: try JSONDecoder().decode(DetectorState.self, from: data))
        restored.now = s.now + 30
        restored.position = s.position
        let out = restored.send(.relaunched(at: restored.now))
        #expect(out.first == .startLive)
        #expect(restored.phase == .driving)
        restored.move(seconds: 60, speed: 13)
        restored.wait(seconds: 250)
        #expect(restored.trips.count == 1)
    }

    @Test func relaunchWhileStoppingReschedulesTheStopTimer() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13)
        s.wait(seconds: 5)
        guard case let .stopping(_, since) = s.detector.state.phase else { Issue.record("not stopping"); return }
        let out = s.send(.relaunched(at: s.now + 10))
        #expect(out.contains(.startLive))
        #expect(out.contains(.scheduleTimer(.stopTimeout, at: since + 240)))
    }

    @Test func persistIsNotEmittedForEveryFix() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 600, speed: 13)
        let persists = s.effects.filter { effect in
            if case .persist = effect { return true }
            return false
        }.count
        #expect(persists > 0)
        #expect(persists < 40) // ~600 fixes
    }

    // MARK: Assisted mode and permissions

    @Test func assistedStartAndStop() {
        var s = Scenario()
        s.send(.assistedStart(at: s.now))
        s.move(seconds: 80, speed: 4) // slow, but assisted is evidence; 320 m clears the displacement
        #expect(s.phase == .driving)
        s.send(.assistedStop(at: s.now))
        #expect(s.trips.isEmpty) // 320 m: under the 0.3-mile minimum
        #expect(s.phase == .idle)
    }

    @Test func assistedTripLongEnoughIsEmitted() {
        var s = Scenario()
        s.send(.assistedStart(at: s.now))
        s.move(seconds: 200, speed: 4) // 800 m
        s.send(.assistedStop(at: s.now))
        #expect(s.trips.count == 1)
        #expect(s.trips.first?.startedBy == .assisted)
        #expect(s.phase == .idle)
    }

    @Test func permissionChangesNotify() {
        var s = Scenario()
        #expect(s.send(.authorizationChanged(.whenInUse, preciseLocation: true, at: s.now)).contains(.notify(.permissionDowngraded)))
        #expect(s.send(.authorizationChanged(.always, preciseLocation: false, at: s.now)).contains(.notify(.preciseLocationOff)))
        #expect(s.send(.authorizationChanged(.denied, preciseLocation: true, at: s.now)).contains(.notify(.locationDenied)))
        #expect(s.send(.authorizationChanged(.always, preciseLocation: true, at: s.now)).isEmpty)
    }
}
