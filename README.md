# EVE

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![iOS 26.2+](https://img.shields.io/badge/iOS-26.2%2B-black)
![RevenueCat](https://img.shields.io/badge/RevenueCat-SDK%205.90-F25A5A)

**EVE remembers the small things you always forget, like your keys, your earphones, your
charger, and reminds you at the moment you need them.** It learns your routine on-device and
nudges you when the moment fits, not at a fixed time. Built by a team of five at the Apple
Developer Academy and submitted to RevenueCat Shipaton 2026 (Next Gen Award).

▶️ **Demo video:** _VIDEO_URL_ (under 2 minutes, recorded on an iPhone 17)

EVE is built for *micro-reminders*: small, easily forgotten actions whose value depends
entirely on the right moment. Your keys as you walk out the door, your earphones before the
gym, your charger before a long day, your medication after breakfast. Instead of firing a
fixed daily alarm, EVE learns your routine from your calendar and the places you go, waits for
the moment that actually fits, and nudges you then. The loop is always the same:

**learn the routine → detect the right moment → deliver an adaptive nudge → learn from
the response.**

## Why it exists

Fixed-time, repeating reminders fail exactly the people who need them most. If you
struggle with prospective memory (remembering to do a thing *later*), a notification
that arrives at 6:00 PM every day becomes noise you swipe away without reading.

We settled on people with ADHD and executive dysfunction as our primary audience, and
that shaped everything after: one clear action per screen, tap-based feedback instead of
typing, and a calm interface with little visual load.

## What it does

- **Learns from your calendar.** During onboarding, EVE reads your calendar and uses Apple's
  on-device Foundation Models to learn patterns in your week, then asks a few yes/no
  questions about your own events.
- **Prepares you for what's coming.** For each calendar event, EVE writes a few concrete
  prep items (things to bring, prepare, or check) and schedules them an hour before.
  Today's reminders appear on Home, grouped by part of the day.
- **Tells you what matters now.** A suggestion bubble on Home shows the single most useful
  thing to do next, and refreshes when your location, reminders, or the time changes.
- **Knows where you are.** Pin reminders to saved places, triggered when you arrive or leave.
- **Learns from your response.** Notifications offer one-tap *Done*, *Too Early*, and
  *Too Late*, which shift when future reminders fire.
- **Shows its work.** The Insights screen lists what EVE believes about your routine, in plain
  sentences you can edit or delete.

## Stack

Everything except the purchase flow runs on-device. We made a deliberate decision not to
introduce any third-party model or cloud AI runtime, so that what we learned would be
about Apple's frameworks rather than about someone's API.

| Framework | Role |
|---|---|
| **Foundation Models** | The reasoning core: reads context and produces structured output |
| **Natural Language** | Language detection, so non-English text stays out of prompts the model can't handle reliably |
| **EventKit** | Calendar, the passive timeline EVE learns from |
| **CoreLocation** + **MapKit** | Arrivals and departures, place search, travel-time estimates |
| **UserNotifications** | Delivery channel for nudges and one-tap feedback |
| **SwiftData** | Long-term memory. The model is stateless, so insights persist here |
| **SwiftUI** | The entire UI |
| **RevenueCat** (`purchases-ios-spm` 5.90.2) | EVE Plus: paywall, purchase, restore, entitlement, Customer Center |

## Requirements

| | |
|---|---|
| Mac | Xcode **27.0** or later (verified with Xcode 27.0, build 27A266a) |
| iPhone | **iOS 26.2 or later.** For the AI features, an iPhone that supports **Apple Intelligence**, with Apple Intelligence turned on in Settings |
| Accounts | A free Apple ID in Xcode to sign the app for your own device. **No** paid developer account, App Store Connect setup, or RevenueCat account needed |

Without Apple Intelligence the app still runs: onboarding explains what's missing and
falls back to a fixed set of questions instead of AI-generated ones. The adaptive insights
and prep lists need the on-device model.

## Run it on your iPhone

1. Clone the repo and open the project (it lives one folder down, in `eve/`):
   ```sh
   git clone https://github.com/cabbbbsss/EVE.git
   open EVE/eve/eve.xcodeproj
   ```
   Xcode resolves the RevenueCat Swift package automatically. The version is pinned by
   the committed `Package.resolved`.
2. Select the **eve** target → **Signing & Capabilities**:
   - set **Team** to your own (personal) team;
   - change **Bundle Identifier** from `com.eve.ch4app` to something unique, e.g.
     `com.<yourname>.eve`.
3. Plug in your iPhone, select it as the run destination, and press **Run (⌘R)**.
   - Keep the default **Debug** configuration. The app ships with a RevenueCat
     *Test Store* key, and the RevenueCat SDK deliberately crashes a **Release** build that
     uses one, so don't use *Archive* or a Release scheme.
   - First time on a device: enable **Developer Mode** (Settings → Privacy & Security),
     then trust your developer certificate (Settings → General → VPN & Device
     Management).
4. In EVE, allow Calendar access during onboarding, and Location and Notifications when EVE
   asks later. EVE learns from your real calendar, so it has more to work with if the
   calendar has a few events this week.

### Command-line build (no device, compile check only)

```sh
cd EVE/eve
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project eve.xcodeproj -scheme eve \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/dd-eve \
  CODE_SIGNING_ALLOWED=NO build
```

Set `DEVELOPER_DIR` explicitly. If the active toolchain is `CommandLineTools`, it cannot
expand macros, and `@Model` / `@Generable` / `@Observable` will fail to compile. Point
`-derivedDataPath` outside the repo so you get a genuine clean build.
`CODE_SIGNING_ALLOWED=NO` lets the compile check run without the team's signing identity.

## RevenueCat: EVE Plus

EVE's free tier keeps the core benefit (adaptive reminders, local privacy, feedback)
because the people EVE is for shouldn't hit a wall before it helps them. **EVE Plus** is for
people who want EVE more deeply in their life.

| | |
|---|---|
| Entitlement | `eve_pro` (the app gates on the entitlement, never on a product ID) |
| Unlimited places | Free accounts keep **1** saved place; EVE Plus is unlimited. Tapping **+** on the Locations screen at the limit opens the paywall, and the add flow resumes after purchase |
| Personalized prep | Each event's prep list draws on what EVE has learned about you: confirmed answers, insights, and what you did before similar events |
| Contextual learning | Before an upcoming event, EVE deduces what you might need ("Gym coming up. Should I remind you to bring your gloves?") and asks |
| Paywall | RevenueCat-hosted `PaywallView`, laid out from the dashboard's current offering (Annual and Quarterly) |
| Manage | Settings → EVE Plus: membership status, Upgrade, **Restore Purchases**, and RevenueCat **Customer Center** for subscribers |
| Where | [`SubscriptionService.swift`](eve/eve/Services/SubscriptionService.swift) is the only file that talks to `Purchases`; [`PaywallSheets.swift`](eve/eve/Views/PaywallSheets.swift) holds the paywall and Customer Center |

Entitlement changes arrive through RevenueCat's customer-info stream, and every Plus feature
reads the entitlement when it runs, so a purchase unlocks Plus immediately with no relaunch.

### For judges: unlocking EVE Plus

No promo code is needed. The build is wired to RevenueCat's
[**Test Store**](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store) with a
public `test_…` SDK key, so purchases are simulated and no money moves:

1. Run the app from Xcode (Debug) as described above.
2. Open **Settings → EVE Plus → Upgrade to EVE Plus**, or tap **+** on the **Locations**
   screen after saving one place.
3. Pick a package on the paywall. RevenueCat shows a Test Store dialog. Choose
   **Test valid purchase**.
4. The `eve_pro` entitlement activates immediately: Settings shows your membership, the
   **PLUS** badge appears on Home, and you can save unlimited places.

The same dialog also lets you simulate a failed or cancelled purchase.

Test Store purchases belong to the anonymous RevenueCat user of this install. To start
over as a free user, delete the app and run it again. For the same reason, **Restore
Purchases** only re-reads the current user's entitlement under Test Store; it can't bring
back a purchase made on a previous install (a real App Store build restores through
StoreKit).

*Why a public SDK key in an open-source repo is fine:* RevenueCat's public SDK keys can only
read offerings and start purchases for this app. The secret key that can change subscriber
data never leaves the RevenueCat dashboard.

## Privacy and safety

- Calendar events, locations, learned routines, and reminder history are stored on the
  device in SwiftData.
- All AI reasoning runs on-device through Apple's Foundation Models. EVE sends none of
  your calendar or location data to any server.
- The only network traffic is RevenueCat's (offerings, purchases, entitlement status),
  keyed to an anonymous RevenueCat user ID.
- Model output is grounded: prep items and suggestions that name something absent from the
  context they were built from are dropped before you see them.
- Calendar text comes from other people, so it's marked as data (not instructions) on its way
  into a prompt, and those markers are stripped from everything the model returns.

## Known limitations

- AI insights need an Apple Intelligence iPhone with the model downloaded. Other devices
  get the non-AI fallback described above.
- Location-based nudges use iOS region triggers, so they can arrive a little after you
  actually arrive or leave.
- The build uses RevenueCat's Test Store; it isn't configured for App Store purchases.
- Designed and tested on iPhone; the UI and the AI features are English only.

## Project layout

The Xcode project is `eve/eve.xcodeproj`; all app source lives in `eve/eve/`.

```
eve/eve/
├── eveApp.swift      @main entry. Owns the SwiftData ModelContainer + Schema.
├── ContentView.swift Root router: onboarding vs. HomeView.
├── Models/           SwiftData @Model classes and the types they own.
├── Views/            SwiftUI screens and sheets.
├── ViewModels/       Per-screen @Observable state.
├── Managers/         Cross-cutting orchestration across several services.
├── Services/         One external capability each (EventKit, CoreLocation, RevenueCat, …).
└── AI/               Foundation Models prompting and context assembly.
```

## Team

| Who | GitHub | Built |
|---|---|---|
| **Caca**, Sabrina Salsabila Saleh | [@cabbbbsss](https://github.com/cabbbbsss) | AI backend architecture: SwiftData models and services, `FoundationModelService`, `ReminderContextBuilder`, `AssistantManager`, the onboarding questionnaire and learning pass, personalised insights. Wrote the tech report. |
| **Nanda**, Ketut Agus Cahyadi Nanda | [@Gusnand](https://github.com/Gusnand) | Initial app scaffold and Xcode project, `PermissionManager` and the Calendar/Location permission flow, base Location and Calendar screens, colour assets and dark mode, `InsightView` and its Foundation Models prompt, app icon. |
| **Dani**, Dani Muhammad | [@codeby-dani](https://github.com/codeby-dani) | Calendar screen (swipe paging, live now-line, AI-generated event reminders), Locations screen (filter chips, inline and map-based add, AI routing), History timeline, Settings revamp, per-category notification preferences, migration to the asset-catalog colour system. |
| **Amanda**, Amanda Dorotea Susanto | [@Amanda-ds96](https://github.com/Amanda-ds96) | `HomeView`, `WelcomeView`, `PermissionView`, the streaming `AILearningView` redesign, UI colour fixes. |
| **Keiko**, Keiko Serah | — | Design and research. |

## Further reading

[`Tech Report - Eve.md`](Tech%20Report%20-%20Eve.md) is the full challenge write-up: what
we explored, what we built and threw away, the limits we hit with on-device Foundation
Models, and how we arrived at this app.

## License

[MIT](LICENSE) © 2026 Sabrina Salsabila Saleh, Ketut Agus Cahyadi Nanda, Dani Muhammad,
Amanda Dorotea Susanto, Keiko Serah.
