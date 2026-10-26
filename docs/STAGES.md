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
| 2026-10-26 | Home-screen running total covers the user's accounting period (year end set once in setup, default 5 April) | Matches what they file. |
| 2026-10-26 | Tax years after the last published rates use the latest rates and are flagged provisional (`ratesConfirmedThroughTaxYear`) | Keeps the total useful without hiding that HMRC hasn't confirmed it. |
| 2026-10-26 | CSV exports have one line per trip; per-trip pennies reconcile exactly to the claim total (largest remainder) | FreeAgent's mileage import and audit trail. |
| 2026-10-26 | Keep the plan's apportionment method; exports name it (`ApportionmentMethod.explanation`) | Pending accountant sign-off alongside threshold scope. |
| 2026-10-26 | Rates start 6 April 2013 | Simplified expenses for unincorporated businesses began then (council round 1). |
| 2026-10-26 | Package needs Xcode 16 / Swift 5.9+ tools; iOS 18 minimum written as `.iOS("18.0")` | Council round 1: `.v18` needs tools 6.0. |

## Owner actions (can't be done from code)

- [ ] Request the D-U-N-S number (critical path for the company Apple account)
- [ ] Ask an accountant, before 9 Nov: (a) is the 10,000-mile threshold across all vehicles or per vehicle; (b) is the apportionment method right for years not ending 5 April (31 Dec example: 10,000 miles → £5,239.73 vs £4,500 by trip date); (c) do miles on actual-costs vehicles count towards the threshold (currently no)
- [ ] Recruit 8 testers (at least 3 real sole traders) before 9 Nov

## Council log

| Stage | Round | Votes | Blocks fixed |
|---|---|---|---|
| 0 | 1 | 1 approve, 4 block | Manifest `.iOS(.v18)` on tools 5.9; `Decimal(Double)` noise in metres → miles; silent use of unpublished rates; tax-year rows didn't show weights or reconcile; no test run yet |
