# Phase 0 — Product and technical discovery

Status: **awaiting owner approval**. Phase 1 does not start until the decisions below are taken.

This pack responds to the *Mile Log — Master Product & Development Specification* and reconciles it with the council-approved *UK Mileage Log — Build Plan* (decisions D1–D9). Where they disagree, both positions and a recommendation are given.

| # | Deliverable | File |
|---|---|---|
| 1 | Architecture proposal | [01-architecture.md](01-architecture.md) §1.1–1.4 |
| 2 | Technology stack, alternatives, trade-offs | [01-architecture.md](01-architecture.md) §1.2 |
| 3 | System architecture diagram | [01-architecture.md](01-architecture.md) §1.5 |
| 4 | Database schema | [02-data-model.md](02-data-model.md) |
| 5 | Core Location tracking strategy | [03-tracking.md](03-tracking.md) §3.1–3.4, 3.6 |
| 6 | Background execution and battery strategy | [03-tracking.md](03-tracking.md) §3.2, 3.5 |
| 7 | Navigation and screen specification | [04-screens.md](04-screens.md) |
| 8 | Security and privacy assessment | [05-security-privacy.md](05-security-privacy.md) |
| 9 | Prioritised MVP backlog | [06-backlog-roadmap.md](06-backlog-roadmap.md) §6.2 |
| 10 | Roadmap, risks, acceptance criteria | [06-backlog-roadmap.md](06-backlog-roadmap.md) §6.1, 6.3–6.5 |

## Where this pack challenges the specification

| Spec | Recommendation | Section |
|---|---|---|
| Supabase backend, accounts and RLS in the MVP | **Local-first v1, no account; iCloud sync.** Backend added later behind existing seams, when an accountant portal / web / Business tier is validated | 1.4 |
| RevenueCat | **StoreKit 2** until there's a second platform | 1.2 |
| SwiftData | **Core Data** (council D6: migrations for tax records) | 1.2 |
| Free tier limits monthly journeys | **Free logging stays unlimited**; pay for £ totals, exports and rules (plan). Limiting logging means a free user has no history to pay for at tax time. | 6.2 |
| Business tier (multi-driver/vehicle admin) | **Not in v1.** Flat-rate mileage is the sole trader's own claim; multi-driver is a different product | 6.2 |
| Tracking at phase 3, after auth | **Tracking first** — it is the go/no-go | 6.3 |
| Mileage engine at phase 5 | **Already built** and council-approved (pending first test run) | 6.3 |
| `JourneyLocation` kept indefinitely | **Purge raw points 30 days after confirmation**; keep a simplified route | 2.4 |
| `Expense` entity | **Deferred** to v1.1 (parking/tolls) | 2.1 |
| "Commuting" classification | **Kept**, as a non-claimable category with help text | 2.2 |

## Decisions needed

- **D-A** Backend and accounts in v1? (recommend: no)
- **D-B** Free tier: unlimited logging with paid totals/exports (recommend) or journey-limited?
- **D-C** Raw GPS retention: 30 days after confirmation (recommend)?
- **D-D** Accept the revised roadmap (launch early–mid Feb 2027) and tracking-first phase order?

## Blockers on the owner (unchanged)

1. Allow `download.swift.org` in this environment so packages can be compiled and tested.
2. Confirm Mac + Xcode 16+ access, and an Apple Developer Program membership for the prototype (TestFlight).
3. D-U-N-S request for the company Apple account.
4. Accountant answers to the six questions in [../STAGES.md](../STAGES.md).
5. Recruit 8 testers (≥3 sole traders) for a test run starting ~23 Nov.
