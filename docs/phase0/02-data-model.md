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
| — | **New: `ClassificationRule`** | e.g. "trips to Smith & Co's site are business". A rule **pre-fills** the classification; the trip still needs confirming (a one-tap "confirm all" on Today), because the app can't tell whether the user drove or was a passenger (D3, spec F3). Home ↔ a regular workplace is never auto-classified as business: it gets a commuting prompt, since ordinary commuting isn't claimable (BIM47705 **(verify)**). |
| — | **New: `ClaimSnapshot`** | Resolves "totals are calculated, never synced" (D6) vs "historical calculation preservation" (spec F5); see 2.3. |

## 2.2 Local schema (Core Data, v1)

**Store layout.** The store lives in an **App Group container from the first build**, so the widget, Live Activity and App Intents read the same store. Moving a CloudKit-mirrored store later risks duplicates. There are two Core Data configurations:
- **`Synced`**: mirrored to the user's iCloud private database by `NSPersistentCloudKitContainer`. Holds Profile, Vehicle, Journey, Place, ClassificationRule, ClaimSnapshot.
- **`LocalOnly`**: never leaves the phone. Holds RoutePoint and device settings. One drive at 1 Hz is thousands of points, and syncing them would cause a sync storm and push the most sensitive data off the device.

**CloudKit constraints**, which apply to the `Synced` configuration and shape the design:
- every attribute is optional or has a default;
- no unique constraints, so duplicates are removed in code after import, using persistent history tracking;
- relationships are optional;
- once the schema is deployed to production it can only be **added to** (no renames or deletions), so the v1 schema is reviewed with that in mind.

