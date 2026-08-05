# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.15.1] - 2026-08-05

### Fixed
- **Reviews now run axe-core** ([#131](https://github.com/lessthanseventy/excessibility/issues/131)). `mix excessibility.review` (and `Excessibility.Review`) scans both sides of every changed snapshot pair through the configured scanner and folds axe violations into the finding-delta — one finding per offending node, fingerprinted `{id, target}` — so a newly introduced critical (e.g. a button losing its accessible name) is `:block` and `--fail-on block` exits non-zero. If a scan fails (e.g. Playwright isn't installed) the review degrades to the LiveView rules and says so in the report's `:warnings`. Opt out with `--no-axe` (or `axe: false` in the API).
- **False `stylesheet failed to load` when a nested `@import` fails** ([#132](https://github.com/lessthanseventy/excessibility/issues/132)). Chromium fires an `error` event on a `<link>` whose sheet loaded fine but whose nested `@import` failed, which previously warned that the stylesheet was missing and invalidated the whole run's contrast findings. The warning is now gated on `link.sheet` (null exactly when the sheet did not load or parse); failing imports are surfaced separately and accurately as `stylesheet import failed: <url> — text metrics may differ from production`.
- **Telemetry capture no longer crashes on lists of Ecto structs** ([#133](https://github.com/lessthanseventy/excessibility/issues/133)). `Filter.filter_ecto_metadata/1` converts structs (dropping `__meta__`, `NotLoaded` becomes `nil`) instead of `Enum.reduce`-ing them, so index/detail LiveViews with `[%Schema{}]` assigns capture cleanly. Independently, `write_snapshots/1` now logs a timeline failure instead of raising out of the `on_exit` hook — instrumentation can no longer fail the test it observes.
- **`mix excessibility.compare` in non-interactive shells** ([#134](https://github.com/lessthanseventy/excessibility/issues/134)). Without `--keep`, a non-TTY stdin (CI, editor task runners) previously crashed on `:eof` deep in the prompt and leaked `.good.html`/`.bad.html` temp files. The task now refuses up front with the actual guidance (`--keep good|bad`), cleans up temp files even when resolution errors, and if stdin closes mid-run it keeps the baseline (fail-safe) instead of silently accepting the new version.

### Added
- **`node_modules_path` config** ([#135](https://github.com/lessthanseventy/excessibility/issues/135)). `@axe-core/playwright` now gets the same override → bundled → ambient resolution as Playwright, so `config :excessibility, node_modules_path: "assets/node_modules"` reuses a host `node_modules` (providing both `playwright` and `@axe-core/playwright`) and removes the `deps/excessibility/assets` npm install from the workflow entirely. Caveat: the host then pins the axe-core version, and `engine.axe_version` in reports follows it — an axe minor bump can change finding sets vs earlier baselines.

## [0.15.0] - 2026-08-05

### Added
- **`mix excessibility.review` — accessibility blast-radius report** ([#117](https://github.com/lessthanseventy/excessibility/pull/117)). Diffs every current snapshot against its baseline and reports, per view, the rendered regions that changed and the accessibility findings the change *newly introduced* (a finding-delta, so pre-existing issues aren't re-flagged), with a risk tier: `:block` (new critical/serious), `:review` (new moderate/minor or content changed without `aria-live`), `:auto` (rendering changed, nothing broke). `--fail-on block|review|never` controls the exit code. Public API: `Excessibility.Review.review/1`, `review_pairs/2`, `review_pair/4`.
- **Pluggable risk judge** ([#118](https://github.com/lessthanseventy/excessibility/pull/118)). `Excessibility.Review.Judge` turns a change into a verdict (tier, blast-radius summary, structured risks). Ships a transparent `Heuristic` judge (default) and an `LLM` judge where the host app injects the model call as a `completion` function — no HTTP dependency; a missing, erroring, raising, or malformed-output model always degrades to the heuristic. `mix excessibility.review --judge`.
- **MCP `diff_snapshots` tool** ([#119](https://github.com/lessthanseventy/excessibility/pull/119)). Lets an agent diff two rendered HTML states (before/after an edit) and get changed regions, newly introduced findings, and a tier — a blast-radius check for "did I change rendered behavior I didn't intend?".
- **Behavioral findings in reviews** ([#120](https://github.com/lessthanseventy/excessibility/pull/120)). `mix excessibility.review --timeline timeline.json` runs the telemetry analyzers (N+1 queries, dead assigns, render thrash, …) and folds their findings into the review; a critical analyzer finding fails the run like a serious accessibility regression. `Excessibility.Review.Behavioral` normalizes analyzer severities onto the review scale.
- **Multiple viewports per scan** ([#122](https://github.com/lessthanseventy/excessibility/issues/122)). `Excessibility.Scanner.scan(url, viewports: [{1440, 900}, {320, 800}])` runs axe once per width in a single browser session and returns per-viewport results, so WCAG 1.4.10 Reflow failures are actually exercised. Also available as `mix excessibility --viewports 1440x900,320x800` or the `:viewports` config key; screenshots are suffixed per viewport (`name.1440x900.png`). The single `:viewport` option keeps the flat report shape.
- **`:reveal_without_announcement`** ([#123](https://github.com/lessthanseventy/excessibility/issues/123)) — new LiveView rule flagging an initially hidden element (a `hidden` class/attribute or inline `display:none`) that is revealed from the server via a serialized `JS.show`/`JS.toggle` command — either its own `data-*` attribute (the `push_event("js-exec")` idiom) or another element's `phx-*` op whose `to` targets it — while exposing no `role="alert"`/`"status"`/`"log"`, `aria-live`, or live-region ancestor. axe-core cannot catch this because the element is hidden at rest. Severity `:serious`. Dialog targets (`role="dialog"`/`aria-modal`) are skipped.
- **Reuse an existing Playwright installation** ([#124](https://github.com/lessthanseventy/excessibility/issues/124)) via `config :excessibility, playwright_path: "..."`. Resolution order: override → bundled copy → ambient Node resolution. The bundled `playwright` is now pinned (`~1.58.2`) and `assets/package-lock.json` ships in the hex package, so a fresh install resolves the version the browsers were downloaded for. Chromium launch failures now include the exact directory-qualified `npx playwright install chromium` command.
- Scan reports gained a `:warnings` list ([#121](https://github.com/lessthanseventy/excessibility/issues/121)), surfaced by `mix excessibility` (even for passing files) and the MCP `a11y_check` tool — e.g. a linked stylesheet that failed to load, which invalidates contrast/layout findings.
- **Browser-assisted clipping detection** (follow-up to [#122](https://github.com/lessthanseventy/excessibility/issues/122)). `check_clipping: true` (or `mix excessibility --check-clipping`) measures interactive elements — `a`, `button`, `input`, `select`, `textarea`, `[phx-click]`, `[role="button"]` — whose visible width falls below `:clipping_ratio` (default `0.9`), and reports page-level horizontal overflow, per viewport. axe has no rule for a control that is technically in the DOM but only 6% visible; this is the actual user-facing WCAG 1.4.10 failure.

### Fixed
- **`html_snapshot/2` no longer kills LiveView tests** ([#125](https://github.com/lessthanseventy/excessibility/issues/125)). Capture-metadata assigns are now read from the LiveView channel process via `:sys.get_state/2` instead of sending `:get_state` to the test client proxy, which has no matching `handle_call/3` clause and crashed — taking the linked test down with it. Any failure degrades to empty metadata.
- **Screenshot failures are non-fatal and legible** ([#126](https://github.com/lessthanseventy/excessibility/issues/126)). A failed screenshot logs the actual `inspect/1`-ed scanner reason instead of raising `Protocol.UndefinedError` (String.Chars for tuples) and failing the test; the HTML snapshot is kept.
- **axe no longer scans `file://` snapshots before CSS applies** ([#121](https://github.com/lessthanseventy/excessibility/issues/121)). Navigation defaults to `load` and the runner additionally waits until every linked stylesheet has loaded or errored (plus `document.fonts.ready`) before analyzing, so results no longer depend on a race between stylesheet loading and axe injection.
- **Counted finding-delta** ([#130](https://github.com/lessthanseventy/excessibility/pull/130)). The review's `{rule, selector}` fingerprint swallowed *all* current occurrences when the baseline had one, so a second identical violation introduced next to a pre-existing one reported nothing. Baseline occurrences are now consumed per fingerprint.
- `mix excessibility.review` warns when the current snapshots predate the baseline instead of silently describing the previous run ([#130](https://github.com/lessthanseventy/excessibility/pull/130)).
- `--timeline` failures (missing file, invalid JSON) raise a friendly Mix error with the regeneration command instead of a raw `File.Error`/`Jason.DecodeError` ([#130](https://github.com/lessthanseventy/excessibility/pull/130)).

### Changed
- Dependency requirements are now bounded (`~>` instead of open-ended `>=`) for `floki`, `igniter`, `phoenix`, and `phoenix_live_view`, so a future breaking major is not silently accepted into consumer apps.
- **A judge can no longer fully green-light a deterministic `:block`** ([#129](https://github.com/lessthanseventy/excessibility/pull/129)). When the heuristic tier is `:block` (new critical/serious findings from the rules engine) and the judge says `:auto`, `Judge.verdict/2` floors the verdict to `:review` and records the judge's raw tier in `:judge_tier` (printed by `mix excessibility.review`). Rendered page content feeds LLM prompts, so "nobody looks at this" is not a downgrade a model may make alone; judges may still raise tiers without restriction.
- **Run-level behavioral findings stay at the report level** ([#129](https://github.com/lessthanseventy/excessibility/pull/129)). `--timeline` findings are no longer appended to every changed view (one unrelated N+1 no longer marked every view `:block` and double-counted the summary). They still fail the run via the exit gate and reach the LLM judge as prompt context. The judging orchestration is now public as `Excessibility.Review.judge_changes/2`.

## [0.14.0] - 2026-06-24

### Added
- **Cross-snapshot diffing — `Excessibility.SnapshotDiff`** ([#104](https://github.com/lessthanseventy/excessibility/issues/104)). Compares consecutive snapshots of the same test to catch content that changed without an `aria-live` region — a WCAG 2.1 SC 4.1.3 (Status Messages) failure that no single-snapshot tool, axe-core included, can detect. Public API: `diff/3` (a content-agnostic semantic DOM diff that localizes each change to the deepest stable container), `live_region_findings/3`, `scan_sequence/2`, and `scan_files/2`. Wired into `mix excessibility`; gated by `:cross_snapshot_enabled?` (default `true`).
- Default snapshots now embed `Test:`/`Sequence:` capture metadata so cross-snapshot diffing can pair them, **without changing the `Module_line.html` filename scheme** (no baseline churn). Adds `:auto`/`:default` capture modes and `Excessibility.Capture.init_default_context/1`.

### Fixed
- **`:toggle_missing_aria_state`** ([#110](https://github.com/lessthanseventy/excessibility/issues/110)) no longer fires on dismiss patterns: hide-only actions, and toggles whose target is the element's own ancestor container (e.g. a menu item that dismisses its own menu). `aria-expanded` would be wrong on both.
- **`:phx_click_on_non_interactive`** ([#110](https://github.com/lessthanseventy/excessibility/issues/110)) ignores `phx-click-away` (dismissal, not activation), removing false positives on the standard dialog `focus_wrap` pattern. Elements with `phx-click` are unchanged.
- **`:click_away_without_escape`** ([#110](https://github.com/lessthanseventy/excessibility/issues/110)) detects a miscased `phx-key="escape"` (rather than the literal `"Escape"` that matches `KeyboardEvent.key`, which silently never fires) and explains it; the generic message also notes the required capitalization.
- Corrected the `t:Excessibility.LiveViewRules.Rule.finding/0` type cross-reference so `mix docs` builds without warnings.

## [0.13.0] - 2026-04-10

### Added
- **`Excessibility.Scanner` — public runtime scanning API** ([#107](https://github.com/lessthanseventy/excessibility/issues/107)). Call `Excessibility.Scanner.scan(url, opts)` from LiveViews, Oban jobs, CLI wrappers, or any application code to get a structured axe-core report. Returns `{:ok, report}` with atom-keyed fields (`:violations`, `:final_url`, `:duration_ms`, `:engine`, `:timestamp`, `:passes_count`, `:inapplicable_count`) or `{:error, reason}` with typed tuples (`:timeout`, `{:http_error, status}`, `{:navigation_failed, msg}`, `{:playwright_error, msg}`, `{:invalid_url, reason}`).
- Scanner options: `:timeout`, `:wait_for`, `:wait_until`, `:viewport`, `:tags`, `:user_agent`, `:screenshot`, `:disable_rules`, `:fallback`.
- Richer `axe-runner.js` output: `final_url` (after redirects), `duration_ms`, `engine.axe_version`, `engine.chromium_version`, `passes_count`, `inapplicable_count`.
- `mix excessibility.check` gains `--wait-until`, `--tags`, `--timeout`, `--viewport`, `--user-agent` flags.
- **`Excessibility.LiveViewRules` — LiveView-aware accessibility rules** that complement axe-core on Phoenix-specific patterns. Rules auto-discovered from `lib/excessibility/live_view_rules/rules/`; custom rules registered via `config :excessibility, custom_live_view_rules: [...]`. `mix excessibility` now runs both axe-core AND these rules on each snapshot and fails if either finds issues. Rules are no-ops on HTML without `phx-*` attributes, so the feature is safe on non-Phoenix snapshots.
- Config knobs: `:lv_rules_enabled?` (default `true`) and `:lv_rules_disabled` (list of rule ids to skip).
- **Built-in LiveView rules:**
  - **`:phx_click_on_non_interactive`** ([#101](https://github.com/lessthanseventy/excessibility/issues/101)) — flags `phx-click` / `phx-click-away` on elements that are not natively keyboard-accessible (anything other than `<a>`/`<button>`/`<input>`/`<select>`/`<textarea>`/`<summary>`/`<details>`, or elements with `tabindex` or an interactive `role`).
  - **`:toggle_missing_aria_state`** ([#102](https://github.com/lessthanseventy/excessibility/issues/102)) — flags elements whose `phx-click` serializes `JS.toggle/show/hide` but have no `aria-expanded`. Parses the serialized JSON to detect toggle operations and target ids.
  - **`:click_away_without_escape`** ([#103](https://github.com/lessthanseventy/excessibility/issues/103)) — flags `phx-click-away` without a matching `phx-window-keydown`/`phx-keydown` + `phx-key="Escape"` (or `role="dialog"`), so keyboard users can actually dismiss the overlay.
  - **`:debounce_without_live_region`** ([#105](https://github.com/lessthanseventy/excessibility/issues/105)) — flags `<input phx-debounce>` when the snapshot has no `aria-live`, `role="status"`, `role="alert"`, or `role="log"` region anywhere. Conservative: only fires when the whole snapshot lacks any live region.
  - **`:hidden_form_control_without_aria`** ([#106](https://github.com/lessthanseventy/excessibility/issues/106)) — flags `<input type="checkbox|radio">` hidden via `hidden` or `sr-only` when the wrapping `<label>` does not expose state via `aria-checked`, `aria-pressed`, `role="checkbox"`, or `role="radio"`.
- `Excessibility.LiveViewRules` registers discovered rule files as `@external_resource` so edits to existing rules trigger recompilation of the scanner module.

### Changed
- **`Excessibility.AxeRunner` removed and folded into `Excessibility.Scanner`.** The old module was an internal helper; all callers (`mix excessibility`, `mix excessibility.check`, the `a11y_check` MCP tool, snapshot screenshotting) now go through `Scanner.scan/2`. No end-user behavior change for existing Mix task users.
- Violation shape returned from `Scanner.scan/2` is now atom-keyed with normalized `:impact` atoms (`:critical | :serious | :moderate | :minor`), not the raw string-keyed axe-core output.

## [0.12.0] - 2026-03-25

### Breaking Changes
- **Pa11y + ChromicPDF replaced with Playwright + axe-core.** Accessibility checks now use axe-core via Playwright instead of Pa11y. ChromicPDF removed; screenshots now via Playwright.
- **MCP surface simplified.** Removed 8 tools, 9 prompts, 2 resources. Remaining tools: `a11y_check`, `debug`, `get_snapshots`, `get_timeline`, `generate_test`, `check_work`.
- **`.claude_docs` approach replaced with `CLAUDE.md`.** Installer now appends an Excessibility section directly to `CLAUDE.md`. The `mix excessibility.setup_claude_docs` task has been removed.

### Added
- `AxeRunner` Elixir wrapper for axe-core with Playwright
- `mix excessibility.check` for checking arbitrary URLs
- `mix excessibility.snapshots` for snapshot management
- Automatic curl fallback when Playwright fails on remote URLs, with browser-like headers to bypass WAFs
- **MCP elicitation support** — tools can request structured input from the user mid-execution via forms
- **`check_work` composite MCP tool** — runs tests + a11y check + optional perf analysis in one call, with threshold-based elicitation for triage
- **Auto-check workflow** — installer adds CLAUDE.md instructions so Claude automatically runs `check_work` after modifying code
- MCP server negotiates elicitation capability with clients and caches callback in state
- Threshold-based elicitation in `a11y_check` — only interrupts for critical/serious violations; minor issues returned silently
- Playwright and Node.js setup in CI workflow

### Fixed
- IO.Stream crash in `build_markdown_report` ([#84](https://github.com/lessthanseventy/excessibility/issues/84))
- LiveView `get_assigns` crash on unsupported `:get_state` calls ([#83](https://github.com/lessthanseventy/excessibility/issues/83))
- MCP timeline tools crash on large files ([#80](https://github.com/lessthanseventy/excessibility/issues/80))
- Added `BitString` implementation for `Excessibility.Source` protocol ([#85](https://github.com/lessthanseventy/excessibility/issues/85))
- Broken doc links in README
- `node_modules` excluded from hex package
- Credo `--strict` compliance for Elixir 1.19

### Changed
- Installer creates/appends `CLAUDE.md` instead of `.claude_docs/excessibility.md`
- README updated with auto-check workflow, `check_work` tool docs, and optional hooks guidance

## [0.10.2] - 2026-02-03

### Fixed
- Make `bin/mcp-server` a generic wrapper script that works from any Phoenix project directory
- Installer now generates correct relative path (`deps/excessibility/bin/mcp-server`) in `.mcp.json`

## [0.10.1] - 2026-02-03

### Fixed
- Include `bin/` directory in Hex package so `bin/mcp-server` is available when installed as a dependency

## [0.10.0] - 2026-02-01

### Fixed
- Fixed e11y_debug MCP tool hanging by reducing response size (24KB → ~300 bytes)
- Output now written to temp file instead of included in response
- Added recursive process tree killing on timeout to prevent zombie processes

### Added
- Debug logging for MCP server via `MCP_LOG_FILE` environment variable
- Complete MCP tools documentation in README (11 tools with speed indicators)
- Better workflow guidance in generated claude_docs

### Changed
- e11y_debug now returns `output_file` path and `result_summary` instead of full output
- Improved tool descriptions to clarify workflow (generate_test → e11y_debug)

## [0.8.3] - 2026-01-25

### Fixed
- Fixed function filtering to recursively process structs ([#48](https://github.com/lessthanseventy/excessibility/issues/48))
  - `Filter.filter_functions/1` now descends into structs and converts them to maps
  - Functions nested inside structs (e.g., `Phoenix.HTML.Form` → `Ecto.Changeset` → function) are now properly filtered
  - Prevents `Protocol.UndefinedError` when generating `timeline.json` with LiveViews that have forms or changesets with function references

## [0.8.1] - 2026-01-25

### Fixed
- Fixed JSON encoding crash when timeline contains Ecto structs ([#44](https://github.com/lessthanseventy/excessibility/issues/44))
  - `Formatter.prepare_for_json/1` now converts structs to maps before encoding
  - Removes `__meta__` fields from Ecto structs during conversion
  - Prevents `Protocol.UndefinedError` when generating `timeline.json` with LiveViews that have database records in assigns

## [0.8.0] - 2026-01-25

### Added
- Timeline analysis and debugging features
  - Automatic `timeline.json` generation for test runs
  - Markdown formatter for human-readable timeline reports
  - JSON formatter for machine-readable timeline data
  - Diff computation between telemetry snapshots
  - Key state extraction with configurable highlighting
  - CLI flags for timeline filtering control (`--full`, `--highlight`)

### Changed
- Require Elixir ~> 1.14 for Ecto dependency compatibility
- Updated CI to test on Elixir 1.14+ (removed 1.13 support)
- Streamlined CI matrix to one OTP version per Elixir version

### Improved
- Enhanced signal-to-noise ratio in telemetry snapshots
  - Configurable `filter_assigns` pipeline
  - Automatic filtering of Ecto metadata (`__meta__`, `NotLoaded` associations)
  - Automatic filtering of Phoenix internals (`flash`, `__changed__`, `__temp__`)
  - Filtering of private assigns (keys starting with `_`)

### Documentation
- Added implementation plan for telemetry signal-to-noise improvements
- Added timeline analysis usage documentation

## [0.7.0] - Earlier

See git history for changes in 0.7.0 and earlier versions.

[0.8.3]: https://github.com/lessthanseventy/excessibility/compare/v0.8.1...v0.8.3
[0.8.1]: https://github.com/lessthanseventy/excessibility/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/lessthanseventy/excessibility/compare/v0.7.0...v0.8.0
