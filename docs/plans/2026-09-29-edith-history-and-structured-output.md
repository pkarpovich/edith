# Edith: run history (SwiftData), copy-last menu items, API effort and structured output

## Overview

Four changes that ship together:

1. **Run history.** Every Ask Edith run is recorded in a local SwiftData store: the original selection, the prompt and model settings, the raw model output, the parsed result, the stop reason, latency and how the overlay ended (confirmed / dismissed / paste failed / failed). The store is the future source of real cases for the prompt eval (`$HOME/Projects/environment/prompt-evals`); exporting to it is a later, separate task.
2. **Two menu-bar items**, fed by the store: "Copy Last Result" and "Copy Last Original". Real scenarios: the paste landed in the wrong field or failed (today only a beep), the user pressed esc and then changed their mind, the user needs the original back after pasting.
3. **`effort` reaches the API.** `AnthropicAPIProvider` ignores the prompt file's `effort` today (it only logs a warning). It is sent as `output_config.effort` when set.
4. **Structured output for the API provider.** On `claude-sonnet-5-5` the model sometimes skips thinking and reasons in the visible reply ("...\n\nHmm, wait - ...\n\n<corrected text>"), and Edith pastes all of it. The API request now always carries `output_config.format` with a JSON schema `{"text": string}`; the model can only reason in its thinking, and Edith pastes the `text` field. Eval evidence (sonnet 5.5, effort medium, 45 cases x3, judge opus 5.5): plain output 127/135 with 3 reasoning leaks, structured output 125/135 with 0 leaks, 0 malformed JSON, 0 `max_tokens` stops, latency avg 1.7s / p90 3.0s.

### Non-goals

- No export from the store into the eval corpus, no token or cost columns, no retention/cleanup, no "don't record" toggle, no UI for browsing history.
- No live streaming of partial JSON for the API provider: the overlay stays in `processing` until the reply is complete. The CLI provider keeps its current streaming.
- No change to the CLI provider's output format (no `--json-schema`); no prompt-level switch to turn the schema off.
- No fix of the overlay's "Текст уже корректен" placeholder or its hardcoded "1 edit" counter (`edith/OverlayView.swift`) - separate change.
- `AnthropicModels.defaultModel` stays as is.

### Rejected alternatives

- **Raw SQLite3 / GRDB** instead of SwiftData: rejected - the user wants the native Apple stack; a spike confirmed the SwiftData file is readable from `sqlite3` (table `ZEDITRUN`, `Z`-prefixed columns, dates in seconds since 2001-01-01), which is all the eval side needs (read-only).
- **Default SwiftData store location**: rejected - a non-sandboxed app gets `~/Library/Application Support/default.store`, shared with every other non-sandboxed SwiftData app.
- **A code-side "reject replies with extra lines" guard** against reasoning leaks: rejected as treating the symptom; structured output removes the cause.
- **Keeping Haiku 4.5 for fix-en**: rejected by the user - all API prompts move to `claude-sonnet-5-5` (Haiku 4.5 also rejects `effort`).

## Skills to invoke

Load each skill below with the Skill tool and follow its conventions before implementing any task in this plan.

- `axiom:axiom-data` - SwiftData `@Model`, `ModelContainer`/`ModelConfiguration`, `FetchDescriptor`, in-memory stores for tests (read its `skills/swiftdata.md`)
- `swiftui-expert-skill` - the `MenuBarExtra` menu items and `@Query` usage in `EdithApp.swift`
- `swift-concurrency` - the provider stream contract change, MainActor isolation of the recorder, cancellation in `AskEdithRunner`
- `swift-testing-expert` - all new and changed tests (Swift Testing)

## Context (from discovery)

