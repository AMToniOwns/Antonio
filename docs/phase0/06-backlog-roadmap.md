# 6. Risks, MVP backlog and roadmap

## 6.1 Technical risk register

| # | Risk | Likelihood | Impact | Mitigation | Owner/when |
|---|---|---|---|---|---|
| R1 | Background detection misses drives (recall < 95%) | Medium | Fatal | Layered wake + recovery (§3); measured go/no-go; assisted mode; fallback product | Detection test run |
| R2 | Late SLC wake under-counts distance (> 2% error) | **High** | High | Start from last stop + `MKDirections` gap estimate; region A/B; measure the gap first week | Test run week 1 |
| R3 | Force-quit stops relaunch on iOS 18/26 | Medium | Medium | Recovery from motion history; user guidance; measured | Test run |
| R4 | Tax-rule interpretation wrong (six open questions) | Medium | High (trust, refunds) | Accountant sign-off before launch; rules versioned and named in exports | Owner, before 9 Dec |
| R5 | No Mac / Swift toolchain → nothing compiled yet | **Current** | Blocks phase 1 | Allow download.swift.org; confirm Mac + Xcode 16+ access | Owner, now |
| R6 | Company Apple account (D-U-N-S) late | Medium | Delays launch | Request now; prototype on personal account | Owner, now |
| R7 | App Review pushback on Always location | Low | Medium | Core-feature justification, honest purpose strings, indicator on | Beta |
| R8 | Fewer than 6 testers finish / < 3 sole traders | Medium | Invalid go/no-go | Recruit 8 now; small thank-you payment | Owner |
| R9 | Core Data + CloudKit duplicates across devices | Medium | Medium | Client UUIDs, dedupe on start time, totals never synced | Phase 2 tests |
| R10 | Schedule slip misses January Self Assessment peak | **High** | Low (April 2027 is the main window) | Accept; aim for April 2027 MTD threshold change | — |
| R11 | Spec scope (accounts, backend, Business tier) delays launch | High if adopted | High | Defer behind seams (§1.4) | Decision D-A |

## 6.2 Prioritised MVP backlog

**Must (v1 launch)**
1. TripDetection package: state machine, fix filtering, gap handling, start-point estimate, replay tests.
2. Tracking service adapter: wake layer, live session, relaunch restore, authorisation monitoring, tracking log, debug timeline.
3. Persistence: Core Data model v1, JourneyStore, dedupe, file protection, CloudKit sync, point purge job.
4. Recovery of missed trips (unconfirmed, never counted).
5. Onboarding (vehicle, year end, permission explainers).
6. Today screen: review card, tax-year card with bands, health line, recent trips.
7. Journeys: list, filters, detail with map, classify, edit miles, merge, split, delete, manual add.
8. RateEngine integration ✅ engine built; wire to UI and snapshots.
9. Reports: FreeAgent CSV, generic CSV, PDF summary, ClaimSnapshot.
10. Entitlements + StoreKit 2: £34.99/yr, £3.99/mo, free trial decision, paywall, restore.
11. Privacy: export all, delete all, delete location detail, policy, "not tax advice".
12. Widget, Live Activity, rate-split note (plan v1).
13. Saved places + classification rules (paid).
14. CI: Linux packages + macOS app build/test.

**Should (v1 if time, else v1.1)**
- Assisted mode (Shortcuts App Intent) — promote to Must if R1/R2 results are marginal.
- Smart suggestion: "Last 3 trips to this place were Business — mark as Business?" (always asks).
- Analytics (opt-in, privacy-first).
- Parking/toll expenses attached to a trip.

**Won't (v1)** — accounts, Supabase backend, web dashboard, accountant portal, multi-driver/Business tier, receipt scanning, AI classification, direct HMRC/MTD submission, other countries.

## 6.3 Spec phase order vs recommended order

The spec builds authentication (phase 2) before tracking (phase 3) and the mileage engine at phase 5. Recommendation: **de-risk tracking first** — it is the go/no-go — and skip auth.

| Spec phase | Recommended |
|---|---|
| 0 Discovery | **0 Discovery** — this pack |
| 1 Foundation | **1 Foundation + tracking prototype**: Xcode project, packages, CI, TripDetection, tracking service, debug timeline, minimal store. Frozen at end → detection test run starts. |
| 2 Auth & onboarding | **2 v1 features (parallel with test run)**: onboarding (no auth), persistence + CloudKit, journeys, Today, design system |
| 3 Tracking | moved into 1 |
| 4 Journey management | in 2 |
| 5 Mileage engine | **done** (RateEngine, council-approved; pending first green run) |
| 6 Dashboard & reporting | **3 Reporting + commercial**: exports, snapshots, StoreKit, paywall, widget, Live Activity |
| 7 Backend & sync | **later**, triggered by a validated need (§1.4) |
| 8 Commercial | in 3 |
| 9 Beta & release | **4 Beta + release** |

Every phase ends with passing tests and a council review, and doesn't start until the previous phase's acceptance criteria are met.

## 6.4 Roadmap (realistic, from today, 8 Nov 2026)

The council plan had the detection build finished by 8 Nov and the test run starting 9 Nov. That hasn't happened (no toolchain, no Mac access confirmed, Stage 1 not started), so everything moves about two weeks.

| Phase | Dates | Exit criteria |
|---|---|---|
| 0 Discovery | 8–10 Nov | This pack approved |
| 1 Foundation + tracking prototype | 11–22 Nov | Packages green on CI; prototype app on testers' phones via TestFlight (personal account); TripDetection frozen and tagged |
| Detection test run | 23 Nov – ≥14 Dec (hard stop 23 Dec) | ≥200 reference drives, ≥21 days |
| 2 v1 features | 23 Nov – 18 Dec (parallel) | Onboarding, store, journeys, Today working on device; tests green |
| Go/no-go | 14–23 Dec | Plan thresholds |
| 3 Reporting + commercial | 4–15 Jan 2027 | Exports reconcile to claim; purchases work in sandbox |
| 4 Beta | 18–31 Jan | TestFlight with ≥20 users; crash-free ≥99.5%; battery < 5%/day |
| Launch | **early–mid February 2027** (or ~mid-March if the fix-and-remeasure cycle runs) | App Store approval |

January's Self Assessment peak is likely missed; the April 2027 MTD threshold change (the main window per the plan) is not.

## 6.5 MVP acceptance criteria — proposed amendments

| # | Spec wording | Proposed |
|---|---|---|
| 1 | "A user can register and configure their vehicle" | A user can **set up** (no account) and configure their vehicle and year end in under 2 minutes |
| 10 | "Data synchronises securely with the backend" | Data **syncs across the user's devices via their private iCloud**, and survives reinstall |
| 2, 13 | detect in supported background conditions; documented and tested on physical devices | **plus**: the detection test run meets the go thresholds (live recall ≥ 95%, total miles ±2%, median trip error ≤ 5%, false trips ≤ 5%) |
| new | — | Every export reconciles to the claim total to the penny and names its rules version |

All other criteria stand as written.
