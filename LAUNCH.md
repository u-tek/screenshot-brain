# Launch checklist

Everything between "it builds" and "it's on the App Store". Tick as you go.

## 1. Accounts and keys (from the build brief, section 2)

- [ ] Apple Developer Program membership; team ID and bundle ID in `Config/Local.xcconfig`
- [ ] Identifiers registered: the app, `.share`, `.widgets`; App Group `group.<bundle ID>`;
      iCloud container `iCloud.<bundle ID>` (CloudKit)
- [ ] Capabilities on the app ID: Sign in with Apple, App Groups, iCloud (CloudKit),
      Background Modes (processing, fetch)
- [ ] CloudKit: deploy the development schema to production (record types `ItemState`,
      `Onboarding`, zone `ScreenshotBrain`) after one full sync in development
- [ ] Sign in with Apple key created; account endpoint deployed (`server/README.md`);
      `SB_ACCOUNT_SERVER_HOST` set
- [ ] App Store Connect products: yearly (7-day free trial), weekly, lifetime (non-consumable);
      RevenueCat project, `premium` entitlement, offerings per `docs/EXPERIMENTS.md`;
      `SB_REVENUECAT_API_KEY` set
- [ ] TelemetryDeck app ID in `SB_TELEMETRYDECK_APP_ID`
- [ ] Privacy policy page live; `SB_PRIVACY_POLICY_URL` and `SB_SUPPORT_EMAIL` set
- [ ] Confirm the share card's handle (`@screenshotbrain`) is ours, or change it in
      `Packages/SBKit/Sources/Reveal/ShareCard.swift`

## 2. Sign-offs (on real devices)

### Accuracy (M2)
- [ ] At least 10 test users run the debug "Was this right?" mode on 100+ screenshots each
- [ ] Per category accuracy from the debug screen: ship only categories at **95% or better**;
      remove the rest from `CategoryClassifier.shippedCategories` (they fall back to Other)

### Nudity filter (M3)
- [ ] `DisplaySurfaceTests` (nudity never appears anywhere; only safe items reach the widget, Reveal and shareables) green on CI
- [ ] On device: a set of flagged test images in Photos never appears in the Reveal, triage,
      the widget, Home, search or the share card
- [ ] Record the false-negative rate seen in testing in this file

### Performance (M2, M10)
- [ ] iPhone 8 on iOS 16: debug benchmark, first 60 screenshots in **15 s or less**
      (record the per-stage numbers here)
- [ ] iPhone 8: no dropped frames in the Reveal or triage (Instruments, Animation Hitches)
- [ ] Widget memory within limits on iPhone 8 (Xcode memory gauge on the widget extension)

### First open (M4)
- [ ] Full first open end to end on a real device with real screenshots, for each of: full
      access, limited access, Don't Allow (picker and share extension)
- [ ] Kill the app mid-onboarding and relaunch: it resumes; sign in on a second device: it resumes

### Everything else
- [ ] Every action on device: calendar (iOS 16 and 17+), Maps, shop, copy ingredients, send
- [ ] Batch delete goes through iOS's confirmation; declining leaves everything in place
- [ ] Widget: all four states render; Keep / Done / Drop work on iOS 17+; iOS 16 opens the item
- [ ] Notifications: one a night at most, specific copy, nothing on empty nights
- [ ] Sandbox: trial, purchase, restore and lifetime; the widget locks when premium lapses
- [ ] Account deletion removes CloudKit data and revokes the token (check the Apple ID's
      "Sign in with Apple" list)
- [ ] Dynamic Type at the largest sizes, VoiceOver through onboarding, the Reveal and triage,
      Reduce Motion, dark mode, iPhone SE

## 3. TestFlight plan

1. **Internal (week 1):** the team, on as many old phones as we can find. Accuracy mode on.
2. **External, small (week 2):** 25 people across both audiences (15–21 and 45+). Watch the
   funnel below; interview five.
3. **External, wide (weeks 3–4):** 200 people. Paywall live in sandbox. Fix, then submit.

## 4. App Store Connect

- [ ] Name, subtitle, keywords (never "organise", "sort", "manage" or "declutter")
- [ ] Description leads with "You saved it for a reason."
- [ ] Screenshots: 6.9" and 6.5", built from real Reveal cards and the widget
      (`design/screens/` holds the current renders)
- [ ] 30-second app preview recorded on a device
- [ ] Privacy labels: no data collected by us except anonymous usage counts (TelemetryDeck) and
      purchase history (RevenueCat); no tracking
- [ ] Review notes from `docs/APP_REVIEW.md`
- [ ] Age rating; the nudity filter is described in review notes

## 5. Analytics to watch

Event names are in `Packages/SBKit/Sources/Core/Analytics.swift`.

| Metric | From |
|---|---|
| Full-access rate | `photoAccess.full` ÷ (`photoAccess.full` + `.limited` + `.denied`) |
| Reveal completion | `reveal.completed` ÷ `reveal.started` |
| Triage completion | `triage.completed` ÷ `triage.started` |
| Widget added on day 0 | `widget.added` with `day = 0` ÷ onboarding completions |
| Recap open rate | `recap.opened` ÷ notifications scheduled |
| Actions per user per week | `action.*` per active user |
| Day 1 / 7 / 30 retention | TelemetryDeck retention |
| Trial starts and conversions | `purchase.trialStarted`, `purchase.completed`; RevenueCat |

## 6. Widget freshness: what the marketing copy can say

The brief asked whether a widget button could fetch and read the newest screenshot on the spot.
Reading a screenshot means Vision text recognition and a Core ML model, and a widget's App
Intent runs in the widget extension under its tight memory limit. That hasn't been prototyped on
a device yet, so v1 ships the version that certainly works: new screenshots reach the widget after
the background scan (`BGProcessingTask`) or the next time the app opens.

**Marketing copy: "tonight's screenshots", not "the screenshot you just took".**

If a device prototype shows an intent can read one screenshot inside the extension's limits on an
iPhone 8, revisit this.
