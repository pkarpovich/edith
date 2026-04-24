# Edith — Walking Skeleton (Intent → Selection → Overlay → Paste)

## Overview

Greenfield native macOS app `edith`. Phase 1 is a walking skeleton that validates the full end-to-end plumbing **without any LLM involvement**. The app exposes a single `AskEdithIntent` usable from Shortcuts.app that:

1. Reads the selected text from the currently active application via Accessibility API.
2. Shows a non-activating overlay with the original text and a mock-transformed version (`uppercased()`).
3. On Enter: replaces the selection via simulated ⌘V, restoring the previous pasteboard afterward.
4. On Esc: dismisses the overlay, changes nothing.

**Why this skeleton:** validates that the chosen architecture (AppIntent `.background` + Shortcuts.app trigger + AX read + nonactivating NSPanel + CGEvent paste) preserves the user's selection and focus across the flow in real target applications. If this fails, no further design work matters.

**Target verification apps (user smoke tests):** Chrome, Telegram Desktop, Slack, WhatsApp. Slack and WhatsApp are Electron-based — AX behavior there is a known unknown we're surfacing now rather than later.

## Context (from discovery)

- Greenfield project. No existing codebase. `/Users/pavel.karpovich/Projects/edith` is empty.
- Bundle ID: `space.pkarpovich.edith`
- App display name: `edith`
- Intent title (Shortcuts.app): `Ask Edith`
- Intent type name: `AskEdithIntent`
- Min deployment: **macOS 26.4**
- Swift 6.2+ / Xcode 26.4
- No third-party dependencies in Phase 1
- Trigger model: user creates a Shortcut in Shortcuts.app containing `Ask Edith`, binds it to a system hotkey. App does not own hotkey registration.
- **Local environment verified (2026-04-24):** Xcode 26.4.1, Swift 6.3.1, macOS SDK 26.4, macOS 26.4.1 host, `notarytool` 1.1.1 available.
- **Distribution: personal only.** No Mac App Store submission. Target = DMG built locally and installed on the user's two laptops. App Sandbox stays OFF (AX and CGEvent paste are restricted under sandbox for non-MAS apps), Hardened Runtime ON (required if the DMG is ever notarized), no provisioning profile / TestFlight / App Store Connect plumbing needed.
- **Signing identities in the keychain:**
    - `Apple Development: Pavel Karpovich (Y56BH6SLN9)` — used for **Phase 1 dev builds** (this is what goes into target Signing & Capabilities). Team ID: `Y56BH6SLN9`.
    - `Apple Distribution: Pavel Karpovich (GGG699AY79)` — for MAS / enterprise paths, not used by this project.
    - ⚠️ `Developer ID Application` certificate is **not present** in the keychain. Not required for Phase 1 (dev signing is sufficient for local run + TCC grant). For the future DMG-to-second-laptop step, the user must first create a `Developer ID Application` cert at developer.apple.com (free with Apple Developer Program), or fall back to ad-hoc signing (`codesign --sign -`) with a manual right-click-Open bypass of Gatekeeper on the second machine.

## Development Approach

- **Automation boundary**: ralphex writes code, unit tests, and runs `xcodebuild` + `xcodebuild test`. Everything that requires launching the app, interacting with System Settings, using Shortcuts.app UI, or exercising behavior inside other applications is a user smoke test, collected in Post-Completion.
- **Testing approach**: regular (code first, unit tests for pure helpers in the same task). Integration behavior (AX / CGEvent / NSPanel) cannot be realistically unit-tested and is deferred to user smoke tests.
- Complete each task fully before moving to the next.
- **CRITICAL: every task MUST include new/updated unit tests** for the pure code introduced in that task.
- **CRITICAL: all tests must pass (and `xcodebuild` must succeed) before starting the next task.**
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy

- **Unit tests (automated, inside tasks)**: pure helpers only — mock transformation, pasteboard snapshot/restore, deep-link URL builder, intent metadata, error-branch returns from the AX reader when a fake AX helper is injected.
- **Manual smoke tests (user, in Post-Completion)**: AX integration in target apps, overlay focus preservation, paste-back round-trip, permission onboarding flow.
- **No UI/e2e framework**: not applicable for a menu-bar utility that drives other apps.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document issues/blockers with ⚠️ prefix.
- Update plan if implementation deviates from original scope.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): ralphex-automatable tasks — code changes, unit tests, build + test invocations.
- **Post-Completion** (no checkboxes): user smoke tests that require launching the app, clicking through System Settings / Shortcuts.app, and exercising behavior in target applications.

## Implementation Steps

### Task 1: Xcode project skeleton

