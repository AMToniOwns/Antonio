# Build stages

Each stage's deliverable is reviewed by the five-advisor council (Contrarian, Assumption-Ripper,
Expansionist, Outsider, Executor) and passes only on a unanimous approve vote.

| Stage | Window | Deliverable | Status |
|---|---|---|---|
| 0. Setup | 26 Oct – 1 Nov | Repo, RateEngine package with D7 tests | Council approved (5/5, round 3). Exit gate open: `swift test` green |
| 1. Detection (now Phase 1a/1b, see docs/phase0) | 11 Nov – 2 Dec | TripDetection package (frozen end of week), prototype app with debug timeline | Not started |
| 2. Test run | from 3 Dec | 200 reference drives, 21+ days, odometer-checked | Not started |
| 2b. v1 in parallel | 3 Dec – 8 Jan | Core Data store, review screen, exports, paywall | Not started |
| 3. Go/no-go | ~24 Dec – 6 Jan | Report against the thresholds | Not started |
| 4. Beta | 25 Jan – 12 Feb | TestFlight | Not started |
| 5. Launch | mid-Feb – mid-Mar 2027 | App Store | Not started |

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
| 2026-10-26 | Year ends 31 March to 4 April are priced wholly in the tax year they fall in | HMRC treats them as 5 April since basis-period reform (council round 2). |
| 2026-10-26 | "To confirm" counts every unconfirmed trip, business or personal | Its business/personal label is only a guess until reviewed. |
| 2026-10-26 | Rates start 6 April 2013 | Simplified expenses for unincorporated businesses began then (council round 1). |
| 2026-10-26 | Package needs Xcode 16 / Swift 5.9+ tools; iOS 18 minimum written as `.iOS("18.0")` | Council round 1: `.v18` needs tools 6.0. |

## Owner actions (can't be done from code)

- [ ] Request the D-U-N-S number (critical path for the company Apple account)
- [ ] Ask an accountant, before the go/no-go (~24 Dec): (a) is the 10,000-mile threshold across all vehicles or per vehicle; (b) is the apportionment method right for years not ending 5 April (31 Dec example: 10,000 miles → £5,239.73 vs £4,500 by trip date); (c) do miles on actual-costs vehicles count towards the threshold (currently no); (d) for a year not ending 5 April, is the 10,000 miles counted over the accounting year (as coded) or per tax year; (e) does a short first period get the full 10,000 miles (currently yes); (f) we assume no one elects out of treating a 31 March – 4 April year end as 5 April — fine?
- [ ] Recruit 8 testers (at least 3 real sole traders) — by 25 Nov, see docs/phase0/README.md "Owner actions"

## Council log

| Stage | Round | Votes | Blocks fixed |
|---|---|---|---|
| Phase 0 pack | 6 | **5 approve** | — (split children share createdAt; extra Phase 2 dedupe tests) |
| Phase 0 pack | 5 | 4 approve, 1 block | "Higher-ranked" undefined for equal-status copies (50/50 split vs confirmed unsplit copy double-counted); now a strict total order with union coverage |
| Phase 0 pack | 4 | 4 approve, 1 block | Overlap groups chained, so split children or a long recovered trip could swallow real trips; now mutual pairwise matching plus a conservative union-coverage rule, miles tolerance, delete-both, undo records |
| Phase 0 pack | 3 | 4 approve, 1 block | Dedupe stored in synced mergedIntoID could loop across phones; now derived each pass, LocalOnly; conflicting confirmations prompt the user; device ID in Keychain ThisDeviceOnly |
| Phase 0 pack | 2 | 3 approve, 2 block | Duplicate-merge tie-break and merged trips counted; tracking-device handover on a new phone and duplicate Profile rows |
| Phase 0 pack | 1 | 0 approve, 5 block | Live-layer API generations mixed; wake budget; CloudKit constraints (route points, dedupe, schema); Live Activity can't start from background; two-iPhone double count; rule example was commuting; App Group store; roadmap not credible; plain-English decisions, free/paid matrix, fallback, dated owner actions |
| 0 | 3 | 5 approve | — (4 April year-end test strengthened) |
| 0 | 2 | 4 approve, 1 block | Year ends 31 Mar – 4 Apr weren't treated as 5 April (basis-period rule); also: unknown vehicles outside the period, validated year-end decoding, non-finite miles, confirmed-through year vs latest set |
| 0 | 1 | 1 approve, 4 block | Manifest `.iOS(.v18)` on tools 5.9; `Decimal(Double)` noise in metres → miles; silent use of unpublished rates; tax-year rows didn't show weights or reconcile; no test run yet |

## Carried into v1 (stage 2b) specs

- Show `ApportionmentMethod.explanation` beside the home-screen total and on exports only when `needsRateSplit` is true.
- Per-trip export rows show miles and rate per tax year, not one blended figure; label `overlapDays` as "days priced in this tax year".
- Exports carry `rulesVersion`, threshold scope, the provisional flag and excluded vehicles.
- Vehicles with trips are archived, not deleted (pending owner answer).
- Trip start time → Europe/London `CivilDate` conversion lives in TripDetection, with a clock-change test.
