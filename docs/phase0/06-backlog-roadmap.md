# 6. Risks, MVP backlog and roadmap

## 6.1 Technical risk register

| # | Risk | Likelihood | Impact | Mitigation | When |
|---|---|---|---|---|---|
| R1 | Background detection misses drives (live recall < 95%) | Medium | Fatal | Layered wake and recovery (§3); measured go/no-go; assisted mode; fallback product | Test run |
| R2 | A late SLC wake under-counts distance (> 2% error) | **High** | High | Start the trip from the last stop and estimate the gap with `MKDirections`; region A/B test; measure the gap in week 1 | Test run, week 1 |
| R3 | Live location can't start from a background wake, or a force-quit stops relaunch, on iOS 18/26 | Medium | High | Phase 1a device checks; classic `CLLocationManager` baseline; motion-history recovery | Phase 1a |
| R4 | Tax rules interpreted wrongly (the six open questions) | Medium | High | Accountant sign-off before launch; rules versioned and named in exports | Before go/no-go |
| R5 | No Swift toolchain or Mac, so nothing has been compiled yet. RateEngine is *written and reviewed, not verified*. | **Current** | Blocks Phase 1 | Entry gate (§6.4) | Now |
| R6 | Company Apple account (D-U-N-S) arrives late | Medium | Delays launch | Request now; prototype on a personal account with its own bundle ID | Now |
| R7 | App Review questions Always location on the first submission | **Medium** | 1–2 week delay | Core-feature justification, honest purpose strings, review buffer | Phase 4 |
| R8 | Fewer than 6 testers finish, or fewer than 3 are sole traders | Medium | Go/no-go invalid | Recruit 8 now; small thank-you payment; consent notice ready | Before Phase 1b |
| R9 | Core Data + CloudKit duplicates or schema lock-in | Medium | Medium | App Group store from day one; dedupe after import; additive-only schema reviewed before first production deploy | Phase 2 |
| R10 | Schedule slip misses the January Self Assessment peak | **Certain** | Low | Accept it. The main window is April 2027 (MTD threshold change) | — |
| R11 | Spec scope (accounts, backend, Business tier) delays launch | High if adopted | High | Defer behind seams (§1.4) | Decision D-A |
| R12 | Two iPhones on one Apple ID double-count trips | Medium | High (over-claim) | Tracking-device setting; cross-device overlap dedupe | Phase 2 |
| R13 | iCloud off or full means silent loss on reinstall | Medium | High | Sync health line; local export | Phase 2 |
| R14 | Revenue lag: free users first *need* to pay at their first quarterly update or return (summer 2027 at the earliest) | High | Medium (cash flow) | Model it against the month-12 target; trial/paywall timing is decision D-F | Before Phase 3 |
| R15 | The test run spans Christmas, when trade driving is atypical | High | Medium | Extension pre-agreed; see question Q3 | Test run |

## 6.2 Prioritised MVP backlog

**Must (v1 launch)**
1. TripDetection package: state machine, fix filtering, gap handling, start-point estimate, replay tests.
2. Tracking service adapter: wake layer, live session (classic `CLLocationManager` baseline, newer `CLLocationUpdate` behind the same protocol), relaunch restore, authorisation monitoring, tracking log, debug timeline with log and MetricKit export.
3. Persistence: Core Data `Synced` and `LocalOnly` configurations in an App Group container, JourneyStore, dedupe after import, file protection, CloudKit sync, point purge, sync health.
4. Recovery of missed trips (unconfirmed, never counted).
5. Onboarding: vehicle, year end, tracking device, permission explainers.
6. Today screen: review card with "confirm all", tax-year card, health line, recent trips.
7. Journeys: list, filters, detail with map, classify, edit miles, merge, split, delete, manual add.
8. RateEngine integration: the engine is written and council-reviewed; its first green test run is the first Phase 1a task.
9. Reports: FreeAgent CSV, generic CSV, PDF summary, ClaimSnapshot.
10. Entitlements and StoreKit 2 (£34.99 a year, £3.99 a month), paywall, restore purchases.
11. Privacy: export all data, delete all data, delete location detail, privacy policy, "not tax advice".
12. CI: Linux job for the packages, macOS job to build and test the app.

**Should (in v1 if time allows, otherwise v1.1)**
- Widget (it reads the shared App Group store).
- Saved places and classification rules (the classification is pre-filled; the user still confirms).
- Live Activity, for trips started in the foreground or through assisted mode only (§4.2).
- Assisted mode (Shortcuts App Intent). This becomes a **Must** if the R1 or R2 results are marginal.
- Rate-split explanation screen (the note itself is Must, inside item 6).
- Smart suggestion: "Your last 3 trips here were Business. Mark this one Business?" (always asks).
- Opt-in, privacy-first analytics.
- Parking and toll expenses attached to a trip.
- A read-only figures share for accountants (signed PDF/CSV, or a `CKShare` of snapshots), to test demand for a portal.

