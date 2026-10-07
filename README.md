# Screenshot Brain

People screenshot things they mean to do later and never look at them again. Screenshot Brain reads those screenshots on the phone and helps them actually happen. **You saved it for a reason.**

iPhone only, iOS 16+, Swift and SwiftUI. Screenshots and their extracted text never leave the device.

## Getting started

```sh
brew install xcodegen
make open        # generates ScreenshotBrain.xcodeproj from project.yml and opens it
```

The project file is generated and not committed: edit `project.yml`, then run `make project`.

It builds and runs in the simulator as is. For a device build, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (gitignored) and fill in your team ID and bundle ID. The App Group (`group.<bundle id>`) and CloudKit container (`iCloud.<bundle id>`) derive from the bundle ID; register both in the developer portal.

| Command | What it does |
|---|---|
| `make test` | Runs every module's unit tests on an iPhone simulator |
| `make build` | Builds the app for the simulator, unsigned |

CI (`.github/workflows/ios.yml`) runs both on every push, on a macOS runner, plus the account server's tests on Linux.

Before the App Store, work through `LAUNCH.md`: keys, sign-offs on real devices, the TestFlight plan and the analytics to watch.

## Design

The look is "Mist and light": see `design/REFERENCES.md`. Light is made like it is in a design tool: a closed shape, filled with one gradient (stops interpolated in OKLab), blurred with a Gaussian stretched along the direction of motion, composited in linear colour, plus faint grain. Glass is Liquid Glass on iOS 26 and frosted material before.

Screens are exported from the real app by CI. Put `[snapshots]` in a commit message (or run the workflow by hand) and CI commits PNGs to `design/screens/<device>/` and the design lab pages to `design/lab/`. Routes live in `scripts/snapshot-routes.txt`.

| Path | What's there |
|---|---|
| `design/references/` | The reference images; `00-north-star.jpg` is the target |
| `design/lab/` | Design lab pages and the two north-star rebuilds, light and dark |
| `design/compare/` | Each rebuild beside the north star |
| `design/screens/` | Every screen on iPhone 16 Pro and iPhone SE |
| `design/appstore/` | App Store screenshots at 6.9", built from the real screens |
| `design/system.png` | The design system sheet (`python3 design/tools/system_sheet.py`) |

CI also uploads the simulator build as the `ScreenshotBrain-simulator` artifact: unzip it and run `xcrun simctl install booted ScreenshotBrain.app`.

## Layout

| Path | What's there |
|---|---|
| `App/` | The app target: entry point, the app model, every screen |
| `ShareExtension/` | "Share to Screenshot Brain", for people who don't give photo access |
| `Widgets/` | Home and Lock Screen widgets, with Keep / Done / Drop intents |
| `server/` | The Sign in with Apple token endpoint (Cloudflare Worker) for account deletion |
| `docs/` | App Review notes and the paywall experiment |
| `Packages/SBKit/` | Every module, as one Swift package with a target per module |
| `Config/` | xcconfig files: identifiers and service keys |
| `design/` | Reference notes, design lab exports, comparisons and screen snapshots |
| `scripts/` | Build helpers |

### Modules

| Module | Responsibility | Milestone |
|---|---|---|
| `Core` | Configuration, App Group paths, logging, analytics, domain types | M1 |
| `Store` | GRDB database in the App Group container: models, migrations, queries | M1 |
| `DesignSystem` | Tokens, light, glass and components | M1 |
| `ScanEngine` | Fetching, text recognition, entity detection, classification, grouping | M2 |
| `Safety` | Nudity filter and sensitive-text detection | M3 |
| `Reveal` | Stats and the story UI | M4 |
| `Triage` | The swipe deck | M5 |
| `Actions` | Calendar, Maps, shop, copy ingredients, send | M5 |
| `Notifications` | Nightly recap, nudges, digest | M7 |
| `WidgetCore` | What the widget shows and when: ordering, rotation, states | M6 |
| `Paywall` | RevenueCat premium tier | M8 |

Dependencies run one way: `Core` ← `Store` / `Safety` ← `ScanEngine` and the feature modules ← the app.

## Privacy rules the code relies on

- Screenshots, extracted text and detected entities stay on the device. The database and thumbnails live in the App Group container and are excluded from device backups. Only metadata (item states keyed by a hash of the Photos cloud identifier, onboarding answers, the recap time) syncs through the user's private CloudKit database.
- Notifications name an item only when it's safe to display; anything else is described by its category.
- Analytics are event counts only. `Analytics.track` accepts integer parameters, so content can't be sent by accident.
- An item is not safe to display until the Safety module says so. `ScreenshotItem.isSafeToDisplay` defaults to `false`.
