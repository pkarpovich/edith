# Edith — Phase 2: Claude CLI Provider

## Overview

Replace `MockTransformer.uppercased` with a real LLM call via `claude -p`, fronted by a small provider abstraction so future backends (FoundationModels, Anthropic SDK, etc.) can plug in later without further refactor. Each Shortcut in Shortcuts.app owns its own prompt via a new intent parameter, so `Fix RU`, `Fix EN`, `Reply` are three Shortcuts with three different prompts pointing at the same `Ask Edith` action.

Because Claude responses can take 3–30 seconds, the overlay becomes stateful: it appears immediately after capture with the original selection on the left and a loading indicator on the right, then transitions to the result once it arrives. Esc cancels the in-flight provider task and dismisses; Enter (only available in `.ready` state) pastes the result.

**Out of scope (deferred to Phase 3 or later):**

- Diff highlighting between original and result. The overlay shows two plain text blocks, no inline coloring.
- A `skill` parameter or any non-prompt invocation style.
- Multiple providers — only one (`ClaudeCLIProvider`) ships in this phase. The protocol is in place so adding a second is mechanical, but no registry / selection UI.
- Streaming partial output as it arrives. We collect the full response and present it at once.
- Per-Shortcut provider selection.

## Context (from Phase 1)

- AppIntent already exists (`AskEdithIntent`, `.background` mode), wired through `OverlayCoordinator` and `Paster`.
- `SelectionReader` covers native, Chromium/Electron, and WebKit text capture.
- Overlay currently presents synchronously with a pre-computed result string (mock uppercase). It must become async.
- Bundle ID: `space.pkarpovich.edith`. Signing team: `GGG699AY79` (Apple Development cert).
- Xcode 26.4.1, Swift 6.3.1, macOS 26.4 SDK, deployment 26.4.

## Development Approach

- **Automation boundary**: ralphex writes Swift code, unit tests, edits the Xcode project / SPM manifest, runs `xcodebuild build` / `xcodebuild test`. Anything that requires a running app, Shortcuts.app, Console.app, or actually invoking `claude` lives in Post-Completion as user smoke tests.
- **Testing approach**: regular. Pure logic (state transitions, mock provider) unit-tested in the same task. Real provider integration verified by hand.
- Complete each task fully and run `xcodebuild build` + `xcodebuild test` before starting the next.
- **CRITICAL: every task MUST add or update unit tests** for the pure code introduced in that task.
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy

- **Unit tests**: provider protocol shape, `MockProvider` behavior, overlay state machine transitions, intent dispatching to provider, error mapping.
- **Manual smoke tests** (Post-Completion): real `claude` calls in TextEdit / Telegram / Chrome / Slack / Mail; cancellation (Esc during processing); error path (rename `claude` to simulate missing CLI).

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document issues/blockers with ⚠️ prefix.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): ralphex-automatable.
- **Post-Completion** (no checkboxes): user smoke tests with the live `claude` binary and target apps.

## Implementation Steps

### Task 1: Add swift-subprocess dependency

- [ ] add `swiftlang/swift-subprocess` 0.4.x as a Swift Package dependency to the `edith` target via Xcode (File → Add Package Dependencies)
- [ ] confirm `Subprocess` product is linked into the `edith` target only (not test target)
- [ ] commit the resolved `Package.resolved`
- [ ] write a one-line smoke import test in `edith/SubprocessSmoke.swift`: `import Subprocess` (file deleted at end of task once linkage confirmed) — or equivalent: ensure the project still builds with the new dep
- [ ] run `xcodebuild build` — must succeed with zero warnings
- [ ] run `xcodebuild test` — pre-existing tests must still pass

### Task 2: Define AIProvider protocol and MockProvider

- [ ] add `edith/AIProvider.swift` declaring a `Sendable` protocol with one async-throws method that takes a prompt string and an input string and returns the transformed string
- [ ] declare a small `AIProviderError` enum covering `notFound`, `nonZeroExit(code: Int32, stderr: String)`, `emptyOutput`, `cancelled` so the overlay can render meaningful messages
- [ ] add `edith/MockProvider.swift`: an `AIProvider` that returns `input.uppercased()` after an injectable delay, used for tests and as a fallback in DEBUG when `claude` is missing
- [ ] write unit tests for `MockProvider`: returns uppercased input, honors cancellation via `Task.cancel`, respects injected delay
- [ ] keep `MockTransformer.swift` and its tests for now — `OverlayView` still references it; it goes away in Task 4
- [ ] run `xcodebuild build` + `xcodebuild test` — must pass

### Task 3: Refactor overlay into a state machine

- [ ] introduce `OverlayState` enum with cases `processing(original: String)`, `ready(original: String, result: String)`, `error(original: String, message: String)`
- [ ] convert `OverlayCoordinator` so it exposes a state-publishing surface (an `@Observable` model or `AsyncStream<OverlayState>`) instead of resolving once with a single outcome
- [ ] update `OverlayView` to render per state: in `.processing` show original on the left and a `ProgressView` on the right with "thinking…" text; in `.ready` show original and result side-by-side and an Enter hint; in `.error` show original and a styled error block with Dismiss hint only
- [ ] Esc dismisses in any state; Enter is a no-op outside `.ready`
- [ ] expose a `confirm()` and `dismiss()` callback to the intent so it can react and own the provider Task lifecycle
- [ ] write unit tests for state transitions (start `.processing`, transition to `.ready` produces expected payload, transition to `.error` carries message) — test the model / state struct, not the SwiftUI view
- [ ] run `xcodebuild build` + `xcodebuild test` — must pass

### Task 4: ClaudeCLIProvider and intent integration

