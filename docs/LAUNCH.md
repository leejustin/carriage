# Launch checklist

Target: submit to App Review by **Oct 21, 2026**, live for the Duo launch on Oct 23.

## Blockers that need you

1. **Fold the Duo in Device Hub.** Built with Xcode 27.1, the real hinge reports closed and Carriage lays out for the closed Duo on its own. Half-folded, flat, book and the fold transitions still need a pass: in Device Hub, fold through each and check the page and keys land where they should (debug builds save a picture of each layout to Documents/FoldCapture).
2. **Sign in to Xcode.** The project is set to your team (`2TWQYRZUDF`) with automatic signing, but Xcode has no account signed in, so it can't make the profiles. Add your Apple Account in Xcode › Settings › Accounts. Then Product › Archive registers the app ID (`com.carriage.app`), the widget (`com.carriage.app.widgets`), the iCloud container and the app group, and makes the profiles.
3. **iCloud container and app group.** Create `iCloud.com.carriage.app` (with both CloudKit and iCloud Documents, for the Markdown copies in iCloud Drive) and the app group `group.com.carriage.app` (shared with the widget extension, `com.carriage.app.widgets`). Xcode makes them on the first signed build (blocker 2). Then, in the CloudKit Dashboard, **deploy the schema to Production** before release, or sync works in testing and fails for customers. Without iCloud the app falls back to local storage and keeps the Markdown copies in On My iPhone › Carriage.
4. **App Store Connect product:** one non-consumable, `com.carriage.app.unlock`, $6.99, "Unlock Carriage". Everything else is free; the free version is three pages.
5. **Typeface.** Courier Prime (SIL Open Font License) is bundled in `Carriage/Fonts` with its license file; nothing to do.
6. **Privacy and support pages.** Published with GitHub Pages from `docs/` on `main`: https://leejustin.github.io/carriage/site/privacy.html and https://leejustin.github.io/carriage/site/support.html. Put these in App Store Connect.
7. **Store listing.** Copy, keywords and purchase descriptions are in [APP_STORE.md](APP_STORE.md).

## Submission checklist (from the spec)

| Item | Status |
| --- | --- |
| Built with the iOS 27.1 SDK | ✅ Xcode 27.1; Release build for device is clean |
| Tested half-folded, flat, closed, portrait and landscape in Device Hub | 🟡 Closed checked on the real Duo simulator; the other postures checked with FoldKit's simulation and need a fold in Device Hub (blocker 1) |
| Works on a regular iPhone | ✅ Checked on iPhone 18 Pro simulator |
| Duo and regular screenshots | 🟡 Regular iPhone set in `docs/screenshots/` from `scripts/screenshots.sh`; run it again on the 27.1 Duo simulator |
| Original name, icon and art | ✅ Icon and all art are drawn in code; sounds are synthesized |
| App Review notes explain the fold features | ✅ [APP_REVIEW.md](APP_REVIEW.md) |
| Privacy details filled in | 🟡 Privacy manifests for the app and the widget declare every required-reason API (user defaults, app group, file dates); the policy is written (`docs/site/privacy.html`); in App Store Connect answer "Data Not Collected" |
| Export compliance | ✅ `ITSAppUsesNonExemptEncryption = NO` (only Apple's HTTPS for iCloud), so uploads skip the encryption question |
| Age rating | 🟡 Answer App Store Connect's questionnaire: no on everything; no web access, no user-generated content shared with others |
| In-app purchases tested in the sandbox | 🟡 Works with `Carriage.storekit` locally; test in sandbox once products exist |

## Writing focus

Carriage can't turn on Do Not Disturb (iOS has no API for that). Instead:
- The Focus button (moon) clears the page down to paper and keys; a tap on the paper shows the controls for a few seconds.
- A Focus Filter (`CarriageFocusFilter`) turns that on whenever a Focus with Carriage's filter is active, and can hide goals and streaks.
- The first time someone enters Focus, a short guide shows how to have iOS turn on Do Not Disturb whenever Carriage opens (Settings › Focus › Add Schedule › App). It's also in Settings › Writing. Check the wording against iOS 27's Focus settings on a device.

## Checked so far

- A 20,000-word page opens in a few seconds and types at 3–6 ms a key (the first key on a page that long takes about 50 ms in a Debug build).
- Runs in iPadOS's iPhone-app window with the regular layout.
- Every posture, the reading spread, the closed glance, night desk, focus, onboarding, Save to Files and the library checked in the simulator (Duo postures simulated).

## Not in 1.0

- Apple Pencil margin notes (spec: "Later").
- Dictation, swipe typing and non-English layouts on the typewriter keys (the system-keyboard setting covers dictation and other languages).
