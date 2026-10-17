# Carriage — spec

Pitch: the half-folded Duo becomes a tiny typewriter, with a sheet of paper scrolling on the top half and a custom typewriter keyboard filling the bottom half. A distraction-free writing app for writers, journalers and students (Freewrite's $500+ device shows the market exists). Competitors: Hanx Writer, Typewrite, Write Only and My Typewriter, none of which support the Duo. The edge is the fold itself, plus polish and speed.

## Platform rules (all apps)
- Build with Xcode 27.1 and the iOS 27.1 SDK, or the app shows black borders on the inner screen.
- Draw only on the inner screen while open. Third-party apps get no general way to use the outer screen while open, and no API says which panel a window is on.
- Detect half-fold posture and the hinge with Apple's posture and trait APIs. Folding is a trait change, so the app stays alive and keeps its state.
- It must run well on regular iPhones too.
- From April 2027 every submission needs iPhone Duo screenshots.
- Shared stack: Swift and SwiftUI (UIKit where needed), support iOS 27+, SwiftData plus iCloud, StoreKit 2. One shared fold-posture helper is written once and reused in all three apps (Carriage, Grid Fleet, Firstlight).

## Layout by posture
- Half-folded (hero mode): paper with typebar animation and carriage on top, full custom keyboard on the bottom.
- Fully open and flat: paper on the left, keyboard on the right (or a full-width keyboard).
- Closed (outer screen): read and lightly edit drafts with the standard keyboard.
- Regular iPhone: paper plus a smaller custom keyboard.
- Hardware keyboard attached: full-screen paper, keyboard hidden, sounds and animation still play.

## MVP features
- Custom keyboard: the app draws its own key layout (not the system keyboard), with round keys and a press-down animation.
- Key sounds: separate samples for keys, space, the return bell and the carriage slide, with slight random pitch so it never sounds looped.
- Haptics: a short tap per key and a heavier thunk on return.
- Paper view: monospaced typewriter font, and the typing line stays at a fixed height while the paper scrolls up.
- Modes: Free mode (delete works) and Typewriter mode (no delete; strike through with x instead).
- Library: pages and drafts, auto-saved, with iCloud sync.
- Export: plain text, Markdown, a PDF styled as a typed page, the share sheet, and copy to Notes.

## Later
- v1.1: word goals and streaks; paper and ink styles as a paid pack (cream, onion skin, carbon copy; black, red, faded ribbon); machine sound packs as a paid pack.
- v1.2: focus timer.
- Later: Apple Pencil margin notes.

## Technical notes
- A key press should show its letter and play its sound within about 20 ms. Preload every sound with AVAudioEngine and never load a file on key press.
- Text engine: a UIKit text view (TextKit 2) wrapped for SwiftUI. The app inserts characters itself, so no system keyboard appears.
- Autocorrect is off by design; optional spell check only underlines.
- Storage: SwiftData with iCloud. Each page is plain text plus style settings.
- Accessibility: VoiceOver labels on every key, plus a setting to swap in the system keyboard for dictation and other languages.

## Monetization
$4.99 upfront, or free with a $6.99 one-time unlock after 3 pages. Paper, ink and sound packs at $1.99 each. No subscription and no ads.

## Risks and open questions
- Gimmick risk: make it a real writing tool (export, sync, goals).
- No dictation, swipe typing or non-English layouts at launch.
- Record a real typewriter or license samples; never use sounds from other apps.
- Open question: can the app read the exact hinge angle so the paper tilts with the screen?

## Submission checklist
Built with the iOS 27.1 SDK; tested half-folded, flat, closed, portrait and landscape in Device Hub; works on a regular iPhone; Duo and regular screenshots; original name, icon and art; App Review notes explain the fold features; privacy details filled in; in-app purchases tested in the sandbox.
