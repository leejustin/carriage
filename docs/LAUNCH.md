# Launch checklist

Target: submit to App Review by **Oct 21, 2026**, live for the Duo launch on Oct 23.

## Blockers that need you

1. **Install Xcode 27.1.** This Mac has Xcode 27.0, which has neither the Duo APIs nor a Duo simulator. Built with 27.0, the app is letterboxed on the inner screen and FoldKit falls back to "regular iPhone". Once 27.1 is installed nothing needs changing: FoldKit's hinge and fold-line code switches on automatically. Then run once in the Duo simulator and in Device Hub and check the probe in Settings › Developer (debug builds) reports the hinge and posture.
2. **Signing and bundle ID.** The project uses `com.leejustin.carriage` with no team set. Pick your team in Signing & Capabilities and change the bundle ID if you want another one. Product IDs and the iCloud container follow the same prefix (see below).
3. **iCloud container.** Create `iCloud.com.leejustin.carriage` in the developer portal (Xcode does this when you enable the capability with your team). Without it the app falls back to local storage.
4. **App Store Connect products** (all non-consumable):
   - `com.leejustin.carriage.unlock`, $6.99, "Unlock Carriage"
   - `com.leejustin.carriage.pack.paperink`, $1.99, "Paper & Ink"
   - `com.leejustin.carriage.pack.sounds`, $1.99, "Machine Sounds"
5. **Pick the price model.** The code ships freemium (three free pages, then the $6.99 unlock). For $4.99 upfront, set `Monetization.current = .upfront` in `Carriage/Store/Store.swift` and set the app price in App Store Connect; the packs stay.
6. **Typeface.** Courier Prime (SIL Open Font License) is bundled in `Carriage/Fonts` with its license file; nothing to do.

## Submission checklist (from the spec)

| Item | Status |
| --- | --- |
| Built with the iOS 27.1 SDK | ⛔ Needs Xcode 27.1 (blocker 1) |
| Tested half-folded, flat, closed, portrait and landscape in Device Hub | 🟡 All postures checked with FoldKit's simulation; needs a pass in the real Duo simulator |
| Works on a regular iPhone | ✅ Checked on iPhone 18 Pro simulator |
| Duo and regular screenshots | 🟡 Launch with `-seedDemo` and `-foldSimulation halfOpen` for content; capture on 27.1 Duo simulator |
| Original name, icon and art | ✅ Icon and all art are drawn in code; sounds are synthesized |
| App Review notes explain the fold features | ✅ [APP_REVIEW.md](APP_REVIEW.md) |
| Privacy details filled in | 🟡 `PrivacyInfo.xcprivacy` included; in App Store Connect answer "Data Not Collected" |
| In-app purchases tested in the sandbox | 🟡 Works with `Carriage.storekit` locally; test in sandbox once products exist |

## Writing focus

Carriage can't turn on Do Not Disturb (iOS has no API for that). Instead:
- The Focus button (moon) clears the page down to paper and keys; a tap on the paper shows the controls for a few seconds.
- A Focus Filter (`CarriageFocusFilter`) turns that on whenever a Focus with Carriage's filter is active, and can hide goals and streaks.
- The first time someone enters Focus, a short guide shows how to have iOS turn on Do Not Disturb whenever Carriage opens (Settings › Focus › Add Schedule › App). It's also in Settings › Writing. Check the wording against iOS 27's Focus settings on a device.

## Not in 1.0

- Apple Pencil margin notes (spec: "Later").
- Dictation, swipe typing and non-English layouts on the typewriter keys (the system-keyboard setting covers dictation and other languages).
