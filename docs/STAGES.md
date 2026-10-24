# Build stages

Each stage's deliverable is reviewed by the five-advisor council (Contrarian, Assumption-Ripper,
Expansionist, Outsider, Executor) and passes only on a unanimous approve vote.

| Stage | Window | Deliverable | Status |
|---|---|---|---|
| 0. Setup | 26 Oct – 1 Nov | Repo, RateEngine package with D7 tests | In review |
| 1. Detection | 2 – 8 Nov | TripDetection package (frozen end of week), prototype app with debug timeline | Not started |
| 2. Test run | 9 Nov – 8 Dec | 200 reference drives, 21+ days, odometer-checked | Not started |
| 2b. v1 in parallel | 9 Nov – 8 Dec | Core Data store, review screen, exports, paywall | Not started |
| 3. Go/no-go | 30 Nov – 9 Dec | Report against the thresholds | Not started |
| 4. Beta | 10 – 20 Dec | TestFlight | Not started |
| 5. Launch | 28 Dec – 31 Jan | App Store | Not started |

## Decisions taken during the build

| Date | Decision | Why |
|---|---|---|
| 2026-10-24 | 10,000-mile threshold counted across all vehicles by default (`thresholdScope` in `rates.json`; per-vehicle also supported and tested) | Matches HMRC's example and can only under-claim. Still to confirm with HMRC or an accountant. |
| 2026-10-24 | Accounting periods crossing tax years: price the whole period's miles at each tax year's rates, then apportion by days | The plan's verified fact from BIM75005. |
| 2026-10-24 | Motorcycle miles don't count towards the car/van threshold | The 24p rate has no threshold. |

## Owner actions (can't be done from code)

- [ ] Request the D-U-N-S number (critical path for the company Apple account)
- [ ] Confirm the 10,000-mile threshold scope with HMRC or an accountant
- [ ] Recruit 8 testers (at least 3 real sole traders) before 9 Nov
