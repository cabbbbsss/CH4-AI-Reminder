# EVE

An on-device adaptive reminder assistant for iOS, built for Apple Developer Academy
Challenge 4.

EVE targets *micro-habits* — small, easily-forgotten actions whose value depends
entirely on the right moment: taking medication, refilling a water bottle, charging a
device, picking up groceries on the way home. Instead of firing a fixed daily alarm, it
learns your routine from your calendar and location patterns, waits for the moment that
actually fits, and nudges you then. The loop is always the same:

**learn the routine → detect the right moment → deliver an adaptive nudge → learn from
the response.**

## Why it exists

Fixed-time, repeating reminders fail exactly the people who need them most. If you
struggle with prospective memory — remembering to do a thing *later* — a notification
that arrives at 6:00 PM every day becomes noise you swipe away without reading.

We settled on people with ADHD and executive dysfunction as our primary audience, and
that shaped everything after: one clear action per screen, tap-based feedback instead of
typing, and a dark interface to reduce visual load.

## Stack

Everything runs on-device. We made a deliberate decision not to introduce any
third-party model or cloud AI runtime, so that what we learned would be about Apple's
frameworks rather than about someone's API.

| Framework | Role |
|---|---|
| **Foundation Models** | The reasoning core — reads context, produces structured output |
| **Natural Language** | Detects and translates non-English input before the model sees it |
| **EventKit** | Calendar and Reminders — the passive timeline EVE learns from |
| **CoreLocation** | Arrivals and departures, the sensory trigger for context |
| **UserNotifications** | Delivery channel for nudges and lightweight feedback prompts |
| **SwiftData** | Long-term memory — the model is stateless, so insights persist here |
| **SwiftUI** | The entire UI |

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
├── Services/         One external capability each (EventKit, CoreLocation, …).
└── AI/               Foundation Models prompting and context assembly.
```

## Building

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project eve.xcodeproj -scheme eve \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/dd-eve build
```

Set `DEVELOPER_DIR` explicitly: if the active toolchain is `CommandLineTools` it cannot
expand macros, and `@Model` / `@Generable` / `@Observable` will fail to compile. Point
`-derivedDataPath` outside the repo so you get a genuine clean build.

## Team

| Who | GitHub | Built |
|---|---|---|
| **Caca** — Sabrina Salsabila Saleh | [@cabbbbsss](https://github.com/cabbbbsss) | AI backend architecture — SwiftData models and services, `FoundationModelService`, `ReminderContextBuilder`, `AssistantManager`, the onboarding questionnaire and learning pass, personalised insights. Wrote the tech report. |
| **Nanda** — Ketut Agus Cahyadi Nanda | [@Gusnand](https://github.com/Gusnand) | Initial app scaffold and Xcode project, `PermissionManager` and the Calendar/Reminders/Location permission flow, base Location and Calendar screens, colour assets and dark mode, `InsightView` and its Foundation Models prompt, app icon. |
| **Dani** — Dani Muhammad | [@codeby-dani](https://github.com/codeby-dani) | Calendar screen (swipe paging, live now-line, AI-generated event reminders), Locations screen (filter chips, inline and map-based add, AI routing), History timeline, Settings revamp, per-category notification preferences, migration to the asset-catalog colour system. |
| **Amanda** | [@Amanda-ds96](https://github.com/Amanda-ds96) | `HomeView`, `WelcomeView`, `PermissionView`, the streaming `AILearningView` redesign, UI colour fixes. |
| **Keiko** | — | Design and research. |

## Further reading

[`Tech Report - Eve.md`](Tech%20Report%20-%20Eve.md) is the full challenge write-up: what
we explored, what we built and threw away, the limits we hit with on-device Foundation
Models, and how we arrived at this app.
