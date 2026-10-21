# carriage
Carriage — a typewriter writing app for iPhone Duo: paper on top, keys below

Half-fold the Duo and it becomes a tiny typewriter: a sheet of paper scrolls on the top half, a round-key typewriter keyboard fills the bottom. See [SPEC.md](SPEC.md) for the product spec and [docs/LAUNCH.md](docs/LAUNCH.md) for what's left before submission.

## Build

Open `Carriage.xcodeproj` in **Xcode 27.1** (the iOS 27.1 SDK is required for the Duo's inner screen and hinge APIs) and run the `Carriage` scheme. The scheme uses `Carriage.storekit`, so purchases work locally without App Store Connect.

Tests: `⌘U`, or

```bash
xcodebuild -project Carriage.xcodeproj -scheme Carriage -destination 'platform=iOS Simulator,name=iPhone 17' test
```

FoldKit has its own tests: open `Packages/FoldKit` or run `xcodebuild -scheme FoldKit test` inside it.

## Layout

| Folder | What's there |
| --- | --- |
| `Carriage/App` | App entry, `AppModel` (shared state), share sheet, debug demo content |
| `Carriage/Engine` | `TypewriterEngine` (keys → ink, sound, haptics, carriage), goals and streaks, focus timer, spell-check underlines |
| `Carriage/Paper` | The sheet: TextKit 2 text view, ink texture, platen, scale, type guide, carriage motion |
| `Carriage/Keyboard` | The typewriter keys, drawn by the app |
| `Carriage/Sound` | Sound synthesis and the low-latency `AVAudioEngine` player, haptics |
| `Carriage/Typewriter` | The main screen and the layout for each posture |
| `Carriage/Library`, `Settings`, `Store`, `Export` | Library, notebooks, version and writing history, settings, StoreKit 2 and the unlock, TXT/Markdown/PDF/image export |
| `Carriage/Duo` | Duo-only touches: the fold-shut cover, the outer-screen glance, the two-page reading spread |
| `Carriage/Focus`, `Onboarding`, `Intents`, `Files` | Writing focus and its Focus Filter, the first-run tour and tips, Siri and Shortcuts actions, the Markdown copy in Files, widget data, on-device crash reports |
| `CarriageWidgets` | Home and Lock Screen widgets for today's words and the streak |
| `Packages/FoldKit` | The shared fold-posture helper for Carriage, Grid Fleet and Firstlight |

## FoldKit

`FoldMonitor` publishes one `FoldState` (posture, hinge angle, the fold line, hardware keyboard). Add `.foldProbe(monitor)` to the view that fills the window and lay out from `monitor.state`. Folding is a trait change, so views keep their identity and state.

The hinge (`UIHingeInteraction`) and fold-line (`reservedRegions(kind: .division)`) code only compiles against the iOS 27.1 SDK; it's gated on UIKit's version, so the package also builds on 27.0. Without a hinge, `FoldMonitor.simulation` fakes every posture for simulators, screenshots and tests.

## Debug launch arguments

| Argument | Effect |
| --- | --- |
| `-foldSimulation halfOpen` | Fake a posture: `regular`, `closed`, `halfOpen`, `flat`, `flatBook` (also in Settings › Developer) |
| `-seedDemo` | Fill an empty library with sample pages and two weeks of writing history |
| `-unlocked` | Act as if the unlock is bought, for screenshots |
| `-lampHour 21` | Light the desk lamp for that hour |
| `-engraving "J. Lee"` | Engrave a name on the plate |
| `-hardwareKeyboard` | Act as if a hardware keyboard is attached |
| `-uiTesting` | Use an in-memory store |
| `-seedLongPage` | Start with a 20,000-word page, for checking speed |
| `-screenshotScene library\|focus\|paywall` | Open straight into a scene, for screenshots |
| `-resetOnboarding` | Show the first-run tour again (`-onboardingPage 2` opens it on a card) |
| `-laptopPreview` | Lay out as a Duo turned on its side (fold across), for screenshots; Device Hub holds it like a book |

## Screenshots and store listing

`scripts/screenshots.sh "iPhone 18 Pro Max"` builds the app and captures the App Store set into `docs/screenshots/`. The listing copy is in [docs/APP_STORE.md](docs/APP_STORE.md); privacy and support pages are in `docs/site/`.

## Sounds

Every sound is synthesized on device (`TypewriterSynth`), so there's nothing to license. To use real recordings, add files named `<machine>-<kind>-<n>.wav` (for example `portable-key-1.wav`) to the app target; they replace the synthesized takes automatically.
