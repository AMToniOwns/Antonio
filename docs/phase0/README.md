# Phase 0: product and technical discovery

Status: **awaiting owner approval**. Phase 1 does not start until the decisions below are made.

This pack answers the *Mile Log — Master Product & Development Specification* and reconciles it with the council-approved *UK Mileage Log — Build Plan*. Where the two disagree, this pack sets out both positions and recommends one.

**Markers used throughout:**
- **(verify)**: Apple doesn't document this clearly. It gets checked on real phones before anything depends on it.
- **(estimate)**: a planning figure that will be replaced by measurement.

## Deliverables

| # | Deliverable | File |
|---|---|---|
| 1 | Architecture proposal | [01-architecture.md](01-architecture.md) §1.1, 1.3, 1.4 |
| 2 | Technology stack, alternatives and trade-offs | [01-architecture.md](01-architecture.md) §1.2 |
| 3 | System architecture diagram | [01-architecture.md](01-architecture.md) §1.5 |
| 4 | Database schema | [02-data-model.md](02-data-model.md) |
| 5 | Core Location tracking strategy | [03-tracking.md](03-tracking.md) §3.1–3.4, 3.6 |
| 6 | Background execution and battery strategy | [03-tracking.md](03-tracking.md) §3.2 (wake budget), 3.5 |
| 7 | Navigation and screen specification | [04-screens.md](04-screens.md) |
| 8 | Security and privacy assessment | [05-security-privacy.md](05-security-privacy.md) |
| 9 | Prioritised MVP backlog | [06-backlog-roadmap.md](06-backlog-roadmap.md) §6.2 |
| 10 | Roadmap, risks and acceptance criteria | [06-backlog-roadmap.md](06-backlog-roadmap.md) §6.1, 6.3–6.5 |

## Where this pack challenges the specification

| Spec | Recommendation | Section |
|---|---|---|
| Supabase backend, accounts and Row Level Security in the MVP | **v1 works entirely on the phone, with no account, and syncs through iCloud.** A backend comes later, behind seams already built in, once an accountant portal, web app or Business tier is shown to be worth it. | 1.4 |
| RevenueCat | **StoreKit 2** until there's a second platform | 1.2 |
| SwiftData | **Core Data** (council D6) | 1.2 |
| A free tier limited by journeys | **Unlimited free logging** (decision D-B) | below |
| A Business tier (multi-driver) | **Not in v1** | 6.2 |
| Tracking built in phase 3, after authentication | **Tracking first**, because it decides the go/no-go | 6.3 |
| The mileage engine built in phase 5 | **Already written and reviewed.** Its first test run is the first Phase 1a task. | 6.3 |
| `JourneyLocation` kept forever and synced | **GPS points stay on the phone and are deleted 30 days after a trip is confirmed** | 2.4 |
| An `Expense` entity | **Moved to v1.1** (parking and tolls) | 2.1 |
| Rules classify trips silently | **Rules pre-fill the class; the user confirms**, with one tap for all trips at once | 2.1 |

## Decisions needed, in plain English

**D-A. Accounts and a server in v1?** *Recommended: no.*
- **No:** users don't sign up. Their trips stay on their iPhone and in their own iCloud. It launches sooner (about 4–6 weeks less work) and runs at no cost. The privacy promise ("no account, your data stays on your phone and in your own iCloud") becomes a selling point. It can't offer an accountant login or a web dashboard until a server is added later.
- **Yes:** users sign up. You hold everyone's location history, with the GDPR duties that brings: a privacy impact assessment, breach risk and data-retention enforcement. Hosting costs about $25 a month or more once the free tier runs out. It enables a web dashboard and accountant access, but it delays launch.

**D-B. What's free, and what's paid?** *Recommended: the split in this table.*

| Feature | Free | Pro (£34.99 a year or £3.99 a month) |
|---|---|---|
| Automatic trip detection, unlimited | ✓ | ✓ |
| Classify, edit, merge, split, add missed trips | ✓ | ✓ |
| Business miles so far, and progress to 10,000 miles | ✓ | ✓ |
| Journey history and map | ✓ | ✓ |
| Export all my data (JSON, a legal right under UK GDPR) | ✓ | ✓ |
| Basic trips CSV: date, from, to, miles, class, purpose; no £ (D-E) | ✓ | ✓ |
| Saved places (Home, customers), used to spot commuting | ✓ | ✓ |
| **£ claim total** on Today and the widget | — | ✓ |
| FreeAgent CSV and generic CSV with £ per trip | — | ✓ |
| PDF for your accountant | — | ✓ |
| Saved-place *rules* that pre-fill a trip's class | — | ✓ |
| Snapshots, and "your figure changed since you exported it" alerts | — | ✓ |

**What Pro sells:** free users can work out their claim themselves (miles × 55p, then 25p). Pro sells *not having to*: the £ figure kept up to date, files their software and accountant accept as they are, alerts when an exported figure changes, and rules that save taps. That's convenience, priced at about £3 a month. Whether it's enough is the plan's open bet: the council's own estimate in the build plan is about a 23% chance of reaching £135 a month within 12 months. The month-12 target already assumes this. The alternative is the spec's journey-limited free tier. Free users would stop logging, and then have no history worth paying for at tax time.