- [x] create Xcode project: macOS → App template, SwiftUI lifecycle, product name `edith`, bundle id `space.pkarpovich.edith`, min deployment macOS 26.4, unit-test bundle included
- [x] set `LSUIElement = YES` in `Info.plist` so the app has no Dock icon
- [x] in target Signing & Capabilities: set **Team = Pavel Karpovich (Y56BH6SLN9)** and signing style = automatic (so Xcode picks the `Apple Development: Pavel Karpovich (Y56BH6SLN9)` identity), **remove the App Sandbox capability** if the template added it (sandbox breaks AX and CGEvent paste for non-App-Store apps), **keep / add Hardened Runtime** so the resulting build is notarization-ready
- [x] replace the default app entry point with a `MenuBarExtra` scene showing a minimal label (so we can see the app is running)
- [x] confirm `SWIFT_DEFAULT_ISOLATION = MainActor` is set on the app and test targets (Xcode 26 default for new projects); if missing, set it
- [x] add a placeholder unit test in the test target so the test phase has at least one case
- [x] run `xcodebuild -scheme edith build` — must succeed with zero warnings (wrapped via `make build`; ad-hoc signing for CLI since the Apple Developer account is not enrolled in `xcodebuild`. User's Xcode IDE still uses automatic `Apple Development` signing per target config.)
- [x] run `xcodebuild -scheme edith test` — must pass before Task 2 (wrapped via `make test`)

**Deviations from original Task 1 wording:**
- Project files generated from `project.yml` via `xcodegen` (regeneration is reproducible; not needed for IDE use).
- Unit tests use **Swift Testing** (not XCTest) because `XCTestCase.init()` is declared `nonisolated` in stdlib and clashes with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Swift Testing has no such conflict and is Apple's recommended framework under Xcode 26.
- Wrapped `xcodebuild build` / `xcodebuild test` in `Makefile` with ad-hoc signing overrides (`CODE_SIGN_IDENTITY=-`) so ralphex/CI does not require being signed into an Apple Developer account via Xcode. The project target itself keeps **automatic signing + Apple Development** so the user's Xcode IDE still produces the TCC-stable signed build.

### Task 2: AskEdithIntent declared and exposed

- [x] add a file `AskEdithIntent.swift` declaring a struct conforming to `AppIntent` with `title` set to the localized string `"Ask Edith"`, `supportedModes` set to `[.background]`, and a `perform()` method that logs a timestamped message via `os.Logger` and returns an empty `.result()`
- [x] add a file `EdithShortcutsProvider.swift` declaring a type conforming to `AppShortcutsProvider` that lists `AskEdithIntent` so the action registers with Shortcuts.app automatically on first launch
- [x] add a `Logger` extension with a stable subsystem (bundle id) and a `edith` category, used from `perform()` (marked `nonisolated` since `NonisolatedNonsendingByDefault` makes `perform()` nonisolated and cannot touch a MainActor-isolated static)
- [x] add unit tests asserting `AskEdithIntent.title` equals the expected string and `AskEdithIntent.supportedModes` equals `[.background]`
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 3

### Task 3: Accessibility selection reader

- [x] add a file `SelectionReader.swift` with a type that reads the current selection by chaining AX attribute lookups: system-wide element → `kAXFocusedApplicationAttribute` → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`
- [x] treat `AXError.apiDisabled`, missing attributes, wrong types, and empty strings as "no selection" (return `nil` with a log entry)
- [x] factor the AX calls behind a small protocol so tests can inject a fake that returns canned errors or values without touching real APIs
- [x] call the reader from `AskEdithIntent.perform()` and log the first 200 characters of the captured text with private-data privacy classification
- [x] add unit tests covering the reader branches via the fake: API disabled → `nil`; missing attribute → `nil`; wrong type → `nil`; empty string → `nil`; valid string → returned as a Swift `String`
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 4

### Task 4: Accessibility permission check and onboarding window

- [x] add a file `PermissionsCheck.swift` exposing a boolean property that wraps `AXIsProcessTrustedWithOptions` with the no-prompt option, so checks do not re-trigger the system prompt
- [x] add a constant `AccessibilityDeepLink` holding the `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` URL
- [x] add a SwiftUI `OnboardingView` with a short message and a button that opens the deep link via `NSWorkspace`
- [x] extend the app scene to show an onboarding `Window` on launch iff AX is not granted, and to show a status line ("Accessibility: granted" / "not granted") inside the `MenuBarExtra`
- [x] add unit tests asserting the deep-link URL string matches the expected constant and the status-formatting helper returns the expected two outputs for true and false
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 5

### Task 5: Nonactivating overlay panel with mock result

- [ ] add `OverlayPanel.swift` as an `NSPanel` subclass whose designated initializer sets `styleMask` to include `.nonactivatingPanel` (set once at init, never mutated), with `level = .popUpMenu`, `isFloatingPanel = true`, `hidesOnDeactivate = false`
- [ ] add a SwiftUI `OverlayView` showing two text blocks side-by-side ("Original" and "Result") and an Enter / Esc hint row at the bottom
- [ ] add `OverlayCoordinator.swift` that wraps the SwiftUI content in `NSHostingView`, puts it in `OverlayPanel`, positions the panel on the active screen, and installs a local key-down monitor mapping Enter to a confirm callback and Esc to a dismiss callback
- [ ] add `MockTransformer.swift` with a pure function that returns `uppercased()` of its input
- [ ] wire `AskEdithIntent.perform()` to present the overlay after capture, then suspend via async continuation until the coordinator resolves with either confirmed-with-result or dismissed
- [ ] add unit tests for `MockTransformer` covering empty string, ASCII, Cyrillic, and emoji-containing inputs
- [ ] run `xcodebuild build` + `xcodebuild test` — must pass before Task 6

### Task 6: Paste-back with pasteboard save and restore

- [ ] add `PasteboardSnapshot.swift` as a pure value type that captures the types and payloads of a given `NSPasteboard`'s items and can re-apply them to a pasteboard later; pasteboard is injected so tests can target a named test pasteboard instead of `.general`
- [ ] add `Paster.swift` that, given a string: captures a snapshot of `.general`, writes the string as `.string`, posts synthesized ⌘V key-down and key-up CGEvents at the HID tap, then restores the snapshot after ~250 ms
- [ ] connect the overlay's confirm callback to `Paster.paste(result)` and have the coordinator dismiss the panel afterwards
- [ ] add unit tests that use a dedicated test pasteboard (not `.general`) to verify snapshot round-trip: write items, snapshot, mutate, apply, verify restored types and payloads
- [ ] run `xcodebuild build` + `xcodebuild test` — must pass before Task 7

### Task 7: Verify automated acceptance criteria

- [ ] `xcodebuild -scheme edith build` passes with zero warnings
- [ ] `xcodebuild -scheme edith test` passes with all unit tests green
- [ ] all task checkboxes above are marked `[x]`
- [ ] no `TODO` / `FIXME` left in files created in Tasks 1–6

## Technical Details

- **AppIntent mode**: `supportedModes = [.background]` — per WWDC25 session 275 (https://developer.apple.com/videos/play/wwdc2025/275/), "the app will never be foregrounded by the intent". Load-bearing assumption.
- **NSPanel gotcha**: `.nonactivatingPanel` must be set in `styleMask` at init, not mutated afterwards, otherwise activation behavior does not stick. Reference: https://philz.blog/nspanel-nonactivating-style-mask-flag/
- **AX attribute chain**: system-wide `AXUIElement` → `kAXFocusedApplicationAttribute` → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`.
- **Electron limitation**: Electron apps may return empty or incorrect `kAXSelectedTextAttribute`. Surfaced during user smoke tests, not in ralphex tasks.
- **Paste-back mechanism**: `CGEventCreateKeyboardEvent` with virtual keycode 9 (V), flags `.maskCommand`, posted to `.cghidEventTap`. Requires the Accessibility permission.
- **Pasteboard restore delay**: ~250 ms chosen as headroom over typical paste-handling time. Tunable during user smoke tests if paste is flaky.
- **Default isolation**: `.defaultIsolation(MainActor.self)` (Swift 6.2+) — Xcode 26 applies this to new projects by default; avoids manual `@MainActor` sprinkling on UI types.
- **Dependencies**: stdlib + AppKit + SwiftUI + AppIntents only. `swift-subprocess` / `DifferenceKit` enter in Phase 2.
- **Signing & distribution (Phase 1)**: target signed with `Apple Development: Pavel Karpovich (Y56BH6SLN9)`, signing style automatic, App Sandbox OFF, Hardened Runtime ON. The dev cert is stable (keyed on common name + team), so the TCC record for Accessibility persists across rebuilds once granted — avoids re-granting AX on every Run from Xcode, a common pain point for AX utilities.

## Post-Completion

*Smoke tests the user runs. No checkboxes — ralphex does not launch the app, interact with Shortcuts.app, grant AX, or drive other applications.*

**After Task 1 — app skeleton sanity:**

- Launch the app (from Xcode Run, or the built `.app`).
- Menu-bar icon should appear.
- Dock should NOT show `edith`.
- App should not open any window.

**After Task 2 — intent visible and fires without activation:**

- Install / run the app once so macOS registers it with the App Intents index.
- Open Shortcuts.app → New Shortcut → search "Ask Edith" → action should be found.
- Create a Shortcut containing only `Ask Edith`. Bind it to a system hotkey (e.g. `⌃⌥⌘E`) via the Shortcut's Info → Keyboard Shortcut.
- Focus a different app (e.g. Safari). Press the hotkey.
- Open Console.app (filter on "edith") — verify the intent-fired log line appears.
- Verify `edith` did NOT activate: no Dock flash, no menu-bar app switch, Safari remains active.

**After Task 3 — AX selection reader across target apps:**

- Ensure Accessibility is granted for `edith` in System Settings → Privacy & Security → Accessibility.
- Select text in each target and trigger the Shortcut; inspect Console.app log for the captured text; fill the matrix below.

| App                          | AX read works? | Notes |
|------------------------------|----------------|-------|
| Chrome — `<input>`           |                |       |
| Chrome — Google Docs         |                |       |
| Chrome — content-editable    |                |       |
| Telegram Desktop             |                |       |
| Slack                        |                |       |
| WhatsApp Desktop             |                |       |

- If Slack / WhatsApp return empty, this is the ⚠️ Electron limitation flagged earlier. Note it and proceed — Phase 2 will decide whether to add a ⌘C fallback specifically for those apps.

**After Task 4 — permission onboarding:**

- Remove `edith` from System Settings → Privacy & Security → Accessibility.
- Relaunch the app.
- Onboarding window should appear with "Open System Settings" button.
- Button should open the Accessibility pane directly.
- Grant permission, close the pane. Menu-bar status should update to "granted" (may require a relaunch — acceptable).

**After Task 5 — overlay behavior:**

- Select text in Chrome, trigger the Shortcut.
- Overlay panel should appear showing original + uppercased result.
- Chrome should remain the active app (menu-bar title stays "Chrome", not "edith").
- Press Esc — overlay dismisses, nothing changes.
- Reselect, trigger again, press Enter — overlay dismisses (no paste yet, that's Task 6).
- Repeat in Telegram, Slack, WhatsApp — record any focus-stealing weirdness.

**After Task 6 — full round-trip paste replace:**

- Put a known string into the system clipboard beforehand (e.g. `"pre-existing"`).
- Select text in Chrome, trigger Shortcut, press Enter.
- Selection should be replaced with the uppercase version.
- After ≥1 second, open any text field and paste — the clipboard should contain the original `"pre-existing"` (restored).
- Repeat in Telegram, Slack, WhatsApp. Update the matrix:

| App               | Selection read | Overlay focus OK | Paste replaces selection | Clipboard restored |
|-------------------|----------------|-------------------|---------------------------|---------------------|
| Chrome (input)    |                |                   |                           |                     |
| Chrome (Docs)     |                |                   |                           |                     |
| Telegram Desktop  |                |                   |                           |                     |
| Slack             |                |                   |                           |                     |
| WhatsApp Desktop  |                |                   |                           |                     |

**After Task 7 — wrap-up and go/no-go for Phase 2:**

- Review the filled matrix.
- Decide which apps are supported (Phase 2 proceeds) and which ones need fallback strategies.
- If Shortcuts.app hotkey latency is intolerable (>800 ms), note it — Phase 2 may layer native hotkey registration via `KeyboardShortcuts` on top of the Shortcut path.
- If selection is dropped in any app despite `.background` intent + nonactivating panel, that is a ⚠️ blocker — record and investigate before Phase 2.

**Phase 2 triggers (out of scope here, but unblocked by Phase 1 success):**

- Replace `MockTransformer.uppercased` with a Claude CLI provider using `swift-subprocess`.
- Add a `prompt` parameter to `AskEdithIntent`. Prompt travels from Shortcut → intent → provider.
- Real inline diff rendering (word-level via token-based LCS) in `OverlayView`.
- Optional streaming UI during the Claude call.
- Optional on-device Foundation Models provider as an alternative.

**Personal distribution (not a Phase 1 deliverable, noted for the future):**

- Prerequisite: create a `Developer ID Application` certificate at developer.apple.com (the current keychain only has `Apple Development` + `Apple Distribution`). Alternative: ad-hoc sign with `codesign --sign -` and accept the Gatekeeper "right-click → Open" bypass on the second laptop.
- With `Developer ID Application`: archive in Xcode (Product → Archive), export a signed `.app` using the Developer ID profile, wrap into a DMG (`hdiutil create` or the `create-dmg` tool), copy to the second laptop, drag to `/Applications`.
- Notarization is optional for personal use but recommended: Gatekeeper on the second machine will warn on first run otherwise. `xcrun notarytool submit` + `xcrun stapler staple` is the minimal path; `notarytool` 1.1.1 is already installed locally.
- AX permission must be granted on each machine once; TCC is per-host.
- No App Store Connect, no provisioning profile, no TestFlight, no iCloud-container IDs.
