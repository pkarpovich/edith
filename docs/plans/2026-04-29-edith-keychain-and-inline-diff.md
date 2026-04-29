# Edith: Keychain-backed API key + inline diff overlay

## Overview

Two related UX improvements:

1. **Keychain-backed API key with in-app Settings.** Today `AnthropicAPIProvider` reads `ANTHROPIC_API_KEY` from `ProcessInfo.environment`, which forces the user to set the variable via `launchctl setenv` or hard-code it into a shared Xcode scheme (which already leaked once into a diff). Replace this with: a `KeychainStore` wrapper around `Security.framework` that stores one item (service = bundle id, account = `anthropic-api-key`); a SwiftUI `Settings` scene with a secure field, Save and Clear actions; and an `apiKeyProvider` default that prefers Keychain and falls back to the env var (env stays useful for Xcode debug runs).

2. **Inline diff overlay.** The current `.ready(original, result)` overlay renders two side-by-side `ScrollView` columns. Replace with a single text block that shows the **result** with character-level insertions highlighted on a soft green background (matches the design reference: insertions highlighted, deletions not rendered). Use `CollectionDifference<Character>` on stdlib — no third-party dep.

The two features are bundled because both require touching app-level wiring and ship together as the first "real product" version after the streaming provider.

## Context (from discovery)

- **Onboarding/Settings**: `OnboardingView.swift` is accessibility-only (presented from `EdithApp.swift:37-56` via a delegate when AX permission is missing). No `Settings` scene, no `UserDefaults`, no menu entry beyond "Open Accessibility Settings" and "Quit".
- **Provider wiring**: `AnthropicAPIProvider.swift:15-23` exposes an `apiKeyProvider: @Sendable () -> String?` closure with env-var default. Constructed once in `AskEdithIntent.makeProvider()` (`AskEdithIntent.swift:87-94`) without overriding the closure.
- **Overlay structure**: `OverlayView.swift` puts original (left) and result (right) into an `HStack` of two 320pt `ScrollView` columns inside a 640pt-wide panel; `.ready` arm at `OverlayView.swift:64`. Streaming/processing/error states already exist in `OverlayState.swift`.
- **Dependencies**: `project.yml:23-26` lists only `swift-subprocess`. No Keychain wrapper, no diff library. Plan stays on Apple-only frameworks (`Security`, stdlib `CollectionDifference`, `AttributedString`).

## Development Approach

- **Testing approach**: Regular (code first, then tests). Matches the rest of this repo; AX/Keychain integration code is hard to test purely TDD because it depends on system services.
- Complete each task fully before moving to the next.
- Make small, focused changes; do not refactor adjacent code.
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task — both success and error scenarios.
- **CRITICAL: all tests must pass before starting the next task.**
- **CRITICAL: update this plan file when scope changes during implementation.**
- Run `make test` after each change.
- Maintain backward compatibility: existing prompt files with `provider: api` and a working env-var must keep working until the user moves their key to Keychain.

## Testing Strategy

- **Unit tests**: required for every task. Cover Keychain wrapper success/error paths via an injected backend protocol; cover diff rendering via `AttributedString` snapshots; cover provider resolution chain via `apiKeyProvider` closure substitution.
- **No e2e/UI tests** in this repo; manual smoke goes in Post-Completion.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document blockers with ⚠️ prefix.
- Update plan if implementation deviates from original scope.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): code changes, unit tests, project.yml/xcodeproj regen.
- **Post-Completion** (no checkboxes): manual smoke (writing real key, opening Settings, running fix-ru.txt against a chat selection, visually inspecting diff overlay).

## Implementation Steps

### Task 1: Keychain wrapper around Security.framework

