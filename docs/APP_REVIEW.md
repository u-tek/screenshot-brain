# Notes for App Store Review

Paste the section below into App Store Connect → App Review Information → Notes.

---

**What the app does.** Screenshot Brain reads the user's screenshots and helps them follow
through on the things they saved: places, gigs, products and recipes. It shows a "Reveal" of what
they've been saving, a swipe deck to decide what to keep, one-tap actions (calendar, Maps, shop,
copy ingredients, send to a friend) and a home screen widget for ticking things off.

**Photo access.** The app asks for photo library access to read screenshots only (it fetches
assets with the screenshot subtype, from the last two months on first run). Everything works with
full access, with limited access (a Reveal built for a handful of screenshots), and with no access
at all: people can pick screenshots with the system photo picker, which needs no permission, or
share them in from Photos through the share extension.

**On-device processing.** All reading happens on the device: Vision text recognition, Apple's
data detectors, a rules-based classifier and a small Core ML nudity classifier. Screenshots, the
text read from them and anything detected in them never leave the device and are excluded from
device backups. There is no server that sees user content.

**Nudity filter.** Every screenshot is screened on device before anything can display it, using a
bundled 17 kB Core ML model (NSFWDetector, BSD-3-Clause) and, where the user has enabled it,
Apple's SensitiveContentAnalysis as an extra signal. A flagged screenshot is never shown anywhere
in the app, the widget, the Reveal or anything shareable, and its text isn't kept. Screenshots
with card numbers, bank details, passwords or one-time codes are kept out of the widget and out of
anything shareable.

**Accounts.** Sign in with Apple is used so progress syncs across the user's devices and survives
a new phone: what they kept, did and dropped, their onboarding answers and their recap time. This
metadata syncs through the user's own private CloudKit database. Screenshots and their text are
never synced. Account deletion is in Settings → Account → Delete account; it deletes the CloudKit
data, everything on the device, and revokes the Sign in with Apple token through Apple's REST API.

**Purchases.** One premium tier: yearly with a 7-day free trial, weekly, or lifetime. Premium
unlocks the widget, the all-time Reveal and full monthly stats; everything else is free. The
paywall shows the price, the renewal period and the trial terms next to the purchase button, and
"Restore purchases" is always visible there and in Settings.

**To try it.** Any device with a few screenshots works. With no screenshots, take two or three
of a restaurant page, an event listing and a product page first, then open the app.