- [ ] add `edith/ClaudeCLIProvider.swift` using `swift-subprocess` to invoke `claude -p <prompt> --output-format=text` with the captured selection piped to stdin; collect stdout to a `String`, trim trailing newline
- [ ] map subprocess errors to `AIProviderError`: missing executable → `notFound`; non-zero exit → `nonZeroExit(code, stderr)`; cancellation → `cancelled`; empty stdout → `emptyOutput`
- [ ] add `@Parameter(title: "Prompt") var prompt: String` to `AskEdithIntent`; remove the `MockTransformer` call from the intent
- [ ] wire `AskEdithIntent.perform()` to: capture → present overlay in `.processing(original)` → start a `Task` invoking `ClaudeCLIProvider().run(prompt:input:)` → on success transition to `.ready(original, result)` → on error transition to `.error(original, message)` → await user `confirm()` (paste) or `dismiss()` (cancel the in-flight Task if still processing)
- [ ] delete `edith/MockTransformer.swift` and its test file once nothing references them
- [ ] write unit tests using a fake `AIProvider` injected into the intent (or its core logic factored into a helper): success path produces `.ready` state with provider output; provider throws → `.error` state with formatted message; cancellation flips to dismissal cleanly
- [ ] run `xcodebuild build` + `xcodebuild test` — must pass

### Task 5: Verify automated acceptance criteria

- [ ] `xcodebuild -scheme edith build` passes with zero warnings
- [ ] `xcodebuild -scheme edith test` passes with all unit tests green
- [ ] all task checkboxes above are marked `[x]`
- [ ] no `TODO` / `FIXME` left in files created or modified in Tasks 1–4

## Technical Details

- **swift-subprocess invocation**: `run(.name("claude"), arguments: ["-p", prompt, "--output-format=text"], input: .string(input, using: .utf8))`. Collect `result.standardOutput` as `String` via `.collect()`. Stderr collected separately for error messages on non-zero exit.
- **PATH**: `claude` is installed via npm/pnpm typically into `~/.bun/bin` or `~/.local/bin`. The `Process` / Subprocess inherits the parent app's environment; menu-bar apps launched by macOS may not have a user shell PATH. Mitigation: explicitly extend the `PATH` env var passed to Subprocess to include common locations (`/opt/homebrew/bin`, `~/.bun/bin`, `~/.local/bin`, `/usr/local/bin`). Document in Post-Completion how to verify.
- **Cancellation**: `Task` running the provider is held by the intent. `OverlayCoordinator.dismiss()` resolves the awaiter and cancels the Task. `swift-subprocess` propagates cancellation to the child via stdin close + SIGTERM.
- **`@Parameter` UX**: Shortcuts.app surfaces prompt as a free-text field per Shortcut. User fills it once when authoring the Shortcut; subsequent triggers reuse the same prompt.
- **`OverlayState` ownership**: model held by `OverlayCoordinator`, observed by `OverlayView` via SwiftUI's `@Observable` / `@State` binding. The intent has a thin handle that lets it call `transition(to:)` and await `confirmOrDismiss()`.
- **No diff yet**: `OverlayView` shows `Text(original)` and `Text(result)` plainly. Phase 3 introduces `DifferenceKit` + `AttributedString` for word-level highlighting.

## Post-Completion

*Smoke tests requiring real `claude` and target apps. Ralphex does not run the app or invoke the CLI.*

**Pre-flight (run once):**

- Confirm `claude` is in PATH from a fresh login shell: `which claude`. If missing, install per project conventions and re-test.
- Ensure the existing AX permission for `edith` is still granted (signing identity unchanged in this phase).

**After Task 4 — happy path:**

- Open Shortcuts.app, edit the existing test Shortcut bound to `Hyper+E`. The `Ask Edith` action should now show a `Prompt` field. Set it to something simple like `Convert this text to UPPERCASE` (so we know it's actually calling Claude and not the removed mock).
- Open TextEdit, type `hello edith`, select, hit `Hyper+E`.
- Overlay appears immediately with `hello edith` on the left and a loading spinner on the right.
- After a few seconds, spinner replaced with `HELLO EDITH` (or whatever Claude returns for the prompt).
- Press Enter — selection is replaced.

**Cancellation path:**

- Same setup, but as soon as the spinner appears press Esc.
- Overlay closes; nothing is pasted; in Console there should be no error logs (cancellation is clean).

**Error path:**

- Temporarily rename `~/.bun/bin/claude` (or wherever it lives) to `claude.bak`.
- Trigger the Shortcut.
- Overlay should show `.error` state with a message like "Claude CLI not found".
- Restore the binary.

**Cross-app verification matrix:**

| App                   | Shortcut prompt                     | Result        |
|-----------------------|-------------------------------------|---------------|
| TextEdit              | "convert to uppercase"              |               |
| Telegram Desktop      | "fix grammar in russian"            |               |
| Chrome (Docs)         | "rewrite professionally in english" |               |
| Slack                 | "shorten this message"              |               |
| Mail (compose)        | "make this email warmer"            |               |

**Latency notes (record empirically):**

- First call after a cold start tends to be slowest. Note typical end-to-end time per app for awareness.
- If `claude` cold-start exceeds ~10 s in a way that hurts UX, evaluate whether a warm `claude --resume`-style daemon path is worth chasing in a future phase.

**Known follow-ups for Phase 3 (informational):**

- Diff highlighting (`DifferenceKit` + `AttributedString` word-level).
- Streaming partial output.
- Optional `skill` parameter on the intent so Shortcuts can pick `english-editor` and friends instead of typing prompts.
- `FoundationModelsProvider` as on-device alternative; introduce a small registry + per-Shortcut provider selection.
