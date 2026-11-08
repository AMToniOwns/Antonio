import Foundation
import Testing
@testable import TripDetection

@Suite struct CandidateTests {
    @Test func wakeStartsLiveQueriesMotionAndRunsRecovery() {
        var s = Scenario()
        let out = s.send(.wake(.significantLocationChange, at: s.now))
        #expect(out.contains(.runRecovery))
        #expect(out.contains(.startLive))
        #expect(out.contains(.queryMotionHistory(from: s.now - 300)))
        #expect(out.contains(.scheduleTimer(.candidateTimeout, at: s.now + 120)))
        #expect(s.phase == .candidate)
    }

    @Test func relaunchWhileIdleOnlyRunsRecovery() {
        var s = Scenario()
        #expect(s.send(.relaunched(at: s.now)) == [.runRecovery])
        #expect(s.phase == .idle)
    }

    @Test func candidateWithoutEvidenceTimesOut() {
        var s = Scenario()
        s.wake()
        s.waitWithFixes(seconds: 60)
        let out = s.send(.timerFired(.candidateTimeout, at: Scenario.t0 + 120))
        #expect(out.contains(.stopLive))
        #expect(out.contains(.cancelTimer(.candidateTimeout)))
        #expect(s.phase == .idle)
        #expect(s.trips.isEmpty)
    }

    @Test func fastFixesAndDisplacementStartDriving() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 10, speed: 13) // evidence, but only 130 m
        #expect(s.phase == .candidate)
        s.move(seconds: 15, speed: 13) // 325 m
        #expect(s.phase == .driving)
        #expect(s.effects.contains(.cancelTimer(.candidateTimeout)))
        #expect(s.effects.contains(.scheduleTimer(.silenceWatchdog, at: s.now + 240 - 1)))
    }

    @Test func unknownSpeedIsDerivedFromConsecutiveFixes() {
        var s = Scenario()
        s.wake()
        s.move(seconds: 40, speed: 10, reportSpeed: false)
        #expect(s.phase == .driving)
    }

    @Test func currentMotionHistoryIsEvidenceAndDatesTheStart() throws {
        var s = Scenario()
        s.wake()
        let history = [MotionSample(startDate: s.now - 400, kinds: [.walking], confidence: .high),
                       MotionSample(startDate: s.now - 200, kinds: [.automotive], confidence: .medium)]
        s.send(.motionHistory(history, receivedAt: s.now))
        s.move(seconds: 80, speed: 4) // slow (320 m): only motion says this is a drive
        #expect(s.phase == .driving)
        s.move(seconds: 100, speed: 13)
        s.waitWithFixes(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.startedAt == Scenario.t0 - 200)
    }

    @Test func lateWakeAfterArrivalIsNotADrive() {
        var s = Scenario()
        s.wake()
        // Drove until a minute ago, walking now: recovery's job, not a live trip.
        let history = [MotionSample(startDate: s.now - 300, kinds: [.automotive], confidence: .high),
                       MotionSample(startDate: s.now - 60, kinds: [.walking], confidence: .high)]
        s.send(.motionHistory(history, receivedAt: s.now))
        s.move(seconds: 60, speed: 1.4)
        s.timer(.candidateTimeout, at: Scenario.t0 + 120)
        #expect(s.phase == .idle)
        #expect(s.trips.isEmpty)
    }

    @Test func lowConfidenceAutomotiveIsNotEvidence() {
        var s = Scenario()
        s.wake()
        s.send(.motionHistory([MotionSample(startDate: s.now, kinds: [.automotive], confidence: .low)], receivedAt: s.now))
        s.move(seconds: 40, speed: 5)
        #expect(s.phase == .candidate)
    }

    @Test func carParkCrawlKeepsTheCandidateWhileMotionSaysDriving() {
        var s = Scenario()
        s.wake()
        s.send(.motionHistory([MotionSample(startDate: s.now - 20, kinds: [.automotive], confidence: .high)], receivedAt: s.now))
        s.move(seconds: 100, speed: 2) // 200 m: not far enough yet
        s.timer(.candidateTimeout, at: Scenario.t0 + 120)
        #expect(s.phase == .candidate)
        s.move(seconds: 20, speed: 13)
        #expect(s.phase == .driving)
    }

    @Test func candidateExpiresEvenWithEvidence() {
        var s = Scenario()
        s.wake()
        s.send(.motionHistory([MotionSample(startDate: s.now, kinds: [.automotive], confidence: .high)], receivedAt: s.now))
        s.timer(.candidateTimeout, at: Scenario.t0 + 600)
        #expect(s.phase == .idle)
        #expect(s.logs.contains(.candidateExpired))
    }

    @Test func staleLastStopIsNotUsedAsTheStart() throws {
        let farAway = Coordinate(latitude: 53.6, longitude: -1.55) // ~22 km south
        var s = Scenario(lastStop: farAway)
        s.startDriving()
        s.waitWithFixes(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.startCoordinate == trip.firstFixCoordinate)
        #expect(trip.startIsUncertain)
        #expect(s.logs.contains { if case .lastStopIgnored = $0 { return true }; return false })
        #expect(s.logs.filter { if case .lastStopIgnored = $0 { return true }; return false }.count == 1)
    }

    @Test func outlierFixIsReplacedAfterRepeatedJumps() throws {
        var s = Scenario()
        s.wake()
        let bogus = Coordinate(latitude: 54.8, longitude: -1.55) // a stray cached fix 111 km away
        s.send(.fix(LocationFix(timestamp: s.now, coordinate: bogus, horizontalAccuracy: 10), receivedAt: s.now))
        s.move(seconds: 3, speed: 13)
        guard case let .candidate(c) = s.detector.state.phase else { Issue.record("not a candidate"); return }
        #expect(c.fixes.count == 1)
        #expect(c.fixes.first?.coordinate == s.position)
    }
}

