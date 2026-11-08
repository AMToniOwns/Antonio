# Mile Log — UK mileage tracker

An iPhone mileage log for UK sole traders who use HMRC's flat mileage rates.
The plan is in the "UK Mileage Log — Build Plan" doc and the master specification. Phase 0 (architecture, tracking strategy, schema, roadmap) is in [docs/phase0](docs/phase0/README.md). Progress, decisions and known issues are in [docs/STAGES.md](docs/STAGES.md).

## Layout

| Path | What |
|---|---|
| `Packages/TripDetection` | Pure Swift: the trip state machine (wake → candidate → driving → stopping), fix filtering, gaps, recovery of missed drives, UK local dates. Events in, effects out; no Core Location. |
| `Packages/RateEngine` | Pure Swift: versioned HMRC rates file and the trips → claim function (D7). No UI or iOS dependencies, so it builds and tests on Linux. |

## Running the tests

```sh
(cd Packages/RateEngine && swift test)
(cd Packages/TripDetection && swift test)   # Swift 6 toolchain
```
