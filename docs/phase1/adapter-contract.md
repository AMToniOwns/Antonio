# TripDetection adapter contract

`TripDetector` is pure. The iOS adapter (`App/Platform/Tracking`) turns Core Location and Core Motion callbacks into `DetectionEvent`s, then carries out the returned `DetectionEffect`s. These are the rules the adapter must follow. Replays and tests assume them.

## Events

1. **Order.** Events go to the detector one at a time, on one serial queue, in the order they were delivered. The adapter never reorders or batches them.
2. **Launch.** On every process start, the adapter first restores the last persisted `DetectorState` and sends `.relaunched(at: now)`. If the launch was caused by a location event (`UIApplication.LaunchOptionsKey.location`, or the first SLC or visit callback after launch), it then sends `.wake(.significantLocationChange | .visitDeparture | .regionExit, at:)`. Opening the app in the foreground sends only `.relaunched`.
3. **SLC and region callbacks while already live** are still sent as `.wake`. The detector ignores them unless it's idle.
4. **Fixes.** Send every `CLLocation` from `didUpdateLocations` as `.fix(_, receivedAt: now)`, one event per location, even when iOS delivers several at once. `receivedAt` is the delivery time, not the location's timestamp. The detector uses the difference to drop stale cached fixes. Pass `speed` and `speedAccuracy` exactly as given, including −1.
5. **Motion.** Send live `CMMotionActivity` updates as `.motion(_, receivedAt:)`. The reply to `.queryMotionHistory(from:)` goes back as one `.motionHistory(samples, receivedAt:)`, oldest first. Map `confidence` one to one, and send `unknown` only when that's the only flag set.
6. **Visits.** Send `CLVisit` as `.visit`. Map `arrivalDate`/`departureDate` of `.distantPast`/`.distantFuture` to `nil`.
7. **Authorisation.** Send `.authorizationChanged` from `locationManagerDidChangeAuthorization`, and once on every launch. `preciseLocation` is `accuracyAuthorization == .fullAccuracy`.

## Effects

| Effect | Adapter action |
|---|---|
| `startLive` / `stopLive` | start or stop the live layer (Phase 0 §3.2). Both are idempotent. |
| `queryMotionHistory(from:)` | `queryActivityStarting(from:to: now)`, then reply with `.motionHistory` |
| `runRecovery` | run `RecoveryPlanner.recover` over 7 days of history, with known trips from the store; save the results as `recovered`, unconfirmed journeys |
| `setStopRegion` | replace the single `CLMonitor` last-stop condition (only when the region A/B arm is on) |
| `scheduleTimer(id, at:)` | one timer per `TimerID`; a new schedule replaces the old one. A time in the past fires as soon as possible. If the process is suspended and the timer is missed, nothing is lost: the detector also checks elapsed time on the next fix, motion or relaunch. |
| `cancelTimer(id)` | cancel the timer, if one is scheduled |
| `persist(state)` | write atomically to the `LocalOnly` store before handling the next event. Writes may be coalesced, but the latest state must be on disk within 5 s. |
| `emitTrip` | save as a `detected` journey: estimate `needsEstimate` gaps and the lead-in with `MKDirections`, then set `startDateLocal`, `detectionVersion` and the polyline |
| `notify` | a local notification, plus a dashboard banner (Phase 0 §3.4) |
| `log` | append to the tracking log (JSON lines, 7 days, ≤ 5 MB), alongside the event that caused it |

## Tracking log and replay

The adapter writes every event it sends to the tracking log, using `EventLog.encode`, with diagnostics interleaved. The debug timeline exports this file. `TripDetector.replay(EventLog.decode(file), from: initialState)` reproduces every decision exactly, which is how a tester's problem drive becomes a regression test.

## Known limits (verify in the test run)

- Persisting the whole points array is quadratic over a long drive. An hour at 1 Hz is about 120 writes averaging 1,800 points. If MetricKit shows this costs battery, switch to a checkpoint plus an append-only point log.
- Fixes delivered more than 10 s late are dropped as stale. The tracking log counts these `fixRejected(stale)` events. If background batching causes many of them, raise `maxFixAge` for batched deliveries.
- Core Motion can't tell a driver from a passenger, or a car from a bus or train. Classification handles that (Phase 0 §3.4).
