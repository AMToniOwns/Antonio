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

**Profile** (one logical row; see duplicates rule 8)
`id, displayName?, businessName?, businessType (enum), accountingYearEndMonth, accountingYearEndDay, homePlaceID?, onboardingCompletedAt?, analyticsOptIn (Bool), rulesetID ("uk-hmrc-flat"), distanceUnit (miles|km), trackingDeviceID, trackingDeviceName`, plus a `…SetAt` date for each field the user can set (used by rule 8)

`rulesetID`, `timeZoneID` and `currency` cost nothing now and keep other countries possible later.

**Tracking device.** `trackingDeviceID` names the one phone that detects trips, so someone with two iPhones on one Apple ID doesn't log every drive twice.
- **The device ID** is a random UUID made on first launch and stored in the **Keychain** with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Because of that setting, it isn't carried over when a backup is restored to another phone. It isn't `identifierForVendor` either. Expected behaviour, all **(verify)**:
- Keychain items usually survive deleting and reinstalling the app, so a reinstall keeps the same device.
- A restore onto the *same* phone keeps it.
- A restore or migration to a *new* phone doesn't, so the new phone counts as a new device. That's the case this design is for.
- **Names:** the user names each phone (default "This iPhone"). On iOS 16 and later, `UIDevice.name` returns only the model ("iPhone") unless the app holds a special entitlement **(verify)**, so it isn't relied on. Both the ID and the name are stored in Profile (`trackingDeviceID`, `trackingDeviceName`).
- **When the app is opened**, if this phone isn't the tracking device, it asks: "Track trips on this iPhone? *Work iPhone* will stop." The choices are **Switch** and **Keep using Work iPhone**. A choice to keep the other phone is remembered on this phone, and the question then lives in Settings → Tracking. A brand-new install takes the role silently only once the first CloudKit import has finished (rule 8) and shows no other tracking phone.
- **Today's health line:** "This iPhone isn't tracking trips — *Work iPhone* is. Tap to switch." It replaces the slow "last trip 9 days ago" warning as the first sign after a phone upgrade.
- **The old phone** stops its wake layer *eventually*, after it imports the change. Silent pushes are throttled, so this can take a while. Until then, rule 2's deduplication prevents double counting.

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
| mergedIntoID | UUID? | set only by a *user* merge (history); never by deduplication |
| userEditedFields | [String] | fields the user changed by hand (late-edit rule 6, Profile-style protection) |

**Duplicates** (council D6). Two different things are kept apart here. A *user merge* is something the user does, and it is stored. *Deduplication* is something the app works out, and it is **never stored in a synced field**. Keeping the two apart is what stops two phones from fighting over which copy is the duplicate.

1. **The same ID arriving twice through sync.** The container uses `NSMergeByPropertyObjectTrumpMergePolicy`, so conflicting writes are resolved property by property and the newest write wins. How CloudKit imports interact with that policy is **(verify)**.
2. **Duplicates are matched in pairs and worked out fresh on every pass; nothing is stored.** After every local write and every CloudKit import, the app checks pairs of trips. Two trips are duplicates only when **each covers more than 50% of the other's time range** (mutual overlap). Matches don't chain: trip A matching B, and B matching C, does not make A and C duplicates. Deleted, `inProgress` and user-merged trips are skipped.

   **The full order** sets which copy wins and gives every trip a strict place:
   1. category: confirmed beats manual, manual beats detected or assisted, and those beat recovered;
   2. within a category, the earliest `createdAt`;
   3. then the lowest UUID.

   "Outranks" always means "earlier in the full order", tie-breaks included, so no two trips ever rank equal.

   A trip is suppressed only by a partner that outranks it. If it matches several such partners, the largest overlap wins, then the full order. A suppressed trip's representative is found by following "suppressed by" links up to a trip that isn't suppressed. Each link points to a trip that outranks the one before it, so the chain always ends, and every suppressed trip resolves to exactly one representative.

   The result lives only in a `LocalOnly` cache, `suppressedBy`, which is rebuilt from scratch each time.
3. **Coverage by several trips.** A trip can be covered by several shorter trips without a pairwise match. Examples: a long recovered trip spanning two confirmed drives, or another phone's unsplit copy of a drive this phone split in two. Coverage is the **union of the time ranges** (not the sum) of the trips that **outrank it** in the full order and aren't themselves suppressed. When that union covers more than 50% of the trip's time range:
   - if the covered trip is **unconfirmed**, it is suppressed;
   - if it is **confirmed**, it is flagged "Possible duplicate — check" and **not counted** until the user keeps or deletes it.

   This can only make a claim smaller, never larger.
4. **Conflicting confirmations.** Two confirmed copies in one pair disagree when their classification or vehicle differs, or their miles differ by more than 5%. A different vehicle matters because cars and motorcycles have different rates. If only the purpose or notes differ, the representative's are kept, and the other copy's text is shown on the trip detail under "Other copy said…". They then count for nothing until the user picks one ("2 copies of a trip disagree — choose one"), and the choice tombstones the other copy. Within that tolerance, the representative wins silently. A class pre-filled by a rule or a default never counts as a confirmation.
5. **What each screen uses.**
   - **Counted** (RateEngine, totals, exports): confirmed representatives and confirmed unmatched trips, but not trips flagged under rules 3 or 4.
   - **Review list:** unconfirmed representatives and unconfirmed unmatched trips, plus anything flagged under rules 3 or 4.
   - Suppressed, user-merged and tombstoned trips appear in neither.
   - **Deleting a representative** asks "Delete both copies?", so the suppressed copy can't quietly start counting again.
6. **User merge and split** are explicit and stored.
   - **Merge:** the earlier trip is extended. Its original end, distance and polyline are kept in a `mergeUndo` record, and the later trip is tombstoned with `mergedIntoID`.
   - **Merge undo:** restores the earlier trip from `mergeUndo` and un-tombstones the later trip. It's available while the tombstone exists, which is 30 days.
   - **Split:** the parent is tombstoned and two children are created, with time ranges that don't overlap.
   - **Split undo:** tombstones the children and restores the parent.
   - **Edits that arrive late:** an edit can sync in for a trip that is already merged away, for example a purpose set offline on the other phone. The app shows "An edit arrived for a merged trip". It copies the edit to the surviving trip for any field the user hasn't edited there. Journey keeps a `userEditedFields` set for this.
7. **Totals** are calculated, never synced, so a duplicate that slips through briefly can't corrupt a stored total.
8. **Profile duplicates.** CloudKit has no unique constraints, so two phones could each create a Profile.
   - **Avoid them:** on first launch with iCloud available, onboarding shows "Looking for your Mile Log data…" and waits for the first CloudKit import (up to 30 s). Only then does it create a Profile.
   - **If they happen anyway:** the oldest `createdAt` wins, then the lowest UUID. Each Profile field also has a `…SetAt` date. Any field the user set on the losing row, more recently than on the winner, is copied across before the losing row is tombstoned. Defaults never overwrite a choice the user made.
   - **Test:** a two-phone race (both offline, one confirms, one merges, then sync) is a required test in Phase 2.

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