- [x] create `edith/KeychainStore.swift` with a protocol `KeychainBackend` and a real implementation `SecItemKeychainBackend` so the wrapper is unit-testable
- [x] expose `KeychainStore` API: `read() -> String?`, `write(_ value: String) throws`, `delete() throws`; service = bundle id (`space.pkarpovich.edith`), account = `anthropic-api-key`, accessibility = `kSecAttrAccessibleAfterFirstUnlock`
- [x] surface a typed `KeychainError` enum (e.g. `.itemNotFound`, `.unexpectedStatus(OSStatus)`, `.encodingFailed`)
- [x] write tests for `KeychainStore` against an in-memory `FakeKeychainBackend`: read-after-write, overwrite-existing, delete-then-read returns nil, error from backend bubbles up
- [x] run `make test` — must pass before Task 2

### Task 2: Settings scene with API key field

- [ ] add `edith/SettingsView.swift`: SwiftUI form with a `SecureField` (toggle to plain `TextField` for "Show"), a "Save" button (calls `KeychainStore.write`), a "Clear" button (calls `KeychainStore.delete`), and a status line that reads "key saved" / "no key" by checking `KeychainStore.read()` on appear and after each action
- [ ] register a `Settings { SettingsView() }` scene in `EdithApp.swift` so `Cmd+,` opens the standard macOS settings window
- [ ] add a "Settings…" `Button` to the `MenuBarExtra` menu in `EdithApp.swift:18-34` that calls `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` (or the modern `SettingsLink` API if available on the target macOS — verify against current SDK)
- [ ] write tests for `SettingsView` view-model (extract `SettingsModel: ObservableObject` if needed): save reflects in `KeychainStore`, clear removes entry, "Show" toggle does not leak the field beyond the binding
- [ ] run `make test` — must pass before Task 3

### Task 3: Provider reads from Keychain with env fallback

- [ ] in `AnthropicAPIProvider.swift:15-23`, change the default `apiKeyProvider` closure to `{ KeychainStore.read() ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] }`
- [ ] update `AskEdithIntent.makeProvider()` (`AskEdithIntent.swift:87-94`) — no change required if the default closure now does the right thing; verify by reading the call site
- [ ] update `AnthropicAPIProviderTests.swift` to inject a closure that returns a test value for the existing tests; do not exercise the real Keychain in tests
- [ ] add a new test that the default closure path is wired by constructing `AnthropicAPIProvider()` (default args) inside a test that pre-populates a `FakeKeychainBackend` via a test-only initializer or a static seam — keep the seam minimal
- [ ] run `make test` — must pass before Task 4

### Task 4: Character-level inline diff renderer

- [ ] add `edith/InlineDiff.swift` with a pure function `func attributedDiff(original: String, result: String, insertColor: Color) -> AttributedString` that:
  - computes `result.difference(from: original)` as `CollectionDifference<Character>` and walks the result string, applying `BackgroundColor` on contiguous insertion runs (deletions are not rendered, since the result is shown as the canonical text)
  - merges adjacent insertions into single highlighted runs to avoid visual fragmentation
  - returns plain `AttributedString` for the unchanged stretches