- **Run flow**: `edith/AskEdithIntent.swift` `perform()` reads the selection, `prepare(path:selection:)` loads/parses/renders the prompt, builds an `OverlayCoordinator`, and passes a `drive` closure that calls `AskEdithRunner.drive(provider:original:prompt:model:effort:state:)`. `OverlayCoordinator` (`edith/OverlayCoordinator.swift`) re-runs the same `drive` closure on Cmd+R after an error, and `resolve(_:)` pastes via `Paster.paste` (returns `false` on failure, today only a beep + log) and returns `Outcome` (`.confirmed(String)` / `.dismissed`).
- **Provider contract**: `edith/AIProvider.swift` - `run(prompt:model:effort:) -> AsyncThrowingStream<String, Error>`, errors in `AIProviderError` (`LocalizedError`). Implementations: `AnthropicAPIProvider`, `ClaudeCLIProvider` (one chunk after the process exits), `MockProvider`; test doubles in `edithTests/AskEdithRunnerTests.swift`.
- **API provider**: `edith/AnthropicAPIProvider.swift` builds the body with `JSONSerialization` (`model`, `max_tokens` 4096, `stream: true`, one user message), streams via `AnthropicTransport`, parses with `edith/AnthropicSSEParser.swift`, which only knows `content_block_delta` (`text_delta`), `message_stop`, `error`; `message_delta` (carries `stop_reason`) is ignored; thinking deltas are ignored.
- **Menu**: `edith/EdithApp.swift` - `MenuBarExtra` with `.menuBarExtraStyle(.menu)`, `MenuBarContent` holds the Accessibility status, "Open Accessibility Settings...", `SettingsLink`, Quit.
- **Project**: XcodeGen (`project.yml`, regenerate with `make generate` after adding files), Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, strict concurrency, macOS 26.0, not sandboxed, only dependency swift-subprocess. Tests: Swift Testing in `edithTests/`, system seams behind protocols (`KeychainBackend`, `AXBackend`, `AnthropicTransport`). Commands: `make build`, `make test`.
- **Verified APIs**: AppIntents `AppDependencyManager.shared.add(dependency:)` and the `@Dependency` property wrapper (`typealias Dependency = AppDependency`) exist in the macOS 26 SDK.

## Development Approach

- **Testing approach**: Regular (code first, then tests in the same task) - matches the previous Edith plans.
- Complete each task fully before moving to the next; small, focused changes; do not refactor adjacent code.
- **CRITICAL: every task MUST include new/updated tests** for the code changed in that task, success and error paths.
- **CRITICAL: all tests must pass before starting the next task** (`make test`).
- **CRITICAL: update this plan file when scope changes during implementation.**
- Run `make generate` whenever a file is added or removed, then `make build` and `make test`.
- No comments or docstrings in code (repo convention); early returns; no arrow functions inlined in SwiftUI props (use methods).

## Code-Quality Rules (verify before marking each task complete)

The Swift skills in this plan have no `## Hard rules` block; these are their hard-rule equivalents, copied verbatim.

### SwiftUI (`swiftui-expert-skill`, Correctness Checklist - "violations are always bugs")