**D-C. How long are detailed GPS trails kept?** *Recommended: 30 days after a trip is confirmed, on the phone only.*
After that only a simplified route line and the start and end points remain. The cost is that old trips can't be re-measured, and future features such as CO₂ and fuel estimates can't use them. The alternative is to keep trails forever, which means more risk and more storage.

**D-D. The revised roadmap.** *Recommended: accept it.*
Tracking is built and tested first. Launch moves to **mid-February to mid-March 2027**, or around April if the fix cycle runs. January's Self Assessment peak is missed; the April 2027 MTD window is not. Dates slip day for day with the entry gate (§6.4).

**D-E. Is a basic trips CSV (no £, no bands) free?** *Recommended: yes.*
UK GDPR already requires a free data export, and a CSV is friendlier than JSON. Users who want £ totals and accountant-ready files still pay. The alternative is JSON only for free users, which makes the free tier slightly weaker without changing much.

**D-F. Free trial?** *Recommended: no trial at first. The free tier is the trial.*
The paywall appears when the user first taps for £ totals or an export. If conversion is poor, add a 7-day trial of Pro. Revenue lag is risk R14.

### If the detection test fails: the fallback product

If trips can't be detected reliably even after one fix cycle, Mile Log stops being a mileage app. The plan's fallback is a **UK residence day log**: an app that records which days the user spent in the UK, for people who have to count UK days for tax residence, such as people who work abroad part of the year. It reuses the location wake layer, and it only needs to know *which country you were in each day*, which is far easier than measuring every drive. It would need its own market check before any build.

## Owner actions, with dates

| Action | Needed by | Blocks |
|---|---|---|
| Allow `download.swift.org` in this environment's network settings | 10 Nov | compiling anything |
| Confirm a Mac with Xcode 16 or later, and who builds on it | 11 Nov | Phase 1a |
| Approve this pack (D-A to D-F) | 10 Nov | Phase 1a |
| Apple Developer Program membership (personal) | 18 Nov | TestFlight |
| Recruit 8 testers (at least 3 sole traders); collect Apple IDs and consent | 25 Nov | Phase 1b |
| Request a D-U-N-S number for the company Apple account | now (it can take weeks) | Phase 4 |
| Accountant answers to the six questions in [../STAGES.md](../STAGES.md). They're written for the accountant, so forward them unchanged. | before go/no-go (~24 Dec) | launch |
| Two iPhones for device checks (one on iOS 18, one on iOS 26). A borrowed phone counts. | 11 Nov | Phase 1a |
| At least 15 beta testers' Apple IDs (the 8 test-run testers plus 7) | ~12 Jan | Phase 4 |

## Questions for you

1. **Q1 Capacity:** who builds this, and how many hours a week? Is Christmas blocked out? The roadmap assumes one developer working with AI help, about full time.
2. **Q2 Deadline:** is there a date after which launching loses real value? The pack assumes it is about mid-March 2027, ahead of the April MTD change.
3. **Q3 Christmas:** can the test run cover Christmas, with extensions agreed in advance? The alternative is starting it on 4 January, which moves launch to about April.
4. **Q4 Testers:** will they be paid a thank-you, and will they agree to share GPS traces? A draft recruitment message is available.
5. **Q5 Scope:** are limited-company directors in scope? Their mileage follows different rules (AMAP, on a tax-year basis). The pack assumes sole traders only for v1.
6. **Q6 iCloud:** must the app work with iCloud off? The pack assumes yes: the app works fully on the phone and shows a warning.

## Glossary

| Term | Meaning |
|---|---|
| SLC (significant location change) | A low-power iOS service that wakes the app after the phone has moved about 500 m |
| Visits | iOS's low-power record of places where the phone stayed a while |
| Live tracking | Full GPS, on only during a drive |
| Core Motion | The phone's motion sensors; they tell driving apart from walking |
| Recall | The share of real drives the app caught |
| False trip | Something the app logged as a work drive that wasn't one |
| Go/no-go thresholds | The pass marks from the plan: recall at least 95%, total miles within 2% of the odometer, a typical trip within 5%, false trips 5% or fewer |
| Recovered trip | A drive rebuilt afterwards from motion history. It never counts until the user confirms it. |
| Core Data / CloudKit | Apple's on-device database, and its sync to the user's own iCloud |
| App Group | A shared storage area that lets the widget read the app's data |
| StoreKit 2 | Apple's in-app purchase system |
| TestFlight | Apple's system for giving testers pre-release builds |
| D1–D9 | Decisions from the council's build plan: D1 iOS 18, D2 detection, D3 missed trips, D4 testing (8 testers, 200 drives), D5 battery, D6 storage, D7 rate engine, D8 debug screen, D9 go/no-go thresholds |
| Tax year | 6 April to 5 April. Mileage rates change on 6 April |
| Self Assessment | the yearly tax return sole traders file online by 31 January |
| MTD (Making Tax Digital) | HMRC's move to digital records and quarterly updates. It applies from April 2026 to sole traders over £50k, and from April 2027 to those over £30k |
| AMAP | the mileage allowance employers pay employees (e.g. company directors), with its own rules. Out of scope for v1 |
| Claim total | the mileage expense the user puts on their return: miles × HMRC's rates |