- [ ] use a soft green background (`Color.green.opacity(0.25)` or equivalent — match the reference screenshot in `docs/plans/2026-04-29-edith-keychain-and-inline-diff.md`'s assets section if present, otherwise pick a near match)
- [ ] write tests for `attributedDiff`: identical strings produce no highlight, pure insertion is fully highlighted, pure deletion produces an unhighlighted result equal to the new string, replacement (delete + insert at same spot) highlights only the inserted range, multi-byte/Unicode (Cyrillic, emoji) characters are handled because `CollectionDifference<Character>` is grapheme-aware
- [ ] run `make test` — must pass before Task 5

### Task 5: Replace side-by-side overlay with inline diff

- [ ] in `OverlayView.swift:64`, replace the `.ready(original, result)` arm: drop the two-column `HStack`, render a single `ScrollView` containing a `Text(attributedDiff(original: model.state.original, result: result))` with the existing font and selection settings
- [ ] adjust the panel width in `OverlayCoordinator.swift:97-102` if the single column should be narrower than 640pt — pick one width that works for both `.streaming` and `.ready` so the panel does not jump between states
- [ ] keep the panel header / footer hints unchanged (Enter to confirm, Esc to dismiss)
- [ ] write a snapshot-style test for the rendering: build the `AttributedString` via `attributedDiff`, assert it matches the expected runs for a representative example (e.g. `"привет как дела"` → `"Привет, как дела?"`)
- [ ] run `make test` — must pass before Task 6

### Task 6: Verify acceptance criteria

- [ ] verify all requirements from Overview are implemented (Keychain stores key, Settings UI saves/clears, Provider reads from Keychain with env fallback, overlay shows inline diff)
- [ ] verify edge cases: empty key in Settings is rejected (or saved as empty? — pick one and test), result identical to original renders without any green highlight, very long result still scrolls
- [ ] run `make test` — full suite must pass
- [ ] verify no new SwiftLint or compiler warnings (the project does not run a linter today; if `xcodebuild` emits warnings that did not exist on `main`, fix them)
- [ ] verify the project still builds for both Debug and Release in `make build`

### Task 7: [Final] Update documentation

- [ ] if `README.md` documents env-var setup, replace with "Open Settings… and paste your key" (verify whether README mentions API key at all before editing)
- [ ] update any inline doc comments on `AnthropicAPIProvider.apiKeyProvider` to mention the Keychain → env fallback order

## Technical Details

**Keychain layout**

- Service: `space.pkarpovich.edith` (bundle id; centralize as a constant)
- Account: `anthropic-api-key`
- Accessibility: `kSecAttrAccessibleAfterFirstUnlock` (key is needed for hotkey-triggered intents that may fire on a locked-but-unlocked-once session; do not use `WhenUnlocked` because intents may fire while the screen is locked but the keychain is unlocked)
- Item class: `kSecClassGenericPassword`
- Value: UTF-8 encoded `Data`

**API key resolution order**

1. `KeychainStore.read()` — primary
2. `ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]` — fallback for `xcodebuild`/Xcode debug runs where setting Keychain is inconvenient
3. `nil` — provider raises `AIProviderError.missingApiKey` and the overlay shows `.error`

**Inline diff algorithm**

- Input: `original: String`, `result: String`
- Compute `result.difference(from: original)` (which is the standard library's `CollectionDifference<Character>`)
- Iterate the `result` string by index; for every position, check if the character at that index is part of an insertion in the diff (by tracking insertion offsets); apply `BackgroundColor` attribute to runs of consecutive insertion characters
- Deletions are intentionally not rendered — the user only needs to see the corrected text, with changes highlighted

**Settings scene wiring**

- Modern SwiftUI app: a `Settings { SettingsView() }` scene auto-binds `Cmd+,`. From `MenuBarExtra`, use `SettingsLink` if available; otherwise fall back to `NSApp.sendAction(Selector(("showSettingsWindow:")), …)`. Verify which API the project's deployment target supports before committing.

## Post-Completion

*Items requiring manual intervention or external systems — no checkboxes, informational only*

**Manual verification**

- Open the new Settings screen via `Cmd+,` from the MenuBarExtra menu, paste the rotated Anthropic API key, click Save, confirm status flips to "key saved".
- Quit and relaunch Edith; trigger the `Ask Edith` shortcut on a Russian chat selection that uses `provider: api`; confirm streaming kicks in without `missingApiKey`.
- Visually compare the `.ready` overlay against the design reference: result text rendered as a single block, insertions/changes highlighted in soft green, no side-by-side columns. Sample input: `"я там говорил про размышления"` with a deliberate typo `"размышления" → "размышленя"` so the diff has something to highlight.
- Use Keychain Access.app to verify the entry is present under service `space.pkarpovich.edith` after Save and absent after Clear.

**External system updates**

- Rotate the Anthropic API key that leaked in the earlier xcscheme diff (Anthropic console). Use the new key in the Settings screen rather than back in any scheme.