- `@State` properties are `private`
- `@Binding` only where a child modifies parent state
- Changing parent-owned inputs are not stored as `@State`/`@StateObject`; intentional state seeds are documented as one-time
- iOS 17+: `@State` with `@Observable`; `@Bindable` for injected observables needing bindings
- `ForEach` uses stable identity (never `.indices`/`\.offset`; id outlives the view and isn't derived from mutable content)
- No closures stored in custom `@Environment`/`@FocusedValue` keys
- Custom `@Entry` default values are stable (no `Model()`/`Date()`/`UUID()` expressions)
- Version-specific APIs are gated with `#available` and have sensible fallbacks
- Previews use self-contained mock data; no dependency on live services or network

### Swift concurrency (`swift-concurrency`, Verification Checklist)

1. Re-check build settings before interpreting diagnostics.
2. Build and clear one category of errors before moving on. Do not batch unrelated fixes into the same change.
3. Run tests, especially actor-, lifetime-, and cancellation-sensitive tests.
5. Verify deallocation and cancellation behavior for long-lived tasks.
6. Check `Task.isCancelled` in long-running operations.
7. Never use semaphores or ad hoc locking in async contexts when actor isolation or `Mutex` would express ownership more safely.

### Swift Testing (`swift-testing-expert`, Agent behavior contract)

1. Prefer Swift Testing for Swift unit and integration tests.
2. Treat `#expect` as the default assertion and use `#require` when subsequent lines depend on a prerequisite value.
3. Default to parallel-safe guidance. If tests are not isolated, first propose fixing shared state before applying `.serialized`.
5. Recommend parameterized tests when multiple tests share logic and differ only in input values.
8. Only import `Testing` in test targets, never in app/library/binary targets.

### Per-task gate

- `make build` has no new warnings in touched files; `make test` is green.
- `grep -n "^\s*//" <touched .swift files>` finds no new comments.
- Every SwiftData test uses its own `ModelContainer(... isStoredInMemoryOnly: true)` - no shared container between tests.

## Testing Strategy

- **Unit tests** only (no UI/e2e tests in this repo). System seams stay behind protocols: the API provider is tested through a fake `AnthropicTransport` that replays SSE bytes; SwiftData through in-memory containers.
- Manual acceptance goes in Post-Completion.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix; blockers with ⚠️ prefix.
- Keep the plan in sync with the actual work.

## Solution Overview

- **Provider events.** `AIProvider.run` streams `ProviderEvent` instead of `String`: `.partial(String)` for live text (CLI only) and exactly one `.finished(ProviderResponse)` at the end. `ProviderResponse` carries `text` (what the overlay shows and pastes), `rawOutput` (the provider's unparsed output) and `stopReason: String?`. `AskEdithRunner.drive` maps `.partial` to `.streaming`, `.finished` to `.ready`, and returns a `DriveOutcome` so the caller can record it.
- **API request.** `output_config` is sent with `format` always and `effort` only when the prompt sets one. The provider accumulates `text_delta`s (no `.partial`), reads `stop_reason` (and the refusal category) from `message_delta`, and on `message_stop` decodes the JSON into `text`.
- **History.** One `@Model EditRun`; a MainActor `RunRecorder` over `ModelContainer.mainContext` writes at three moments: run start (`pending`), provider finished or failed, overlay resolved. Store errors are logged and never interrupt the fix flow.
- **Wiring.** `EdithApp.init` creates the container at an explicit URL, registers it with `AppDependencyManager`, and attaches it to the `MenuBarExtra` scene with `.modelContainer`. `AskEdithIntent` gets it through `@Dependency`.
- **Menu.** Two `@Query`s with `fetchLimit` 1 drive "Copy Last Result" (latest run with a result, dismissed ones included) and "Copy Last Original" (latest run of any outcome).

## Technical Details

### `EditRun` (SwiftData `@Model`)

| Property | Type | Notes |
|---|---|---|
| `createdAt` | `Date` | set at start; sort key |
| `promptPath` | `String` | as passed to the intent |
| `promptName` | `String?` | `AskEdithIntent.promptName(from:)` |
| `provider` | `String?` | `ProviderKind.rawValue`; nil when the prompt file failed to parse |
| `model` | `String?` | frontmatter value |
| `effort` | `String?` | frontmatter value |
| `original` | `String` | the selection |
| `rawOutput` | `String?` | provider output before parsing (also set for malformed / truncated replies) |
| `result` | `String?` | parsed text shown in the overlay |
| `stopReason` | `String?` | `end_turn`, `max_tokens`, `refusal`, ...; nil for CLI |
| `latencySeconds` | `Double?` | start of `drive` to `.finished` or error |
| `outcomeRaw` | `String` | `RunOutcome.rawValue`, exposed as `outcome: RunOutcome` computed property |
| `errorMessage` | `String?` | `localizedDescription` for `failed` |

`RunOutcome: String` = `pending`, `confirmed`, `dismissed`, `pasteFailed`, `failed`. Every property added later must be optional or have a default, so SwiftData's automatic lightweight migration applies.

### Store location

`FileManager` Application Support directory + `space.pkarpovich.edith/history.store`; create the directory before building the `ModelConfiguration(url:)`. The Homebrew cask's `zap` already removes that directory.

### API request body additions

```json
"output_config": {
  "effort": "medium",
  "format": {"type": "json_schema", "schema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"], "additionalProperties": false}}
}
```

`effort` key omitted when the frontmatter value is nil or empty.

### SSE `message_delta`

Payload shape: `{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_details":null},"usage":{...}}`. For refusals `stop_details` holds `{"type":"refusal","category":"...","explanation":"..."}`. New parser event: `.messageDelta(stopReason: String?, refusalCategory: String?)`.

### New `AIProviderError` cases

- `maxTokens(rawOutput: String)` - e.g. "Claude stopped at the token limit before finishing."
- `refusal(category: String?)` - e.g. "Claude declined the request (reasoning_extraction)."
- `malformedOutput(rawOutput: String)` - e.g. "Claude returned a reply Edith could not parse."

`max_tokens` is a failure even if the accumulated JSON parses. The recorder stores `rawOutput` from these cases.

### Outcome mapping

`OverlayCoordinator.Outcome` gains `.pasteFailed(String)`; `resolve` returns it when `Paster.paste` returns `false`. The intent maps `.confirmed` / `.pasteFailed` / `.dismissed` to `RunOutcome` and resolves the most recent run started by this coordinator (retries start new runs; earlier ones already ended as `failed`).

## Implementation Steps

### Task 1: Provider event contract

**Files:**
- Modify: `edith/AIProvider.swift`
- Modify: `edith/ClaudeCLIProvider.swift`
- Modify: `edith/MockProvider.swift`
- Modify: `edith/AskEdithRunner.swift`
- Modify: `edith/AskEdithIntent.swift` (call site only; no recording yet)
- Modify: `edithTests/AskEdithRunnerTests.swift`, `edithTests/MockProviderTests.swift`, `edithTests/ClaudeCLIProviderTests.swift`

- [x] in `AIProvider.swift` add `enum ProviderEvent: Sendable, Equatable { case partial(String); case finished(ProviderResponse) }` and `struct ProviderResponse: Sendable, Equatable { let text: String; let rawOutput: String; let stopReason: String? }`; change `run(prompt:model:effort:)` to return `AsyncThrowingStream<ProviderEvent, Error>`
- [x] `ClaudeCLIProvider`: after the process succeeds, yield `.partial(output)` then `.finished(ProviderResponse(text: output, rawOutput: output, stopReason: nil))`; error paths unchanged
- [x] `MockProvider`: same shape (`.partial` of the uppercased prompt, then `.finished` with it)
- [x] `AskEdithRunner.drive`: `.partial` appends to the running text and sets `.streaming`; `.finished` sets `.ready(original:result: response.text)`; the stream ending without `.finished` is `AIProviderError.truncatedStream`; return `enum DriveOutcome: Sendable, Equatable { case finished(ProviderResponse, latencySeconds: Double); case failed(message: String, rawOutput: String?, latencySeconds: Double); case cancelled }` (`rawOutput` taken from `maxTokens` / `malformedOutput` errors, nil otherwise); cancellation behavior stays as today (no state change, returns `.cancelled`)
- [x] update the test doubles in `AskEdithRunnerTests.swift` to the event stream; keep every existing behavior test (streaming partials, error, cancellation, chunk-then-error, infinite stream cancellation)
- [x] add tests: `.finished` text wins over accumulated partials; stream without `.finished` -> error state + `.failed`; `DriveOutcome` carries the response and a non-negative latency
- [x] `make generate && make test` - must pass before Task 2
- [x] ➕ `AnthropicAPIProvider` moved to the event contract as a bridge (`.partial` per `text_delta`, `.finished` on `message_stop`, `stopReason` nil) so the project compiles; Task 3 replaces this with the schema/JSON flow
- [x] ➕ `AIProviderError.rawOutput` added (returns nil for every case today); Task 3 must return the payload for `maxTokens` / `malformedOutput` so `DriveOutcome.failed` carries it
- [x] ➕ `AskEdithRunner.drive` is `@discardableResult`, so `AskEdithIntent` needed no change yet; `ClaudeCLIProvider.events(for:)` extracted to test the CLI event shape without a subprocess
- [x] ➕ Xcode 27 (27A266a) broke the test build before this change (`#ConformanceIsolation` on test `KeychainBackend` fakes, `#ActorIsolatedCall` in `InlineDiffTests`); fixed test-only: fakes marked `nonisolated`, three InlineDiff tests marked `@MainActor`
- [x] ➕ note: `make generate` with the local xcodegen rewrites `edith.xcscheme` (version, `Edith.app` -> `edith.app`); that churn is reverted with `git checkout -- edith.xcodeproj` before committing unless a file was added/removed

### Task 2: SSE parser reads `message_delta`

**Files:**
- Modify: `edith/AnthropicSSEParser.swift`
- Modify: `edithTests/AnthropicSSEParserTests.swift`

- [x] add `Event.messageDelta(stopReason: String?, refusalCategory: String?)`; parse `event: message_delta` payloads per Technical Details; malformed JSON logs and yields nothing (same as other events)
- [x] keep ignoring `thinking_delta` / `signature_delta` and every other event name
- [x] tests (parameterized where inputs differ only): `end_turn`, `max_tokens`, `refusal` with category, `refusal` without `stop_details`, a `thinking_delta` chunk produces no event, `message_delta` split across two `feed` calls
- [x] `make test` - must pass before Task 3
- [x] ➕ `AnthropicAPIProvider` switch gained `case .messageDelta: continue` so it compiles; Task 3 consumes the event. `refusalCategory` is read only when `stop_details.type == "refusal"`; the old `message_delta` entry was removed from the skipped-events test

### Task 3: API provider sends effort + schema and returns parsed JSON

**Files:**
- Modify: `edith/AnthropicAPIProvider.swift`
- Modify: `edith/AIProvider.swift` (new error cases)
- Modify: `edithTests/AnthropicAPIProviderTests.swift`

- [ ] `buildRequest(apiKey:prompt:model:effort:)`: add `output_config` per Technical Details (`effort` only when non-empty); delete `warnEffortIgnoredOnce` and `effortWarningLogged`
- [ ] streaming: accumulate `text_delta`s without yielding `.partial`; remember `stopReason` / `refusalCategory` from `.messageDelta`; on `.messageStop`: `refusal` -> throw `.refusal(category:)`; `max_tokens` -> throw `.maxTokens(rawOutput:)`; otherwise decode the accumulated string as `{"text": String}` (use `Decodable` + `JSONDecoder`, not `JSONSerialization`) and yield `.finished(ProviderResponse(text:rawOutput:stopReason:))`; decode failure or empty `text` -> `.malformedOutput(rawOutput:)`; no text at all -> existing `.emptyOutput`
- [ ] add the three `AIProviderError` cases with `errorDescription` strings per Technical Details
- [ ] tests via the fake transport: body contains `output_config.format` schema always and `effort` only when given (parameterized nil / "" / "medium"); happy path returns `text` and `rawOutput`; `max_tokens` with valid JSON still fails; refusal carries category; invalid JSON and JSON without `text` fail as malformed; existing HTTP-error and missing-key tests still pass
- [ ] `make test` - must pass before Task 4

### Task 4: `EditRun` model and `RunRecorder`

**Files:**
- Create: `edith/EditRun.swift`
- Create: `edith/RunRecorder.swift`
- Create: `edithTests/RunRecorderTests.swift`

- [ ] `EditRun.swift`: `@Model final class EditRun` with the properties from Technical Details, `enum RunOutcome: String, Sendable, CaseIterable`, and two `static` `FetchDescriptor<EditRun>` factories used by both the menu and tests: `latestRun` (sorted `createdAt` desc, `fetchLimit` 1) and `latestRunWithResult` (same + `#Predicate { $0.result != nil }`)
- [ ] `RunRecorder.swift`: `@MainActor final class RunRecorder` initialized with a `ModelContext`; API: `start(promptPath:promptName:provider:model:effort:original:) -> EditRun`, `finish(_ run: EditRun, with outcome: DriveOutcome)` (sets `rawOutput`, `result`, `stopReason`, `latencySeconds`, `outcome` stays `pending` on success / becomes `failed` + `errorMessage` on failure; `.cancelled` changes nothing - cancellation only happens when the overlay closes, and `resolve` records that), `recordFailure(promptPath:promptName:original:message:)` for prompt-file errors (single insert, outcome `failed`), `resolve(_ run: EditRun, as outcome: RunOutcome)`; every mutating call saves the context, catching and logging errors via `Logger.edith` (never throws to the caller)
- [ ] tests with an in-memory container: start -> finish(success) -> resolve(confirmed) persists all fields; finish(failed) keeps `rawOutput` and message; `recordFailure` writes a `failed` run with nil provider; two runs from a retry are two rows; `latestRunWithResult` skips a newer failed run; `latestRun` returns the newest regardless of outcome
- [ ] `make generate && make test` - must pass before Task 5

### Task 5: Container wiring and recording in the intent

**Files:**
- Modify: `edith/EdithApp.swift`
- Modify: `edith/AskEdithIntent.swift`
- Modify: `edith/OverlayCoordinator.swift`
- Create: `edith/HistoryStore.swift`
- Modify: `edithTests/AskEdithIntentTests.swift`

- [ ] `HistoryStore.swift`: `enum HistoryStore` with `static func makeContainer(at url: URL) throws -> ModelContainer`, `static var defaultURL: URL` (Application Support + `space.pkarpovich.edith/history.store`, creating the directory), and `static func makeInMemoryContainer() throws -> ModelContainer`
- [ ] `EdithApp.init`: build the container at `defaultURL`; on failure log with `Logger.edith.error` and fall back to the in-memory container (the app must still fix text); register it with `AppDependencyManager.shared.add(dependency: container)`; attach it to the `MenuBarExtra` scene with `.modelContainer(container)`
- [ ] `OverlayCoordinator.Outcome`: add `.pasteFailed(String)`, returned by `resolve` when `Paster.paste` returns `false`
- [ ] `AskEdithIntent`: `@Dependency private var container: ModelContainer`; create a `RunRecorder(context: container.mainContext)` on the main actor; prompt-file errors -> `recordFailure`; inside the `drive` closure: `start(...)` before `AskEdithRunner.drive`, then `finish(run, with: outcome)`, and keep the latest run in a MainActor-owned variable the closure updates; after `present` returns, map the coordinator outcome to `RunOutcome` and `resolve` the latest run (skip if it is already `failed`)
- [ ] extract the outcome mapping as a `nonisolated static func runOutcome(for: OverlayCoordinator.Outcome) -> RunOutcome` and test it (parameterized); existing `AskEdithIntentTests` keep passing
- [ ] `make generate && make build && make test` - must pass before Task 6

### Task 6: Copy Last Result / Copy Last Original menu items

**Files:**
- Modify: `edith/EdithApp.swift`
- Create: `edithTests/HistoryMenuTests.swift`

- [ ] in `MenuBarContent`: `@Query(EditRun.latestRun)` and `@Query(EditRun.latestRunWithResult)`; after the Accessibility block add a `Divider` and two buttons "Copy Last Result" and "Copy Last Original", each `.disabled` when its query is empty; actions are methods (no inline closures) that write the text to `NSPasteboard.general` via `clearContents()` + `setString(_:forType: .string)`
- [ ] extract the copy step as a small testable function taking an `NSPasteboard` (use a uniquely named `NSPasteboard(name:)` in tests, released after)
- [ ] tests: copy writes exactly the run's `result` / `original`; with an in-memory container the two descriptors return the expected rows for a mix of confirmed, dismissed and failed runs
- [ ] `make generate && make test` - must pass before Task 7

### Task 7: Verify acceptance criteria

- [ ] every Overview item is implemented; non-goals were not touched
- [ ] a failed store (in-memory fallback) still lets a fix run end to end in a manual run
- [ ] `make build && make test` green
- [ ] manual acceptance from Post-Completion done by the user (record the result here)

### Task 8: [Final] Update documentation

- [ ] no README/CLAUDE.md exists in this repo - nothing to update unless one was added meanwhile
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion

*Manual steps outside the repo; no checkboxes.*

**Prompt files in `$HOME/.config/edith/`** (outside the repo, not reachable from a sandboxed executor):

- `fix-ru.txt`: frontmatter `model: claude-sonnet-5-5`, `effort: medium`, `provider: api`. In the body replace the sentence "Your reply is pasted straight into the chat in place of the original, so it contains only the corrected message: no quotes, no preface, no comments." with "The text field of your answer is pasted straight into the chat in place of the original, so it holds only the corrected message: no quotes, no preface, no comments." (the wording evaluated with the schema). A backup of the pre-2026-09-29 haiku prompt is `fix-ru.txt.bak-2026-09-29`.
- `fix-en.txt`: `model: claude-sonnet-5-5`; keep `effort: low` (valid on Sonnet 5.5, within the user's cap of medium). Its prompt was tuned for Haiku and is not evaluated on Sonnet 5.5.
- `test-api.txt`: switch `model` to `claude-sonnet-5-5` or delete it - it points at Haiku.

**Manual acceptance (the user's real scenario):**

1. Select `да, про приоритет, он несколько тикетов понизил даже` in a chat, run "Edith - Fix RU": the overlay shows only the corrected message (no "Hmm, wait"), Enter pastes it.
2. Run it on another message and press esc; the menu's "Copy Last Result" puts the corrected text on the clipboard, "Copy Last Original" the original.
3. `sqlite3 "$HOME/Library/Application Support/space.pkarpovich.edith/history.store" "select ZORIGINAL, ZRESULT, ZOUTCOMERAW, ZSTOPREASON from ZEDITRUN order by ZCREATEDAT desc limit 2"` shows both runs (`confirmed`, `dismissed`, `end_turn`).
4. "Edith - Fix EN" works on Sonnet 5.5.
