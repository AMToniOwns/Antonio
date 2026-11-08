# 5. Security and privacy assessment

## 5.1 Data inventory (v1, local-first)

| Data | Where | Sensitivity | Retention |
|---|---|---|---|
| Route points | **device only, never synced** | **High.** Reveals home, customers and routine. | 30 days after a trip is confirmed (60 if it never is). In plain English: the app keeps your detailed GPS trail for about a month after you review a trip, so you can fix it. After that, only a simplified route line and the start and end points remain. |
| Simplified route, start/end coordinates and labels | device and iCloud | High | Life of the record. The user can delete the location detail. |
| Trip times, miles, classification, purpose, customer | device and iCloud | Medium (business record) | Kept until the user deletes it. HMRC says to keep records for 5 years after the 31 January filing deadline. Settings shows this guidance; nothing is auto-deleted. |
| Vehicle, places, year end | device and iCloud | Medium | Kept until deleted. |
| Tracking log | device only | Medium | 7 days, rotating. Leaves the device only when the user exports it. Once a log is sent to support, Mile Log is the controller of that copy. It is deleted 90 days after the issue is closed, and the privacy policy says so. |
| Detection test-run data | developer only | High | Collected under a signed tester consent notice. Deleted 90 days after the go/no-go decision, except anonymised fixtures a tester has approved (§3.6). |
| Purchases | Apple | — | Mile Log never sees payment details. |
| Analytics (if opted in) | the chosen provider | Low | Counts only: no coordinates, no labels, no IDFA. |

## 5.2 Controls

- **Consent:** each system prompt is preceded by a plain-English explanation screen. Always location is asked for only after the user understands why. Analytics are opt-in.
- **At rest:** the Core Data store uses `NSFileProtectionCompleteUntilFirstUserAuthentication`, the strongest class that still lets a background relaunch write. Coordinate fields use CloudKit's `allowsCloudEncryption`. Whether Advanced Data Protection makes them end-to-end encrypted is **(verify)**. If iCloud is off or full, the app says so and offers a local export (§3.4).
- **In transit:** the app makes no network calls of its own in v1, apart from Apple services (CloudKit, StoreKit, MapKit geocoding and directions).
- **Secrets:** none ship in the app. A future backend uses the Supabase anon key with RLS only; the service-role key never ships. The pipeline keeps signing keys and the App Store Connect API key in GitHub Actions encrypted secrets, and keeps environment-specific configuration in `.xcconfig` files that hold no secrets.
- **User rights (UK GDPR):** in-app data export (JSON plus CSV), deletion of all data (local and iCloud), and deletion of location detail only. There's no account to delete in v1.
- **Privacy policy and App Store privacy label:** "Data Not Collected" is achievable in v1 if analytics are off, or "Not linked to identity" if they're on. This is a marketing asset; keep it.
- **Location purpose strings:** specific and honest ("Mile Log uses your location in the background to detect drives and measure their distance. Your trips stay on your iPhone and in your iCloud.").

## 5.3 Compliance and positioning risks

| Risk | Mitigation |
|---|---|
| Implying HMRC approval or MTD compliance | Neither "HMRC" nor "MTD" appears in the title or subtitle (council). Copy says "uses HMRC's published mileage rates". An in-app and PDF footer says it's a mileage record, not tax advice. |
| Wrong tax figures | The rate engine is tested and council-reviewed. The six open accountant questions must be answered before launch. Exports name the rules version, the threshold scope and the apportionment method. |
| App Review questioning Always location (likely on a first submission) | Allow a week of review buffer (§6.4). Background location must be core functionality, which it is. The onboarding explanation, the background indicator, and no location use outside trips all support the case. |
| A future backend (when it comes) | DPIA before launch; RLS on every table; no route points on the server by default; Supabase project in an EU or UK region; accountant access to snapshots, not raw journeys. |

## 5.4 Threat model highlights

- **Lost or stolen phone:** covered by iOS data protection. The app adds no Face ID lock in v1 (low value, adds friction); it could be offered later.
- **iCloud account compromise:** outside the app's control. The location-minimisation policy limits what's exposed.
- **A malicious rates-file update:** the rates file ships inside the app binary, is versioned and is validated at load. There's no remote rates fetch in v1.
- **A third-party SDK leaking location:** v1 has no third-party SDKs (StoreKit 2, MapKit and CloudKit only; analytics optional).