@Suite struct TripTests {
    @Test func simpleTripIsEmittedWithMeasuredDistance() throws {
        var s = Scenario()
        s.startDriving(seconds: 600) // 7.8 km
        s.waitWithFixes(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(s.trips.count == 1)
        #expect(abs(trip.measuredMetres - 7_787) < 20) // 599 joins × 13 m
        #expect(trip.startCoordinate == Scenario.home)
        #expect(!trip.startIsUncertain)
        #expect(trip.startedAt == Scenario.t0)
        #expect(trip.endedAt == Scenario.t0 + 605) // the first stopped fix
        #expect(trip.gaps.isEmpty)
        #expect(trip.stops.isEmpty)
        #expect(trip.detectorVersion == TripDetector.version)
        #expect(trip.config == DetectorConfig())
        #expect(trip.startDateLocal == LocalDate.string(for: Scenario.t0))
        #expect(s.effects.contains(.stopLive))
        #expect(s.effects.contains(.setStopRegion(centre: trip.endCoordinate, radiusMetres: 150)))
        #expect(s.phase == .idle)
        #expect(s.detector.state.lastStop?.coordinate == trip.endCoordinate)
    }

    @Test func startIsTheLastStopSoTheLeadInNeedsAnEstimate() throws {
        var s = Scenario()
        s.position.latitude += 400 / Scenario.metresPerDegreeLatitude // SLC woke us 400 m in
        s.startDriving()
        s.waitWithFixes(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.startCoordinate == Scenario.home)
        #expect(trip.firstFixCoordinate != Scenario.home)
        #expect(trip.needsEstimate)
    }

    @Test func noLastStopMeansTheStartIsUncertain() throws {
        var s = Scenario(lastStop: nil)
        s.startDriving()
        s.waitWithFixes(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.startCoordinate == trip.firstFixCoordinate)
        #expect(trip.startIsUncertain)
        #expect(trip.needsEstimate)
    }

    @Test func tripShorterThanPointThreeMilesIsDropped() {
        var s = Scenario()
        s.startDriving(seconds: 30) // 390 m
        s.waitWithFixes(seconds: 250)
        #expect(s.trips.isEmpty)
        #expect(s.logs.contains { if case .tripTooShort = $0 { return true }; return false })
        #expect(s.phase == .idle)
    }

    @Test func longGapIsRecordedForEstimationNotInvented() throws {
        var s = Scenario()
        s.startDriving()
        s.now += 180 // a tunnel: 3 minutes, 2.3 km, no fixes
        s.position.latitude += 2_340 / Scenario.metresPerDegreeLatitude
        s.move(seconds: 60, speed: 13)
        s.waitWithFixes(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.gaps.count == 1)
        #expect(trip.needsEstimate)
        #expect(trip.measuredMetres < 3_000)
    }

    @Test func shortGapIsJoinedInAStraightLine() throws {
        var s = Scenario()
        s.startDriving()
        s.now += 60
        s.position.latitude += 780 / Scenario.metresPerDegreeLatitude
        s.move(seconds: 60, speed: 13)
        s.waitWithFixes(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(trip.gaps.isEmpty)
        #expect(abs(trip.measuredMetres - (119 * 13 + 780 + 13 + 59 * 13)) < 20)
    }
}

@Suite struct StopTests {
    @Test func parkedPhoneWithNoFixesEndsByWatchdog() throws {
        var s = Scenario()
        s.startDriving()
        let last = try #require(s.lastPointTime)
        s.park(seconds: 3600)
        s.timer(.silenceWatchdog, at: last + 240)
        let trip = try #require(s.trips.first)
        #expect(trip.endedAt == last)
        #expect(trip.endReason == .silence)
        #expect(s.phase == .idle)
        #expect(s.effects.contains(.stopLive))
    }

    @Test func earlyWatchdogReschedules() throws {
        var s = Scenario()
        s.startDriving()
        let out = s.send(.timerFired(.silenceWatchdog, at: s.now - 60))
        #expect(out.contains(.scheduleTimer(.silenceWatchdog, at: s.now + 240)))
        #expect(s.phase == .driving)
    }

    @Test func watchdogHoldsInTraffic() {
        var s = Scenario()
        s.startDriving()
        s.motion([.automotive, .stationary])
        s.timer(.silenceWatchdog, at: s.now + 240)
        #expect(s.phase == .driving)
        #expect(s.logs.contains(.trafficHold))
        #expect(s.trips.isEmpty)
    }

    @Test func walkingMotionStartsTheStopWithoutFixes() throws {
        var s = Scenario()
        s.startDriving()
        let last = try #require(s.lastPointTime)
        s.park(seconds: 20) // out of the car; the distance filter sends nothing
        s.motion([.walking])
        #expect(s.phase == .stopping)
        #expect(s.effects.contains(.scheduleTimer(.stopTimeout, at: last + 240)))
        s.timer(.stopTimeout, at: last + 240)
        let trip = try #require(s.trips.first)
        #expect(trip.endedAt == last)
    }

    @Test func unknownSpeedStillStops() throws {
        var s = Scenario()
        s.wake()
        s.move(seconds: 120, speed: 13, reportSpeed: false)
        s.waitWithFixes(seconds: 250, reportSpeed: false)
        #expect(s.trips.count == 1)
    }

    @Test func trafficLightsDontEndTheTrip() {
        var s = Scenario()
        s.startDriving()
        s.motion([.automotive, .stationary])
        s.waitWithFixes(seconds: 300) // a jam longer than the stop timer
        #expect(s.phase == .driving)
        s.move(seconds: 60, speed: 13)
        #expect(s.trips.isEmpty)
    }

    @Test func trafficHoldHasALimit() {
        var s = Scenario()
        s.startDriving()
        s.motion([.automotive, .stationary]) // stale: Core Motion never reports leaving the car
        s.waitWithFixes(seconds: 1500)
        #expect(s.trips.count == 1)
    }

    @Test func crawlingInAQueueIsOneTrip() {
        var s = Scenario()
        s.startDriving()
        s.motion([.automotive, .stationary])
        s.waitWithFixes(seconds: 30)
        #expect(s.phase == .driving)
        s.move(seconds: 30, speed: 3)
        s.waitWithFixes(seconds: 30)
        s.move(seconds: 60, speed: 13)
        #expect(s.phase == .driving)
        #expect(s.trips.isEmpty)
    }

    @Test func crawlResumesAStopOnlyWithAutomotiveMotion() {
        var s = Scenario()
        s.startDriving()
        s.waitWithFixes(seconds: 5)
        #expect(s.phase == .stopping)
        s.move(seconds: 30, speed: 3) // jogging pace, no motion data: not a drive
        #expect(s.phase == .stopping)
        s.motion([.automotive, .stationary]) // in the car, queuing
        s.move(seconds: 10, speed: 3)
        #expect(s.phase == .driving)
    }

    @Test func plainAutomotiveDoesNotHoldSlowFixes() throws {
        var s = Scenario()
        s.startDriving()
        s.motion([.automotive]) // the last change Core Motion reported, minutes ago
        s.waitWithFixes(seconds: 250)
        #expect(s.trips.count == 1)
    }

    @Test func parkedPhoneDriftEndsTheTripAndAddsNoDistance() throws {
        var s = Scenario()
        s.startDriving()
        let parked = s.position
        s.drift(seconds: 600) // indoors: 30 m hops, 40 m accuracy, no speed
        let trip = try #require(s.trips.first)
        #expect(trip.endCoordinate == parked)
        #expect(abs(trip.measuredMetres - 119 * 13) < 5)
    }

    @Test func driftDoesNotResumeAStoppedTrip() {
        var s = Scenario()
        s.startDriving()
        s.waitWithFixes(seconds: 5)
        s.drift(seconds: 120, every: 10, radius: 30)
        #expect(s.phase == .stopping)
    }

    @Test func walkingMotionRightAfterAFastFixIsIgnored() {
        var s = Scenario()
        s.startDriving()
        s.motion([.walking]) // GPS said 13 m/s a second ago: a bumpy road, not a walk
        #expect(s.phase == .driving)
    }

    @Test func walkingSpeedDoesNotResume() {
        var s = Scenario()
        s.startDriving()
        s.park(seconds: 20)
        s.motion([.walking])
        s.move(seconds: 60, speed: 2.5) // a brisk walk
        #expect(s.phase == .stopping)
    }

    @Test func shortDropOffKeepsOneTripAndRecordsTheStop() throws {
        var s = Scenario()
        s.startDriving()
        s.park(seconds: 20)
        s.motion([.walking])
        s.waitWithFixes(seconds: 160) // under 4 minutes in all
        #expect(s.phase == .stopping)
        s.motion([.automotive])
        s.move(seconds: 120, speed: 13)
        #expect(s.phase == .driving)
        #expect(s.effects.contains(.cancelTimer(.stopTimeout)))
        s.park(seconds: 20)
        s.motion([.walking])
        s.waitWithFixes(seconds: 250)
        let trip = try #require(s.trips.first)
        #expect(s.trips.count == 1)
        #expect(trip.stops.count == 1)
        #expect(trip.endReason == .stopTimer)
    }

    @Test func walkingAwayFromTheCarIsTrimmed() throws {
        var s = Scenario()
        s.startDriving()
        let car = s.position
        let parkedAt = try #require(s.lastPointTime)
        let driven = 119 * 13.0
        s.park(seconds: 20)
        s.motion([.walking])
        s.move(seconds: 200, speed: 1.4) // 280 m on foot
        s.timer(.stopTimeout, at: parkedAt + 240)
        let trip = try #require(s.trips.first)
        #expect(trip.endCoordinate == car)
        #expect(abs(trip.measuredMetres - driven) < 5)
        #expect(s.detector.state.lastStop?.coordinate == car)
    }

    @Test func stopTimerEndsTheTrip() throws {
        var s = Scenario()
        s.startDriving()
        s.waitWithFixes(seconds: 5)
        let stoppedAt = s.now
        s.timer(.stopTimeout, at: stoppedAt + 240)
        let trip = try #require(s.trips.first)
        #expect(trip.endedAt == stoppedAt)
    }

    @Test func staleStopTimerIsIgnored() {
        var s = Scenario()
        s.startDriving()
        s.waitWithFixes(seconds: 5)
        s.move(seconds: 60, speed: 13)
        s.timer(.stopTimeout, at: s.now)
        #expect(s.phase == .driving)
        #expect(s.trips.isEmpty)
    }

    @Test func lateFixAfterAMissedStopTimerEndsTheTripCleanly() throws {
        var s = Scenario()
        s.startDriving()
        s.waitWithFixes(seconds: 5)
        s.now += 600 // suspended; the stop timer never fired
        s.fix(speed: 0)
        let trip = try #require(s.trips.first)
        #expect(s.trips.count == 1)
        #expect(trip.gaps.isEmpty)
        #expect(s.phase == .idle)
    }

    @Test func automotiveMotionAfterAMissedStopTimerStartsANewTrip() {
        var s = Scenario()
        s.startDriving()
        s.waitWithFixes(seconds: 5)
        s.now += 3600 // suspended; the stop timer never fired
        s.motion([.automotive])
        #expect(s.trips.count == 1)
        #expect(s.trips.first?.stops.isEmpty == true)
        #expect(s.phase == .candidate)
    }

    @Test func longJamBehindTheDistanceFilterIsNotSplit() {
        var s = Scenario()
        s.startDriving()
        s.motion([.automotive, .stationary])
        s.park(seconds: 900) // 15 minutes, no fixes
        s.move(seconds: 60, speed: 13)
        #expect(s.trips.isEmpty)
        #expect(s.phase == .driving)
    }

    @Test func driveOffAfterAMissedStopTimerStartsANewTrip() {
        var s = Scenario()
        s.startDriving()
        s.waitWithFixes(seconds: 5)
        s.now += 600
        s.move(seconds: 60, speed: 13) // the next drive
        #expect(s.trips.count == 1)
        #expect(s.phase == .driving)
    }

    @Test func fixHoursLaterSplitsTheTripInsteadOfJoiningIt() throws {
        var s = Scenario()
        s.startDriving()
        s.park(seconds: 7200)
        s.move(seconds: 60, speed: 13)
        let first = try #require(s.trips.first)
        #expect(s.trips.count == 1)
        #expect(first.gaps.isEmpty)
        #expect(s.phase == .driving)
        #expect(s.logs.contains { if case .tripSplitAfterSilence = $0 { return true }; return false })
    }

    @Test func arrivalVisitHereEndsTheTrip() {
        var s = Scenario()
        s.startDriving()
        s.waitWithFixes(seconds: 10)
        s.send(.visit(Visit(coordinate: s.position, arrival: s.now - 5, departure: nil), receivedAt: s.now))
        #expect(s.trips.count == 1)
        #expect(s.phase == .idle)
    }

    @Test func lateVisitForThePlaceJustLeftIsIgnored() {
        var s = Scenario()
        s.startDriving()
        s.send(.visit(Visit(coordinate: Scenario.home, arrival: Scenario.t0 - 600, departure: nil), receivedAt: s.now))
        #expect(s.phase == .driving)
        #expect(s.logs.contains(.visitIgnored))
    }

    @Test func farAwayArrivalIsIgnored() {
        var s = Scenario()
        s.startDriving()
        let elsewhere = Coordinate(latitude: 53.9, longitude: -1.4)
        s.send(.visit(Visit(coordinate: elsewhere, arrival: s.now, departure: nil), receivedAt: s.now))
        #expect(s.phase == .driving)
    }
}

@Suite struct LifecycleTests {
    @Test func relaunchMidTripRestartsLiveAndCarriesOn() throws {
        var s = Scenario()
        s.startDriving()
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
        #expect(out.contains(.runRecovery))
        #expect(restored.phase == .driving)
        restored.move(seconds: 60, speed: 13)
        restored.waitWithFixes(seconds: 250)
        #expect(restored.trips.count == 1)
    }

    @Test func staleRelaunchClosesTheOldTrip() throws {
        var s = Scenario()
        s.startDriving()
        let last = try #require(s.lastPointTime)
        s.send(.relaunched(at: last + 3 * 3600))
        let trip = try #require(s.trips.first)
        #expect(trip.endedAt == last)
        #expect(s.phase == .idle)
        #expect(s.logs.contains { if case .staleTripClosedOnRelaunch = $0 { return true }; return false })
    }

    @Test func relaunchWhileStoppingReschedulesTheStopTimer() {
        var s = Scenario()
        s.startDriving()
        s.waitWithFixes(seconds: 5)
        guard case let .stopping(_, since) = s.detector.state.phase else { Issue.record("not stopping"); return }
        let out = s.send(.relaunched(at: s.now + 10))
        #expect(out.contains(.startLive))
        #expect(out.contains(.scheduleTimer(.stopTimeout, at: since + 240)))
    }

    @Test func relaunchedCandidateKeepsItsOriginalDeadline() {
        var s = Scenario()
        s.wake()
        let out = s.send(.relaunched(at: s.now + 60))
        #expect(out.contains(.scheduleTimer(.candidateTimeout, at: Scenario.t0 + 120)))
    }

    @Test func persistIsThrottledToOnceEveryFewSeconds() {
        var s = Scenario()
        s.startDriving(seconds: 600)
        let persists = s.effects.filter { effect in
            if case .persist = effect { return true }
            return false
        }.count
        #expect(persists > 100) // at least every 5 s over 10 minutes...
        #expect(persists <= 125) // ...but not every fix
    }

    @Test func recordedSessionReplaysToTheSameTrips() throws {
        let initial = Scenario().detector.state
        var s = Scenario()
        s.startDriving(seconds: 300)
        s.park(seconds: 20)
        s.motion([.walking, .stationary])
        s.waitWithFixes(seconds: 250)
        let log = try EventLog.encode(session: initial, events: s.events)
        let session = try EventLog.decodeSession(log)
        let replayed = TripDetector.replay(session.events, from: try #require(session.state))
        let replayedTrips = replayed.steps.flatMap(\.effects).compactMap { effect -> TripSegment? in
            if case let .emitTrip(trip) = effect { return trip }
            return nil
        }
        #expect(replayedTrips == s.trips)
        #expect(replayed.state == s.detector.state)
        #expect(replayed.steps.last?.phase == .idle)
        #expect(try EventLog.encode(session: initial, events: s.events) == log) // byte-identical
    }

    @Test func tripIDIsStableForTheSameDrive() throws {
        var a = Scenario(), b = Scenario()
        a.startDriving(); a.waitWithFixes(seconds: 250)
        b.startDriving(); b.waitWithFixes(seconds: 250)
        #expect(try #require(a.trips.first).id == (try #require(b.trips.first)).id)
    }

    @Test func staleCandidateIsReplacedByTheNextWake() throws {
        var s = Scenario()
        s.wake() // the candidate timer is never delivered
        s.now += 3600
        s.wake()
        guard case let .candidate(c) = s.detector.state.phase else { Issue.record("not a candidate"); return }
        #expect(c.since == s.now)
        #expect(s.logs.contains(.candidateExpired))
    }
}

@Suite struct AssistedAndPermissionTests {
    @Test func assistedCandidateWaitsForTheCarToMoveAndStartsWhenItLeaves() throws {
        var s = Scenario()
        s.send(.assistedStart(at: s.now))
        s.timer(.candidateTimeout, at: Scenario.t0 + 300)
        s.waitWithFixes(seconds: 300) // loading the van, GPS on
        #expect(s.phase == .candidate)
        let leaving = s.now
        s.move(seconds: 200, speed: 4)
        #expect(s.phase == .driving)
        s.send(.assistedStop(at: s.now))
        let trip = try #require(s.trips.first)
        #expect(trip.startedAt >= leaving)
        #expect(trip.startedAt <= leaving + 15)
        #expect(trip.endReason == .assistedStop)
    }

    @Test func assistedCandidateDoesNotWaitOvernight() {
        var s = Scenario()
        s.send(.assistedStart(at: s.now)) // the "stop" automation never runs
        s.now += 8 * 3600
        s.wake()
        #expect(s.logs.contains(.candidateExpired))
        guard case let .candidate(c) = s.detector.state.phase else { Issue.record("not a candidate"); return }
        #expect(!c.assisted)
    }

    @Test func shortAssistedTripIsDropped() {
        var s = Scenario()
        s.send(.assistedStart(at: s.now))
        s.move(seconds: 80, speed: 4) // 320 m
        s.send(.assistedStop(at: s.now))
        #expect(s.trips.isEmpty)
        #expect(s.phase == .idle)
    }

    @Test func assistedTripLongEnoughIsEmitted() {
        var s = Scenario()
        s.send(.assistedStart(at: s.now))
        s.move(seconds: 200, speed: 4) // 800 m
        s.send(.assistedStop(at: s.now))
        #expect(s.trips.count == 1)
        #expect(s.trips.first?.startedBy == .assisted)
        #expect(s.trips.first?.startIsUncertain == false)
    }

    @Test func abandoningACandidateCancelsItsTimer() {
        var s = Scenario()
        s.wake()
        let out = s.send(.assistedStop(at: s.now + 10))
        #expect(out.contains(.cancelTimer(.candidateTimeout)))
        // Even if the old timer is delivered anyway, it can't kill a newer candidate.
        s.now += 30
        s.wake()
        s.timer(.candidateTimeout, at: Scenario.t0 + 120)
        #expect(s.phase == .candidate)
    }

    @Test func permissionChangesNotify() {
        var s = Scenario()
        #expect(s.send(.authorizationChanged(.whenInUse, preciseLocation: true, at: s.now)).contains(.notify(.permissionDowngraded)))
        #expect(s.send(.authorizationChanged(.always, preciseLocation: false, at: s.now)).contains(.notify(.preciseLocationOff)))
        #expect(s.send(.authorizationChanged(.denied, preciseLocation: true, at: s.now)).contains(.notify(.locationDenied)))
        #expect(s.send(.authorizationChanged(.always, preciseLocation: true, at: s.now)).isEmpty)
    }

    @Test func denyingLocationEndsTheTrip() {
        var s = Scenario()
        s.startDriving()
        s.send(.authorizationChanged(.denied, preciseLocation: true, at: s.now))
        #expect(s.trips.count == 1)
        #expect(s.phase == .idle)
    }
}
