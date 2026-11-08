# 2. Data model and schema

## 2.1 Changes from the spec's entities

| Spec entity | Change | Reason |
|---|---|---|
| User | **Becomes `Profile`, one row, local.** No email, no `subscriptionStatus`. | No account in v1. Entitlement comes from StoreKit at runtime; storing it invites staleness. |
| Vehicle | Add `expenseMethod`, `capitalAllowancesClaimed`, `archivedAt`; drop `active` | RateEngine needs the eligibility flags. Archive, never hard-delete, a vehicle with trips. |
| Journey | Split `distance` into `distanceMetres` (measured) and `userDistanceMetres` (override). Add `status`, `classificationSource`, `startPlaceID/endPlaceID`, `detectionVersion`, `deletedAt`. Classification gains `unreviewed`. | Detected vs confirmed must be explicit (spec §6 F3, council D3). Overrides must not destroy the measured value (audit). |
| JourneyLocation | **Becomes `RoutePoint`, retained only until purge** (see 2.4); a simplified `routePolyline` stays on the Journey. | Data minimisation. |
| MileageRate | **Not a table.** Lives in the versioned `rates.json` in RateEngine. | Rates are app configuration, not user data; versioned with the code and tested. Per-user overrides aren't allowed (HMRC rates are fixed). |
| Expense | **Deferred.** | Not in v1 scope; flat-rate mileage already covers vehicle running costs. Parking/tolls (claimable on top) are a good v1.x feature. |
| Subscription | **Not stored.** | StoreKit 2 is the source of truth. |
| — | **New: `Place`** (saved locations: home, yard, regular customers) | Drives saved-place rules and smarter classification. |
| — | **New: `ClassificationRule`** | "Always mark trips to my yard as business" — the only way a trip may be classified without a tap (spec F3, plan v1 paid feature). |
| — | **New: `ClaimSnapshot`** | Resolves "totals are calculated, never synced" (D6) vs "historical calculation preservation" (spec F5); see 2.3. |

## 2.2 Local schema (Core Data, v1)

All IDs are UUIDs generated on device. All entities carry `createdAt`, `updatedAt`, `deletedAt?` (tombstone, so CloudKit propagates deletes and a future backend can too).

**Profile** (single row)
`id, displayName?, businessName?, businessType (enum), accountingYearEndMonth, accountingYearEndDay, homePlaceID?, onboardingCompletedAt?, analyticsOptIn (Bool)`

**Vehicle**
`id, nickname, vehicleClass (carOrVan|motorcycle), make?, model?, registration?, expenseMethod (flatRate|actualCosts), capitalAllowancesClaimed (Bool), isDefault (Bool), archivedAt?`

**Journey**
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| vehicleID | UUID? | nil until set; default vehicle applied on detection |
| startedAt / endedAt | Date (UTC) | |
| startDateLocal | String `YYYY-MM-DD` | Europe/London date of `startedAt`; what RateEngine sees |
| startPlaceID / endPlaceID | UUID? | link to a saved Place when within its radius |
| startLabel / endLabel | String? | coarse reverse-geocoded label, e.g. "High St, Leeds" |
| startCoordinate / endCoordinate | lat/lon rounded to 4 dp (~11 m) | kept for the record of journey |
| distanceMetres | Int | measured from route points |
| userDistanceMetres | Int? | user override; used when present |
| status | enum `inProgress, detected, recovered, confirmed` | only `confirmed` counts (D3) |
| classification | enum `unreviewed, business, personal, commuting, excluded` | commuting/personal/excluded never count |
| classificationSource | enum `user, rule, default` | `default` covers "passengers default to Not work" |
| ruleID | UUID? | which rule classified it |
| purpose / customerName / notes | String? | |
| source | enum `detected, recovered, manual, assisted` | assisted = Shortcuts/CarPlay trigger |
| detectionVersion | String | TripDetection build that produced it (frozen-package audit) |
| routePolyline | Data? | simplified (Douglas–Peucker, ~25 m tolerance), for the map |
| pointsPurgeAfter | Date? | see 2.4 |
| mergedIntoID | UUID? | split/merge history |

Uniqueness / dedupe: `(source, startedAt rounded to 60 s, vehicleID)` checked on insert; recovered trips that overlap a detected trip by >50% of duration are discarded (council D6: "remove duplicates by ID and start time").

**RoutePoint** — `journeyID, timestamp, lat, lon, horizontalAccuracy, speed?`; batch-inserted; deleted at purge.

**Place** — `id, name, kind (home|work|customer|other), centre lat/lon, radiusMetres (100–500)`.

**ClassificationRule** — `id, placeID, direction (to|from|either), classification, enabled`. Paid feature.

**ClaimSnapshot** — `id, periodStart, periodEnd, rulesVersion, thresholdScope, totalPence, carVanMiles, motorcycleMiles, figuresJSON, tripIDsHash, createdAt, reason (export|markedFiled)`.

**TrackingEvent** — not Core Data: a rotating JSON-lines log file (7 days, ≤5 MB) for the debug timeline (D8) and support export.

## 2.3 Historical calculation preservation

Totals are recomputed from confirmed trips every time (D6), because a recomputation from the same rates file is deterministic. Two things can change a past figure: the user edits an old trip, or a rates-file change touches a past year. RateEngine already refuses mid-year rate changes, and published years are immutable by policy. To make the past *provable*:

- Every export and "mark year as filed" writes a **ClaimSnapshot** (rules version, scope, totals, a hash of the counted trip IDs and miles).
- If a later recomputation of a snapshotted period differs, the dashboard shows "Your 2026–27 figure has changed by £X since you exported it on 12 Jan" with a diff of the trips.
- Snapshots sync; totals don't.

## 2.4 Location data minimisation

HMRC needs a record of each business journey: date, start, end, purpose, miles. It doesn't need a GPS trace. Proposal:

| Data | Kept | Why |
|---|---|---|
| Raw route points | until **30 days after the trip is confirmed** (or 60 days if never confirmed), then deleted | needed to re-measure, split or fix distance while the user is reviewing |
| Simplified polyline | life of the record (user can turn off in Settings → Privacy) | shows the route on the map; supports the record if challenged |
| Start/end coordinates at 4 dp + labels | life of the record | the journey record itself |
| Tracking log | 7 days rotating, on device only | diagnostics |

User controls: delete a journey (hard delete after 30-day tombstone), delete all location detail (keeps miles, drops polylines/points), export everything (JSON + CSV), delete everything.

## 2.5 Future server schema (Supabase/Postgres) — not built in v1

Mirrors the local schema with `user_id uuid not null references auth.users`, plus:

```sql
alter table journeys enable row level security;
create policy "own rows" on journeys
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
-- same policy on vehicles, places, rules, snapshots
-- route_points: not uploaded at all by default
```

Sync design when it lands: device is authoritative per row; upsert by UUID with `updated_at` last-writer-wins plus tombstones; idempotent because IDs are client-generated. Accountant access comes via a separate `shares` table granting read on snapshots, not raw journeys.