**Encrypted fields:** `allowsCloudEncryption` (encrypted with the user's iCloud keys) is set on `startCoordinate`, `endCoordinate`, `startLabel`, `endLabel`, `routePolyline`, `customerName`, `purpose`, `notes`, and Place `centre`/`name`. It must be decided before the first production schema deploy, because it probably can't be changed afterwards **(verify)**. Whether Advanced Data Protection makes these fields end-to-end encrypted is **(verify)**.

All IDs are UUIDs generated on the device. Every `Synced` entity carries `createdAt`, `updatedAt`, `deletedAt?` and `deviceID`. `deletedAt` is a tombstone, so deletions sync through CloudKit, and through a future backend too.

**Profile** (one logical row; see duplicates rule 5)
`id, displayName?, businessName?, businessType (enum), accountingYearEndMonth, accountingYearEndDay, homePlaceID?, onboardingCompletedAt?, analyticsOptIn (Bool), rulesetID ("uk-hmrc-flat"), distanceUnit (miles|km), trackingDeviceID`

`rulesetID`, `timeZoneID` and `currency` cost nothing now and keep other countries possible later.

**Tracking device.** `trackingDeviceID` names the one phone that detects trips, so someone with two iPhones on one Apple ID doesn't log every drive twice.
- **The device ID** is a random UUID made on first launch and stored in the `LocalOnly` configuration. It is not `identifierForVendor`, which changes on reinstall. A reinstall therefore counts as a new device.
- **On every launch**, if this phone isn't the tracking device, the app asks: "Track trips on this iPhone? (Your other iPhone, *name*, will stop.)" The prompt appears in onboarding, in Settings → Tracking, and on Today. When `trackingDeviceID` is empty (first install), the phone takes the role silently.
- **Today's health line:** "This iPhone isn't tracking trips. Tap to switch." It replaces the slow "last trip 9 days ago" warning as the signal after a phone upgrade.
- **The old phone** sees the change through sync and stops its wake layer.

**Vehicle**
`id, nickname, vehicleClass (carOrVan|motorcycle), make?, model?, registration?, expenseMethod (flatRate|actualCosts), capitalAllowancesClaimed (Bool), isDefault (Bool), archivedAt?`

**Journey**
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| vehicleID | UUID? | nil until set; default vehicle applied on detection |
| startedAt / endedAt | Date (UTC) | |
| timeZoneID | String | `Europe/London` in v1 |
| startDateLocal | String `YYYY-MM-DD` | local date of `startedAt` in `timeZoneID`; what RateEngine sees. Conversion lives in TripDetection, with a clock-change test |
| deviceID | UUID | the phone that recorded it |
| startPlaceID / endPlaceID | UUID? | link to a saved Place when within its radius |
| startLabel / endLabel | String? | coarse reverse-geocoded label, e.g. "High St, Leeds" |
| startCoordinate / endCoordinate | lat/lon rounded to 4 dp (~11 m) | kept for the record of journey |
| distanceMetres | Int | measured from route points |
| userDistanceMetres | Int? | user override; used when present |
| status | enum `inProgress, detected, recovered, confirmed` | only `confirmed` counts (D3) |
| classification | enum `unreviewed, business, personal, commuting, excluded` | commuting/personal/excluded never count |
| classificationSource | enum `user, rule, default` | `rule` and `default` pre-fill; only the user confirms |
| ruleID | UUID? | which rule classified it |
| purpose / customerName / notes | String? | |
| source | enum `detected, recovered, manual, assisted` | assisted = Shortcuts/CarPlay trigger |
| detectionVersion | String | TripDetection build that produced it (frozen-package audit) |
| routePolyline | Data? | simplified (Douglas–Peucker, ~25 m tolerance), for the map |
| pointsPurgeAfter | Date? | see 2.4 |
| mergedIntoID | UUID? | split/merge history |

**Duplicates** (council D6) are removed in code after every local write and every CloudKit import:
1. **The same ID** arriving twice through sync: merge, newest `updatedAt` wins.
2. **The same drive recorded twice:** two trips are treated as one when their time ranges overlap by more than 50% of the shorter trip, whatever device or source they came from. The winner is picked the same way on every device:
   1. a confirmed or manual trip beats a detected one, and a detected trip beats a recovered one;
   2. on a tie, the trip with the earliest `createdAt` wins;
   3. if that also ties, the lowest UUID wins.

   The loser is marked `mergedIntoID` and kept, never silently deleted. If the loser was confirmed, its classification and purpose are copied onto the winner first, unless the winner already has its own. A trip is never merged into a trip that has itself been merged; the chain is followed to its root first. Because the result is the same on every device, two phones importing each other's copy reach the same answer.
3. **What counts:** RateEngine input, totals, exports and the review list all **exclude any trip with `mergedIntoID` set**.
4. **Totals** are calculated, never synced, so a duplicate that slips through for a moment can't corrupt a stored total.
5. **Profile** is meant to be a single row, but CloudKit has no unique constraints, so two phones can each create one. The oldest `createdAt` wins, then the lowest UUID. Fields set only on the losing row are copied across before it is tombstoned.

**RoutePoint** (`LocalOnly`): `journeyID, timestamp, lat, lon, horizontalAccuracy, speed?`, batch-inserted and deleted at purge. Because it never syncs, a second device shows only the simplified route.

**Place** — `id, name, kind (home|work|customer|other), centre lat/lon, radiusMetres (100–500)`.

**ClassificationRule** — `id, placeID, direction (to|from|either), classification, enabled`. Paid feature.

**ClaimSnapshot** — `id, periodStart, periodEnd, rulesetID, rulesVersion, thresholdScope, apportionmentMethod, currency ("GBP"), totalMinorUnits, carVanMiles, motorcycleMiles, figuresJSON, tripIDsHash, createdAt, reason (export|markedFiled)`.

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
| Raw route points | **on the phone only**, until **30 days after the trip is confirmed** (or 60 days if it's never confirmed), then deleted | needed to re-measure, split or fix a distance while the user is reviewing. Once they're gone, a trip can't be re-measured, and future features that need detail (CO₂, fuel) can't be rebuilt for old trips |
| Simplified polyline | life of the record (user can turn off in Settings → Privacy) | shows the route on the map; supports the record if challenged |
| Start/end coordinates at 4 dp + labels | life of the record | the journey record itself |
| Tracking log | 7 days rotating, on device only | diagnostics |

User controls: delete a journey. It is tombstoned at once and removed after 30 days; how tombstone removal propagates through CloudKit is **(verify)**, delete all location detail (keeps miles, drops polylines/points), export everything (JSON + CSV), delete everything.

## 2.5 Future server schema (Supabase/Postgres) — not built in v1

Mirrors the local schema with `user_id uuid not null references auth.users`, plus:

```sql
alter table journeys enable row level security;
create policy "own rows" on journeys
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
-- same policy on vehicles, places, rules, snapshots
-- route_points: not uploaded at all by default
```

**Sync design when the backend arrives:** each row is owned by the device that wrote it. Rows are upserted by UUID, the newest `updated_at` wins, deletions travel as tombstones, and repeating an upload is harmless because IDs are made on the device. Accountants get read access to snapshots through a separate `shares` table, never to raw journeys.

**Decide this before building the portal:** "upload-only" sync means edits made on the web can't flow back to the phone. Two-way sync needs one sync owner, either CloudKit or Supabase, not both. A cheaper way to test whether accountants want a portal at all, in v1.1 with no backend, is a read-only share of the figures: a PDF or CSV the user sends, or a `CKShare` of the snapshots.