**Won't (v1)**
- Accounts.
- Supabase backend.
- Web dashboard.
- Accountant portal.
- Multi-driver support, or a Business tier.
- Receipt scanning.
- AI classification.
- HMRC or MTD submission.
- Other countries.

**Capacity rule:** if the test run triggers the two-week fix-and-remeasure cycle, that work comes before every v1 feature, and the v1 dates move.

## 6.3 Spec phase order vs recommended order

The spec builds authentication (phase 2) before tracking (phase 3), and the mileage engine at phase 5. The recommendation is to **de-risk tracking first**, because it decides the go/no-go, and to drop authentication from v1.

| Spec phase | Recommended |
|---|---|
| 0 Discovery | **0 Discovery:** this pack |
| 1 Foundation | **1a Foundation and tracking on the developer's phone**, then **1b the prototype on testers' phones**, with the detection code frozen |
| 2 Auth and onboarding | **2 v1 features**, in parallel with the test run: onboarding (no auth), persistence, journeys, Today, design system |
| 3 Tracking | moved into 1a/1b |
| 4 Journey management | in 2 |
| 5 Mileage engine | **written and reviewed**; verified in 1a |
| 6 Dashboard and reporting | **3 Reporting and commercial** |
| 7 Backend and sync | **later**, when a validated need triggers it (§1.4) |
| 8 Commercial | in 3 |
| 9 Beta and release | **4 Beta and release** |

Every phase ends with passing tests and a council review. The next phase doesn't start until the current one's exit criteria are met.

## 6.4 Roadmap

**Entry gate.** Every date below slips day for day from the date the gate clears. For example, if the Mac is confirmed on 18 Nov instead of 11 Nov, everything moves by 7 days.

| Needed | By | Why |
|---|---|---|
| `download.swift.org` allowed in this environment | 10 Nov | to compile and test the packages here |
| A Mac with Xcode 16 or later, and someone to build on it | 11 Nov | the app target, device checks and TestFlight uploads |
| Apple Developer Program membership on a personal account; prototype bundle ID `…milelog.prototype` | 18 Nov | TestFlight. External testers need Beta App Review (1–2 days); internal testers must be App Store Connect users |
| 8 testers' Apple IDs and signed consent notices | 25 Nov | Phase 1b |
| D-U-N-S number, then the company Apple account | before Phase 4 | the real app ships under the company |

| Phase | Dates (if the gate clears on time) | Exit criteria (testable) |
|---|---|---|
| 0 Discovery | 8–10 Nov | This pack approved |
| 1a Foundation and tracking on the developer's phone | 11–25 Nov | RateEngine and TripDetection tests green on CI. The app records 10 real drives on the developer's phone with distance within 5% of the odometer. The §3.6 device checklist is run, with results recorded. No crash on relaunch or force-quit. |
| 1b Prototype on testers' phones | 26 Nov – 2 Dec | TestFlight build installed on 8 phones. Testers' consent signed. TripDetection tagged and frozen. |
| Detection test run | from 3 Dec; ends at 200 or more drives and 21 or more days; hard stop 2 Jan | The plan's metrics are reported |
| 2 v1 features (in parallel) | 3 Dec – 8 Jan (Christmas off) | Onboarding, store, sync, journeys and Today work on a device, with tests green |
| Go/no-go | ~24 Dec – 6 Jan | The plan's thresholds |
| (Fix cycle, if needed) | +2 weeks fix, +remeasure | It takes priority over all other work |
| 3 Reporting and commercial | 11–22 Jan | Every export reconciles to the claim total to the penny. Sandbox purchase, restore and expiry all work. |
| 4 Beta and release | 25 Jan – 12 Feb; submit by 5 Feb | No open data-loss bugs. Every crash triaged. Battery taken from the test-run cohort (D5 protocol), not the beta. Privacy label and policy done. |
| **Launch** | **mid-February to mid-March 2027**; around April if the fix cycle runs | App Store approval, with a 1–2 week buffer for App Review |

January's Self Assessment peak is missed. The April 2027 MTD threshold change, the plan's main window, is not, provided the launch happens before about mid-March.

## 6.5 MVP acceptance criteria: proposed amendments

| # | Spec wording | Proposed |
|---|---|---|
| 1 | "A user can register and configure their vehicle" | A user can **set up** the app (no account) and configure their vehicle and year end in under 2 minutes |
| 10 | "Data synchronises securely with the backend" | Data **syncs across the user's devices through their private iCloud**, survives a reinstall, and the app warns the user when it can't sync |
| 2, 13 | detects journeys in supported background conditions; documented and tested on physical devices | **and** the detection test run meets the go thresholds: live recall ≥ 95%, total miles within ±2%, median trip error ≤ 5%, false trips ≤ 5% |
| new | — | Every export reconciles to the claim total to the penny and names its rules version |

All other criteria stand as written.
