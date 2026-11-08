# 4. Navigation, screens and design system

## 4.1 Navigation

`TabView` with four tabs: **Today** (dashboard), **Journeys**, **Reports**, **Settings**. Each tab has its own `NavigationStack`, with a typed route enum per tab so deep links from the widget, Live Activity and notifications work. Modal sheets are used for quick classify, add a missed drive, and the paywall.

The spec names the first tab "Dashboard". This proposal calls it **Today**, because its first job is "what do I need to do now?"

## 4.2 Screens

### Onboarding (target: under 2 minutes, no sign-up)
1. **Welcome:** "Business mileage without the paperwork." Three bullets: automatic, private (no account), ready for your accountant.
2. **Your vehicle:** car/van or motorcycle; nickname; registration optional; "Do you claim actual costs or capital allowances on this vehicle?" Yes shows a warning that flat rates may not apply.
3. **Your year:** "When does your accounting year end?" Defaults to 5 April, with 31 March and Other as options.
3a. **Home (optional, free):** "Where's home?" This lets the app spot commuting. Places are free for everyone; only *rules* are paid.
3b. **Tracking phone** (only when another phone already tracks): "Track trips on this iPhone?" (§2.2).
4. **Location, explained before the system prompt:** what is tracked (only drives), when, where it stays (your phone and your iCloud), and why Always is needed ("While Using may miss trips"). Then the While Using prompt, followed by the upgrade to Always prompt. iOS decides when the Always prompt actually appears **(verify the iOS 18 timing)**.
5. **Motion & Fitness prompt**, explained first: it tells driving from walking, which saves battery.
6. **Notifications prompt**, explained first: it's used to ask you to review a trip, never for marketing.
7. **Done:** "Go for a drive. Your first trip will appear here." Optional: set Home and work places, or set up assisted mode.

Business name and business type are asked later in Settings, or the first time an accountant PDF is generated. They aren't needed to log trips.

### Today
- **Review card (top, only when needed):** "3 trips to review." Swipe right for Business, left for Personal, tap for details.
- **Sync health line** (shown only when there's a problem): "iCloud is off. Your trips are only on this iPhone. Export a backup."
- **Tax-year card:** business miles for the accounting period (everyone), the £ claimed so far (paid users), a progress bar to 10,000 miles showing the 55p and 25p bands, and "8,214 miles left at 55p". A provisional badge appears if the rates are unconfirmed; the rate-split note appears only when `needsRateSplit`.
- **Tracking health line:** "Tracking on". Warning variants: "Location set to While Using — trips may be missed", "Precise Location off", "Last trip detected 9 days ago".
- **Recent trips:** the last five.
- **This month:** business vs personal miles (a bar).

### Journeys
- A list grouped by day, with a status chip (Unreviewed, Business, Personal, Commuting, Excluded, Recovered).
- Filters: status, classification, vehicle, date range. Search covers labels, customer and purpose.
- **Journey detail:** map with route; start/end labels and times; miles (with "estimated" when it applies); vehicle; classification; purpose; customer; notes; the rule that applied, if any. Actions: Merge with next, Split here (tap the map), Delete, and Edit miles (the measured value is kept and shown).
- **Add missed drive:** from, to, date and time, miles (with an `MKDirections` suggestion), vehicle, purpose.

### Reports
- Choose a period: this accounting year, a previous year, a month, a quarter, or a custom range.
- Preview: total, bands, per-tax-year rows, excluded vehicles, unconfirmed trips left out.
- Export: FreeAgent CSV, generic CSV and PDF summary. Which of these are free is decided in README decisions D-B and D-E. Accountants get the figures as a PDF or CSV the user sends; they can't sign in in v1.
- Each export writes a ClaimSnapshot.

### Settings
Vehicles, Places & rules, Accounting year, Tracking (status, assisted mode, diagnostics export), Privacy (route detail on/off, delete location detail, export all data, delete all data), Subscription, About, and "This app is not tax advice".

### Widget and Live Activity (Should: in v1 if time allows)
- **Widget:** "1,234 business miles · 2 to review". It shows £ only for paid users. Tapping it opens the review screen.
- **Live Activity during a trip:** elapsed time and miles so far, with an End trip button. iOS generally lets an app start a Live Activity only while it is on screen, and starting one remotely needs a push server, which v1 doesn't have. So a Live Activity can appear only for trips started with the app open or through assisted mode, not for trips detected in the background. Whether one can start from an App Intent run by a Shortcuts automation is also **(verify)**. Both cases are on the Phase 1a device check.

## 4.3 Design system (phase 1 deliverable; outline here)

| Token group | Proposal |
|---|---|
| Colour | System backgrounds; one accent (deep green, the "money" colour); semantic colours business = accent, personal = secondary label, warning = system orange, error = system red. All defined in an asset catalogue with light and dark variants. |
| Type | SF Pro Dynamic Type styles only. Money uses `.monospacedDigit()` so totals don't jitter. |
| Spacing | 4-point scale (4, 8, 12, 16, 24, 32); 16 pt screen margins. |
| Components | `TripRow`, `ClassificationChip`, `MoneyText`, `BandProgress`, `HealthBanner`, `EmptyState`, `PrimaryButton`, `SwipeToClassify`. |
| Accessibility | Every swipe action is also a button; VoiceOver labels say "Business trip, 12.4 miles, High Street to Leeds". Layouts are tested at accessibility text sizes. |
| Motion | System springs only; honour Reduce Motion. |

Wireframes are low-fidelity and come as SwiftUI previews in phase 1, not separate image files, so they can't drift from the code.
