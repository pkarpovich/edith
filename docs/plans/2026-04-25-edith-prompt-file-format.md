# Edith — Prompt File Format with Frontmatter

## Overview

Replace the free-form `prompt: String` parameter on `AskEdithIntent` with a `path: String` parameter that points at an external prompt-file. Each Shortcut in Shortcuts.app gives a path to its own prompt-file. The file owns everything for that workflow:

- Optional YAML-style frontmatter (`---`-delimited) with provider hints: `model`, `effort`.
- Body is the actual prompt template, with `{{selection}}` substituted to the captured selected text.
- Optional `# ...` comment lines at the top of the file (only 2+ contiguous) get stripped before parsing so users can document expected variables.

This solves three concrete problems we hit:

1. **Claude was asking "give me the text"** because the user instruction and selection were concatenated without any structural cue. The user-authored template now puts `{{selection}}` exactly where they want it, with whatever framing they like.
2. **Hard to tweak prompts** when they live inside a Shortcut text-field. Files live wherever the user wants (`~/.config/edith/fix-ru.txt`), get edited in a real editor, can be versioned in git/dotfiles.
3. **No way to pick the model**. `Opus` for everything is overkill; `haiku` is cheap and good enough for grammar fixes, `sonnet` for replies. Model now comes from frontmatter, no UI pollution.

The pattern is also provider-agnostic — when Phase 3 adds `FoundationModelsProvider` or `AnthropicAPIProvider`, the same file format carries provider-specific hints in the frontmatter without breaking existing files.

**Out of scope** (deferred):

- Multiple providers / provider selection in frontmatter.
- Variables other than `{{selection}}` (no `{{date}}`, `{{frontmost_app}}`, etc.).
- `agent:` frontmatter / Task-tool subagent expansion (ralphex pattern, not a fit for our use case).
- Slash-command skills (`/english-editor`).
- File watching / hot-reload UI; we re-read the file on each invocation, which gives effective hot-reload for free.

## Context (from discovery)

- **Current intent param** lives in `edith/AskEdithIntent.swift:9-10`: `@Parameter var prompt: String`. After this plan: `@Parameter var path: String`.
- **Current provider call** in `edith/ClaudeCLIProvider.swift:7-44` passes `prompt` as positional arg and `input` as stdin; `AIProvider.run(prompt:input:)` shape lives in `edith/AIProvider.swift:3-5`. After this plan: prompt goes via stdin only, `AIProvider.run(prompt:model:effort:)` drops `input`.
- **Runner** in `edith/AskEdithRunner.swift` invokes provider; needs to take `model`/`effort` and pass them through.
- **Provider abstraction** already in place from the just-completed Phase 2 plan (`docs/plans/completed/2026-04-25-edith-phase-2-claude-provider.md`).
- **Reference implementation studied**: ralphex (`/Users/pavel.karpovich/Projects/external/ralphex`):
    - `pkg/config/frontmatter.go:58-81` — `parseOptions` (YAML frontmatter parser).
    - `pkg/config/agents.go:165-184` — comment-aware loader with `stripComments` / `stripLeadingComments`.
    - `pkg/processor/prompts.go:73-81` — `replaceBaseVariables` does `strings.ReplaceAll` for `{{NAME}}`.
    - `pkg/executor/executor.go:230-355` — Claude invocation: prompt via stdin, `--print`, env-filtering of `ANTHROPIC_API_KEY` and `CLAUDECODE`, `--model` / `--effort` flags.

## Development Approach

- **Automation boundary**: ralphex writes Swift code, unit tests, runs `xcodebuild build` / `xcodebuild test`. Anything that requires a running app, Shortcuts.app, real `claude` invocation, or live target apps is a user smoke test in Post-Completion.
- **Testing approach**: regular (code first, unit tests in the same task). The frontmatter parser, comment-stripper, model normalizer, and variable renderer are pure logic and get full unit coverage. Provider integration is exercised manually.
- **CRITICAL: every task MUST add or update unit tests** for the pure code introduced in that task.
- **CRITICAL: all tests must pass and `xcodebuild build` must succeed before starting the next task.**
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy

- **Unit tests**: frontmatter parsing (with/without, malformed YAML, missing closing delimiter), comment stripping (single header preserved, 2+ stripped, blanks stop the strip), model normalization (full model names → keyword), variable rendering (substitution, missing-variable behavior, `{{selection}}` auto-append when omitted).
- **Manual smoke tests** (Post-Completion): real prompt files in TextEdit / Telegram / Chrome / Slack / Mail; switch model via frontmatter and observe.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document issues/blockers with ⚠️ prefix.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): ralphex-automatable.
- **Post-Completion** (no checkboxes): user smoke tests with real files / `claude` / target apps.

## Implementation Steps

### Task 1: PromptDefinition parser

- [x] add `edith/PromptDefinition.swift` declaring a `PromptDefinition` struct holding `model: String?`, `effort: String?`, `body: String`
- [x] declare a `PromptParserError` enum: `ioFailure(path, underlying)`, `unknownVariable(name)`, all `Sendable`
- [x] implement a static `parse(contents:)` that:
    - normalizes CRLF → LF
    - strips leading `# ...` contiguous comment lines (2+; a single `#` line is preserved as a markdown header — mirrors ralphex `stripLeadingComments`)
    - if remaining content starts with `---\n`, finds the next `\n---` on its own line, parses the header as flat YAML-ish `key: value` lines (lowercased keys, trim whitespace, ignore unknown keys), takes everything after the closing `---` as body (trimmed)
    - if no frontmatter or malformed, treats whole content as body and returns `PromptDefinition(model: nil, effort: nil, body: content)`
