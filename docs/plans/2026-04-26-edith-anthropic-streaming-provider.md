# Edith — Anthropic API Streaming Provider

## Overview

Add a second `AIProvider` implementation: `AnthropicAPIProvider` that talks to `api.anthropic.com/v1/messages` directly over HTTP with `stream: true`. No `claude` CLI involved. Eliminates the ~5-second cold-start overhead of the CLI and gives the user a live-typing UX in the overlay because tokens stream in instead of appearing all at once at the end.

The user picks which provider runs each Shortcut by adding `provider:` to the prompt-file frontmatter. The existing `ClaudeCLIProvider` stays as the default (matches today's behavior; no migration needed for existing prompt files).

**Why streaming first**: cold-call latency to the API is ~500-1000 ms before the first token. Without streaming the overlay sits empty for that plus generation time. Streaming makes the response feel instant — first words appear in <1 s, then keep flowing.

**Out of scope** (deferred to later):

- Reasoning / extended-thinking budget (`effort`) for the API provider — mapping `effort` aliases to `thinking.budget_tokens` adds complexity and only helps reasoning-capable models. For now `effort` is silently ignored when `provider: api`, with a one-time log warning.
- Keychain-based API key storage. Phase 3.5+ — for now we read `ANTHROPIC_API_KEY` from the user's environment.
- System prompt support (`system:` frontmatter field).
- Multi-turn / conversation history.
- Image / vision input.
- Retry / rate-limit backoff. We surface rate-limit as a one-shot error in the overlay; user retries manually.

## Context (from discovery)

- **`AIProvider` protocol** lives in `edith/AIProvider.swift:3-5`: today it's `func run(prompt: String, model: String?, effort: String?) async throws -> String` — single-shot return. This needs to become a streaming surface.
- **`ClaudeCLIProvider`** (`edith/ClaudeCLIProvider.swift`) and **`MockProvider`** (`edith/MockProvider.swift`) both implement the current protocol and must be migrated.
- **`OverlayState`** (`edith/OverlayState.swift`) currently has cases `processing(original)`, `ready(original, result)`, `error(original, message)`. Streaming needs a new in-progress state that carries accumulating text.
- **`OverlayView`** renders these states; new state needs UI.
- **`AskEdithRunner.drive`** (`edith/AskEdithRunner.swift`) calls the provider and flips overlay state. With streaming it needs to consume chunks and update state incrementally.
- **`AskEdithIntent.prepare`** (`edith/AskEdithIntent.swift:72-84`) builds a `PreparedPrompt`. It needs to also carry the chosen provider kind, parsed from frontmatter.
- **`PromptDefinition`** (`edith/PromptDefinition.swift`) parses frontmatter; today it knows `model` and `effort`. Add `provider`.
- **Anthropic Messages API** reference (verified 2026-04-26):
    - Docs: https://platform.claude.com/docs/en/api/messages and https://platform.claude.com/docs/en/api/messages-streaming (the older `docs.anthropic.com` URLs now 301-redirect to `platform.claude.com`).
    - Endpoint: `POST https://api.anthropic.com/v1/messages`.
    - Required headers: `x-api-key: <key>`, `anthropic-version: 2023-06-01` (still current as of 2026-04-26 — confirmed across docs and curl examples), `content-type: application/json`. For streaming also `accept: text/event-stream`.
    - Required body fields: `model`, `max_tokens`, `messages`. Optional: `stream`, `system`, `temperature`, `top_p`, `top_k`, `stop_sequences`, `tools`, `tool_choice`, `thinking`, `metadata`. We use `model`, `max_tokens`, `messages`, `stream: true` only.
    - Streaming SSE events we must handle (per https://platform.claude.com/docs/en/api/messages-streaming):
        - `message_start` — full message envelope (we ignore content, may log).
        - `content_block_start` — block index + initial content type (ignore for text-only).
        - `content_block_delta` with `delta.type == "text_delta"` and `delta.text: String` — the only deltas we care about. Other `delta.type` values (`input_json_delta`, `thinking_delta`, `signature_delta`) appear only when tools / extended-thinking are in use; we don't use either, so the parser must skip them gracefully if they ever appear.
        - `content_block_stop` — ignore.
        - `message_delta` — top-level changes (final `stop_reason`, cumulative `usage`); ignore for now.
        - `message_stop` — terminal event for the parser.
        - `ping` — keepalive, ignore.
        - `error` — `{"type":"error","error":{"type":"...","message":"..."}}`. Surface as `AIProviderError.apiError`.
    - Verbatim event examples from the docs:
        - `event: content_block_delta`
          `data: {"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "ello frien"}}`
        - `event: error`
          `data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}`
    - Verbatim minimal curl example from the docs:
      ```
      curl https://api.anthropic.com/v1/messages \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d '{
          "model": "claude-opus-4-7",
          "max_tokens": 1024,
          "messages": [{"role":"user","content":"Hello, Claude"}]
        }'
      ```
    - Versioning policy (https://platform.claude.com/docs/en/api/versioning) explicitly states: "new event types may be added, and your code should handle unknown event types gracefully" — our parser must not throw on unknown event names.

## Development Approach

- **Automation boundary**: ralphex writes Swift, unit tests, runs `xcodebuild build` / `xcodebuild test`. Anything that requires running the app, hitting the live Anthropic API, exercising target apps, or setting an API key in the environment is a user smoke test.
- **Testing approach**: regular. Pure logic (SSE parser, model alias map, frontmatter additions) gets full unit coverage. The HTTP layer is exercised through an injectable transport so we can replay recorded SSE streams in tests. Live network calls are user-only.
- **CRITICAL: every task MUST add or update unit tests** for the pure code introduced.
- **CRITICAL: all tests must pass and `xcodebuild build` must succeed before starting the next task.**
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy

- **Unit tests**: SSE event parser (well-formed, malformed, partial buffers split across reads, mixed event types, error event), model-alias resolver (`haiku` → `claude-haiku-4-5`, full names pass through), frontmatter `provider:` parsing (default, `cli`, `api`, unknown), runner consumes chunks and transitions overlay state, error mapping for HTTP statuses (401, 429, 500), missing API key.
- **Manual smoke tests** (Post-Completion): real API calls in TextEdit / Telegram / Chrome / Slack / Mail; visual check that text streams in token by token; cancellation mid-stream; missing-key path.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document issues/blockers with ⚠️ prefix.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): ralphex-automatable.
- **Post-Completion** (no checkboxes): user smoke tests against the real API and target apps.

## Implementation Steps

### Task 1: Streaming AIProvider protocol with existing providers migrated

- [x] change `edith/AIProvider.swift` so `run` returns `AsyncThrowingStream<String, Error>` instead of `async throws -> String`; each yielded String is a **delta** (the new tokens), not the accumulated result; document the contract in the protocol's leading comment line
- [x] update `edith/MockProvider.swift` to expose the same shape: yields the prompt uppercased as a single chunk and finishes (so existing call sites get equivalent behavior)
- [x] update `edith/ClaudeCLIProvider.swift` to also yield one terminal chunk with the full collected output, then finish; nothing about the CLI invocation changes
- [x] update unit tests for both providers to consume the stream and assert the joined output equals the expected single string; add a test asserting MockProvider yields exactly one element
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 2

### Task 2: OverlayState gets a streaming case

- [x] in `edith/OverlayState.swift`, add `case streaming(original: String, partial: String)`; equality / sendability mirrors the existing cases
- [x] in `edith/OverlayView.swift`, render `.streaming` similar to `.ready` (two-pane layout: original left, partial right) plus a small "streaming…" indicator under the right pane; key handling same as `.processing` (Esc dismisses, Enter is no-op until `.ready`)
- [x] update unit tests for any `OverlayState`-touching helpers (equality, transitions if any)
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 3

### Task 3: Runner consumes chunks and updates overlay incrementally

- [x] update `edith/AskEdithRunner.drive` to iterate the provider's `AsyncThrowingStream`; on first chunk, transition from `.processing` to `.streaming(original, partial)`; on each subsequent chunk, append the delta to `partial` and republish `.streaming`; on stream completion, transition to `.ready(original, finalText)`
- [x] cancellation path: if Task is cancelled mid-stream, terminate without flipping state to anything terminal (overlay dismissal handled by coordinator already)
- [x] error path: any thrown error during iteration → existing `.error(original, message)` mapping via `format(error:)`; map a new `AIProviderError` case if needed (see Task 5)
- [x] write unit tests using a synthetic `AIProvider` that yields a known sequence of chunks, then asserts overlay model state went `.processing → .streaming(partial="he") → .streaming(partial="hello") → .ready(result="hello")` etc. Use a TestOverlayStateModel helper if one doesn't already exist
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 4

### Task 4: SSE event parser and Anthropic model alias map

- [x] add `edith/AnthropicSSEParser.swift`: a stateful parser that consumes `Data` chunks (or `String` lines, whichever is more natural in Swift) and yields semantic events. Cases to model: `textDelta(String)` for `content_block_delta` with `delta.type == "text_delta"`; `messageStop` for `message_stop`; `error(type: String, message: String)` for `error`; everything else is dropped without yielding anything (must NOT throw on unknown event names — see versioning policy)
- [x] handle SSE framing: events separated by blank lines; each event has `event: <name>` line and one or more `data: <json>` lines (concatenate `data:` payloads when multiline); chunks from the network may split mid-event so the parser must buffer until it sees `\n\n`
- [x] add `edith/AnthropicModels.swift`: a small enum / map resolving aliases to API model IDs. Aliases handled: `haiku → claude-haiku-4-5`, `sonnet → claude-sonnet-4-6`, `opus → claude-opus-4-7`. Anything else passes through unchanged so users can pin specific dated models like `claude-haiku-4-5-20251001`
- [x] write unit tests for the SSE parser: well-formed `text_delta` event yields `textDelta`; multi-line `data:` concatenated; partial buffer (call `feed` twice with the second half) eventually yields the right event; `error` event yields `error(type, message)` with values from the verbatim example in Context; `ping` event produces no output; unknown event name (e.g. `event: future_thing`) produces no output and does NOT throw; `content_block_delta` with `delta.type == "input_json_delta"` (tool delta we don't care about) is silently dropped; malformed JSON in `data:` is logged and parser keeps going; completely empty input yields no events
- [x] write unit tests for the alias map: each alias resolves to expected ID, full model ID `claude-haiku-4-5-20251001` passes through unchanged, empty / nil handled
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 5

### Task 5: AnthropicAPIProvider with injectable transport

- [x] add `edith/AnthropicTransport.swift`: a small protocol abstracting the HTTP roundtrip. Method something like `func openStream(request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>)`. Real implementation `URLSessionAnthropicTransport` uses `URLSession.shared.bytes(for:)` and bridges into `Data` chunks
- [x] add `edith/AnthropicAPIProvider.swift` conforming to `AIProvider`. In `run`:
    - read `ANTHROPIC_API_KEY` from `ProcessInfo.environment`; missing → throw new `AIProviderError.missingApiKey`
    - build `URLRequest` to `https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`, `accept: text/event-stream`
    - JSON body: `{ "model": resolved_model, "max_tokens": 4096, "stream": true, "messages": [{"role":"user","content": prompt}] }` where `resolved_model` is `AnthropicModels.resolve(model)` (default `claude-sonnet-4-6` when `model == nil`)
    - if `effort` is non-nil, log a one-time warning that effort is ignored for the API provider in this phase
    - call `transport.openStream`; on non-2xx HTTP status, drain a small body and throw a structured error (see below); on 2xx, feed the byte stream into `AnthropicSSEParser` and yield each `contentBlockDelta(text)` as a delta on the returned `AsyncThrowingStream`; on `error` event, throw `AIProviderError.apiError(...)`
    - propagate cancellation: when the consumer cancels, cancel the underlying URLSession task
- [x] extend `edith/AIProvider.swift` `AIProviderError` with two new cases: `missingApiKey` and `apiError(status: Int, type: String, message: String)`; update `AskEdithRunner.format(error:)` to render friendly strings for both
- [x] write unit tests using a fake transport that returns a canned `AsyncThrowingStream<Data, Error>` from a fixture SSE payload; assert provider yields the expected text deltas in order. Cover: happy path with two text-delta events, HTTP 401 → `apiError(status: 401, ...)`, HTTP 429 → `apiError(status: 429, ...)`, missing API key (test by injecting an env reader) → `missingApiKey`, server-sent `error` event → `apiError`
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 6

### Task 6: Provider selection via frontmatter and intent dispatch

- [x] extend `edith/PromptDefinition.swift` to parse a `provider:` frontmatter key with values `cli` (default) or `api`. Unknown values fall back to `cli` with a logged warning
- [x] in `edith/AskEdithIntent.swift`, extend `PreparedPrompt` with `provider: ProviderKind` (a small enum local to this file or a shared type — caller's preference); `prepare(path:selection:)` populates it from the parsed definition
- [x] in `AskEdithIntent.perform()`, replace the hard-coded `ClaudeCLIProvider()` instantiation with a small factory: `cli` → `ClaudeCLIProvider()`, `api` → `AnthropicAPIProvider(transport: URLSessionAnthropicTransport())`
- [x] write unit tests for `PromptDefinition.parse` covering the new `provider:` field (missing → cli, `cli`, `api`, unknown → cli with warning) and for `AskEdithIntent.prepare` returning the right `provider` value
- [x] write a unit test that injects a fake provider into the intent runner path (if practical) showing the `api` branch is taken when frontmatter requests it; if intent factory is hard to inject, document the manual smoke test path instead — covered by `makeProviderReturnsAnthropicAPIForApi` which asserts the factory returns the correct concrete type for the `.api` kind
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 7

### Task 7: Verify automated acceptance criteria

- [ ] `xcodebuild -scheme edith build` passes with zero warnings
- [ ] `xcodebuild -scheme edith test` passes with all unit tests green
- [ ] all task checkboxes above are `[x]`
- [ ] no `TODO` / `FIXME` left in files created or modified in Tasks 1–6

## Technical Details

- **API endpoint**: `POST https://api.anthropic.com/v1/messages` (https://platform.claude.com/docs/en/api/messages).
- **Required headers**: `x-api-key: $ANTHROPIC_API_KEY`, `anthropic-version: 2023-06-01` (https://platform.claude.com/docs/en/api/versioning), `content-type: application/json`. For streaming additionally `accept: text/event-stream`.
- **Request body**: `{"model":"<id>","max_tokens":4096,"stream":true,"messages":[{"role":"user","content":"<rendered prompt>"}]}`. `max_tokens=4096` is comfortable headroom for our text-fix workflows; if the model truncates we'll see it in smoke tests and bump.
- **SSE events** (full list and verbatim examples in the Context section above; https://platform.claude.com/docs/en/api/messages-streaming):
    - We **emit** on `content_block_delta` whose `delta.type == "text_delta"`, yielding `delta.text` as the chunk.
    - We **terminate** on `message_stop` (clean) or `error` (throw).
    - We **silently skip** `message_start`, `content_block_start`, `content_block_stop`, `message_delta`, `ping`, and any `content_block_delta` whose `delta.type` is not `text_delta` (`input_json_delta`, `thinking_delta`, `signature_delta` — only relevant if tools / extended-thinking are in use, which we never enable).
    - We **must tolerate unknown event names** without throwing — Anthropic's versioning policy reserves the right to add new event types.
- **Why a custom SSE parser instead of an off-the-shelf SDK**: zero-dependency, ~80 lines, fully testable. The official `anthropic-sdk-swift` exists but pulls in OpenAPI-generated client code we don't need; for a personal utility, lean is better.
- **Cancellation**: `URLSession.bytes(for:)` returns `(URLSession.AsyncBytes, URLResponse)`. When the outer `AsyncThrowingStream` is cancelled, we close the byte iterator and call `cancel()` on the task. SSE parser stops emitting.
- **Model alias resolution**: hard-coded map in `AnthropicModels`. When Anthropic releases a new generation, this is the one place to bump. Anything not in the map passes through, so users can pin a dated model in frontmatter (`model: claude-haiku-4-5-20251001`) without code changes.
- **Streaming chunk semantics**: each yielded value from `AIProvider.run` is a **delta** (only the new text). Runner accumulates. `OverlayState.streaming(original, partial)` carries the accumulated `partial`.
- **`effort` for API provider**: silently ignored in this phase, logged once per process invocation. Future Phase will map to `thinking.budget_tokens` when reasoning-capable models are in play.
- **No `--bare` / no env filtering needed**: API provider runs in-process; no subprocess; `ANTHROPIC_API_KEY` is read from the env (and not filtered out, since filtering only made sense to keep the CLI on OAuth).

## Post-Completion

*Smoke tests requiring a real `ANTHROPIC_API_KEY`, the live Anthropic API, the running app, and target apps. Ralphex does not run the app or hit the network.*

**Pre-flight (one time):**

- Generate an API key at console.anthropic.com → API Keys.
- Export it where the menu-bar app will see it. Easiest path: launch Xcode from a shell where `ANTHROPIC_API_KEY` is exported (so the Run-from-Xcode child process inherits it). For a long-term solution, set it via `launchctl setenv ANTHROPIC_API_KEY ...` in `~/Library/LaunchAgents/<your-key-loader>.plist` so the app sees it regardless of how it's launched.
- Verify in Console.app under `subsystem:space.pkarpovich.edith` that the env is visible: trigger any Shortcut and look for the "missingApiKey" error if it isn't.
- Add a test prompt file `~/.config/edith/test-api.txt`:
    ```
    # Smoke test: Anthropic API streaming.
    ---
    provider: api
    model: haiku
    ---
    Convert the text below to UPPERCASE. Respond with ONLY the uppercase version.

    {{selection}}
    ```
- Bind a Shortcut to that file (e.g. `Hyper+Shift+E`).

**After Task 6 — happy path with streaming visible:**

- TextEdit, type a longer phrase like `the quick brown fox jumps over the lazy dog`, select, hit the new hotkey.
- Overlay opens immediately with original on the left and a spinner on the right.
- Within ~500–1000 ms the right pane starts filling **token by token** with `THE QUICK BROWN FOX...` (visibly streaming, not appearing all at once like `provider: cli` does).
- When the stream finishes, Enter pastes the full uppercase text.

**Latency comparison:**

- Same prompt file with `provider: cli` vs `provider: api` — record end-to-end perceived time. API should win by 3-5 seconds easily.

**Cancellation:**

- Trigger the Shortcut on a long input (e.g. a paragraph). Hit Esc while text is still streaming. Overlay dismisses; in Console there should be no error logs (cancellation is clean).

**Error paths:**

- Unset `ANTHROPIC_API_KEY` in the running app's env (relaunch from a shell without it). Trigger Shortcut → overlay shows `.error` "Anthropic API key missing — set ANTHROPIC_API_KEY".
- Set `ANTHROPIC_API_KEY` to garbage. Trigger → overlay shows `.error` from a 401 response with the API's message.
- Use up rate limit (low-tier key + many calls in quick succession). Trigger → overlay shows `.error` from a 429.

**Cross-app verification matrix (with `provider: api`):**

| App                   | Prompt file       | Result OK? | Streaming visible? |
|-----------------------|-------------------|------------|---------------------|
| TextEdit              | test-api.txt      |            |                     |
| Telegram Desktop      | test-api.txt      |            |                     |
| Chrome (Docs)         | fix-en.txt + api  |            |                     |
| Slack                 | fix-en.txt + api  |            |                     |
| Mail (compose)        | reply.txt + api   |            |                     |

**Future follow-ups (informational, not in this plan):**

- Map `effort` to `thinking.budget_tokens` for reasoning-capable models.
- Keychain storage of the API key with a Settings UI for rotation (replace the env-var dependency).
- `system:` frontmatter field, passed as the API's `system` parameter.
- Retry with exponential backoff on transient 5xx / network errors.
- Image / vision input via `{{clipboard_image}}` variable + multipart message content.