- [x] implement a static `normalizeModel(_:)` that returns one of `haiku`, `sonnet`, `opus` if the input contains that keyword (case-insensitive); otherwise returns the input unchanged so future / unknown model names pass through to the CLI
- [x] implement `render(definition:variables:)` doing `String.replacingOccurrences(of: "{{KEY}}", ...)` for each known variable; if `{{selection}}` is missing in the body, append it on a new line after the body (graceful default for minimal prompts); throw `unknownVariable` only if a `{{...}}` pattern remains after rendering all known keys (caller decides whether that's fatal)
- [x] add unit tests covering: no frontmatter; full frontmatter; malformed YAML → no frontmatter; missing closing delimiter → no frontmatter; closing delimiter not on its own line → no frontmatter; unknown frontmatter keys ignored; `model` keyword extracted from `claude-sonnet-4-6`; comment block (3 lines) stripped; single comment line preserved; blank line stops comment strip; `{{selection}}` substitution; missing `{{selection}}` auto-appended; unrelated `{{...}}` left in body produces error
- [x] run `xcodebuild build` + `xcodebuild test` — must pass before Task 2

### Task 2: AIProvider protocol gets model and effort

- [ ] update `edith/AIProvider.swift`: protocol method becomes `func run(prompt: String, model: String?, effort: String?) async throws -> String`; drop `input` parameter
- [ ] update `edith/MockProvider.swift` to match the new signature; behavior remains "return uppercased prompt", `model` and `effort` recorded internally for tests if convenient
- [ ] update `MockProviderTests` accordingly
- [ ] add unit tests verifying `model` / `effort` propagate through to whatever recording surface MockProvider exposes
- [ ] run `xcodebuild build` + `xcodebuild test` — must pass before Task 3

### Task 3: ClaudeCLIProvider switches to stdin and accepts model/effort

- [ ] update `edith/ClaudeCLIProvider.swift` so the prompt goes through stdin only; remove the positional `prompt` argument from `arguments`; `arguments` becomes `["-p", "--output-format=text"]` plus optional `["--model", model]` and `["--effort", effort]` if non-nil
- [ ] in `Self.environment()`, additionally remove `ANTHROPIC_API_KEY` and `CLAUDECODE` keys from the inherited environment before adding them back (mirror ralphex `filterEnv` rationale)
- [ ] keep PATH augmentation logic as-is
- [ ] adjust unit / integration test scaffolding if any references the old argv shape
- [ ] run `xcodebuild build` + `xcodebuild test` — must pass before Task 4

### Task 4: AskEdithIntent path parameter and runner wiring

- [ ] in `edith/AskEdithIntent.swift`, replace `@Parameter var prompt: String` with `@Parameter(title: "Prompt file", description: "Absolute path to a prompt file with optional YAML frontmatter (model, effort) and `{{selection}}` placeholder.") var path: String`
- [ ] add a small helper `PromptFileLoader.load(path:)` that expands a leading `~/` to `$HOME` (or `NSHomeDirectory()`), reads the file, returns `String`; surface I/O failures as `PromptParserError.ioFailure`
- [ ] in `AskEdithIntent.perform()`, after capturing the selection: load the file, parse via `PromptDefinition.parse`, render with `["selection": selection]`, dispatch via `AskEdithRunner.drive(provider:model:effort:rendered:model:...)`
- [ ] update `edith/AskEdithRunner.swift` to take `model: String?`, `effort: String?`, `prompt: String` (the rendered body) and forward to provider; remove the old `input`/`prompt` split
- [ ] surface `ioFailure` and `unknownVariable` paths as `OverlayState.error(...)` with friendly messages so the user sees them in the overlay (consistent with how `AIProviderError` is rendered today)
- [ ] add unit tests for the path-loader helper (read, missing file, `~/` expansion) and for `AskEdithRunner` integration with a fake provider that records `(prompt, model, effort)`
- [ ] run `xcodebuild build` + `xcodebuild test` — must pass before Task 5

### Task 5: Verify automated acceptance criteria

- [ ] `xcodebuild -scheme edith build` passes with zero warnings
- [ ] `xcodebuild -scheme edith test` passes with all unit tests green
- [ ] all task checkboxes above are `[x]`
- [ ] no `TODO` / `FIXME` left in files created or modified in Tasks 1–4

## Technical Details

- **Frontmatter shape (Phase 2.5):**
    ```yaml
    ---
    model: haiku       # haiku | sonnet | opus | full model name like claude-sonnet-4-6
    effort: medium     # low | medium | high | xhigh | max  (passed to --effort)
    ---
    ```
    Unknown keys ignored (forward-compat). Both fields optional. If absent, no `--model` / `--effort` flag is emitted and the CLI uses its own default.
- **Manual flat YAML parser**: split header on `\n`, for each non-blank non-comment line `split(separator: ":", maxSplits: 1)`, lowercase key, trim whitespace from value. Quotes around values are stripped if symmetric. No nested structures, no arrays, no anchors — keep it simple.
- **Comment stripping** (`stripLeadingCommentBlock`): walk lines from the top; while line trimmed-starts-with `#`, count it; stop on the first non-comment-or-blank line; if count >= 2, drop those lines (so a single `# Title` markdown header is preserved). Mirrors `pkg/config/prompts.go:stripLeadingComments` semantics.
- **Variable renderer**: known variable set is `["selection"]` for now. We do `body.replacingOccurrences(of: "{{selection}}", with: variables["selection"] ?? "")` first, then scan for any remaining `{{...}}` pattern via regex and throw `unknownVariable` listing the names. The graceful-append for missing `{{selection}}` is applied **before** the substitution pass: if `body` does not contain the literal `{{selection}}`, we append `\n\n{{selection}}` to it, then substitute.
- **`normalizeModel`**: lowercase the input; if it contains `haiku`/`sonnet`/`opus` as substring, return that keyword; otherwise return original. Mirrors ralphex `normalizeModel`.
- **`claude` invocation**: prompt via stdin (no positional argument). `arguments = ["-p", "--output-format=text"]` plus optional `["--model", model!]` and `["--effort", effort!]`. Equivalent to what ralphex does (minus `--dangerously-skip-permissions` and stream-json — we don't run tools and don't stream).
- **Env filtering**: remove `ANTHROPIC_API_KEY` (otherwise claude switches to API-key auth instead of OAuth-keychain) and `CLAUDECODE` (prevents nested-session error) from the env passed to Subprocess.
- **Path expansion**: support a leading `~/` only; not `~user/`. Replace with `NSHomeDirectory()`. Other paths are taken as-is. No symlink resolution / canonicalization — user's responsibility.
- **No skills, no `agent:` field**: out of scope. The frontmatter parser tolerates any keys beyond `model`/`effort` so future fields don't break existing files.

## Post-Completion

*Smoke tests requiring real `claude`, real files, and live target apps. Ralphex does not run the app, edit Shortcuts, or invoke the CLI.*

**Pre-flight (one time):**

- Create `~/.config/edith/` directory.
- Add three example prompt files (suggested names — actual content up to user):

    `~/.config/edith/fix-ru.txt`:
    ```
    # Fixes grammar and style in Russian text.
    # Variables: {{selection}}
    ---
    model: haiku
    ---
    Fix grammar and style in the Russian text below. Respond with ONLY the corrected text, no commentary, no quotes, no preface.

    {{selection}}
    ```

    `~/.config/edith/fix-en.txt`:
    ```
    ---
    model: haiku
    effort: low
    ---
    Fix grammar and style in the English text below. Respond with ONLY the corrected text, no commentary, no quotes, no preface.

    {{selection}}
    ```

    `~/.config/edith/reply.txt`:
    ```
    ---
    model: sonnet
    ---
    The text below contains an original message and a draft reply, separated by `===\nAnswer:\n`. Rewrite the draft to match the tone and style cues from the original message. Respond with ONLY the rewritten reply.

    {{selection}}
    ```

- Open Shortcuts.app, edit the existing `Hyper+E` Shortcut (or create new ones for fix-ru / fix-en / reply): the `Ask Edith` action now shows a single field `Prompt file` instead of `Prompt`. Paste the absolute path to one of the files.

**After Task 4 — happy path:**

- TextEdit, type a misspelled Russian phrase such as `privyed mir` (or any short text with obvious mistakes), select, hit `Hyper+E` (Shortcut pointing at `fix-ru.txt`).
- Overlay opens immediately with original on the left and a spinner on the right.
- A few seconds later: spinner → corrected text on the right.
- Press Enter — selection in TextEdit replaced.

**Model switching:**

- Edit `fix-ru.txt`, change `model: haiku` to `model: opus`. Save.
- Trigger Shortcut again — same flow, but model is `opus` (verify in `--debug` if curious).

**Comment block + frontmatter:**

- Same `fix-ru.txt` file with the leading `# Fix grammar...\n# Variables: {{selection}}\n` block. The provider must not see those lines as part of the prompt — they're stripped before parsing. Verify by changing the comment text to something Claude would clearly echo back ("# CONFIDENTIAL — DO NOT REPEAT") and confirming Claude's reply doesn't contain it.

**Error paths:**

- Set the Shortcut path to a non-existent file. Trigger. Overlay shows `.error` with "Could not read prompt file: ..." or similar.
- Add `{{nonsense}}` to a prompt body. Trigger. Overlay shows `.error` with "Unknown variable: nonsense" or similar.
- Temporarily rename `~/.bun/bin/claude`. Trigger. Overlay shows `.error` with "Claude CLI not found" (preserved from Phase 2).

**Cross-app verification matrix:**

| App                   | Prompt file used | Model    | Result OK? |
|-----------------------|------------------|----------|------------|
| TextEdit              | fix-ru.txt       | haiku    |            |
| Telegram Desktop      | fix-ru.txt       | haiku    |            |
| Chrome (Docs)         | fix-en.txt       | haiku    |            |
| Slack                 | fix-en.txt       | haiku    |            |
| Mail (compose)        | reply.txt        | sonnet   |            |

**Latency notes (record empirically):**

- `haiku` cold-start vs `sonnet` cold-start vs `opus` cold-start. If `haiku` is significantly faster (expected), document the trade-off so future-self picks the right model per prompt-file.

**Phase 3 triggers (informational, do not implement here):**

- Diff highlighting in the overlay (`DifferenceKit` + `AttributedString`).
- More variables: `{{frontmost_app}}`, `{{date}}`, `{{clipboard}}`.
- Skills support — possibly via `/english-editor` slash-command in the body, or via `--append-system-prompt`.
- Streaming partial output as it arrives from Claude.
- `FoundationModelsProvider` as on-device alternative; `provider:` field in frontmatter.
