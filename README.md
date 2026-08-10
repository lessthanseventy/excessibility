# Excessibility

[![Hex.pm](https://img.shields.io/hexpm/v/excessibility.svg)](https://hex.pm/packages/excessibility)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgrey.svg)](https://hexdocs.pm/excessibility)
[![CI](https://github.com/lessthanseventy/excessibility/actions/workflows/ci.yml/badge.svg)](https://github.com/lessthanseventy/excessibility/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/lessthanseventy/excessibility)

**Accessibility Snapshot Testing for Elixir + Phoenix**

Excessibility helps you test your Phoenix apps for accessibility (WCAG compliance) by taking HTML snapshots during tests and running them through [axe-core](https://github.com/dequelabs/axe-core) via [Playwright](https://playwright.dev/).

## Why Excessibility?

- **Keep accessibility in your existing test feedback loop.** Snapshots are captured inside ExUnit, Wallaby, and LiveView tests, so regressions surface together with your functional failures.
- **Ship safer refactors.** Explicit baseline locking and comparison lets reviewers see exactly what changed and approve intentionally.
- **Debug CI-only failures quickly.** axe-core output points to the failing snapshot, and the saved artifacts make it easy to reproduce locally.

## How It Works

1. **During tests**, call `html_snapshot(conn)` to capture HTML from your Phoenix responses, LiveViews, or Wallaby sessions
2. **After tests**, run `mix excessibility` to check all snapshots with axe-core for WCAG violations
3. **Lock baselines** with `mix excessibility.baseline` when snapshots represent a known-good state
4. **Compare changes** with `mix excessibility.snapshot.compare` to review what changed and approve/reject
5. **Review the blast radius** with `mix excessibility.review` to see which accessibility issues a change newly introduced (JSON output for CI via `--format json`)
6. **In CI**, axe-core reports accessibility violations alongside your test failures

## LiveView-Aware Rules

axe-core can't catch accessibility issues that depend on Phoenix-specific
attributes like `phx-click`, `phx-submit`, or `phx-debounce`. Excessibility
ships a complementary set of **LiveView rules** that inspect snapshot HTML
for these patterns and run automatically alongside axe-core when you call
`mix excessibility`.

Built-in rules:

| Rule | What it flags |
| --- | --- |
| `:phx_click_on_non_interactive` | `phx-click` / `phx-click-away` on `<div>`, `<li>`, `<span>`, `<tr>`, etc. without `tabindex` or an interactive `role` — visually clickable but unreachable by keyboard |
| `:toggle_missing_aria_state` | Elements whose `phx-click` uses `JS.toggle/show/hide` but are missing `aria-expanded` — screen readers can't tell whether the target is open or closed |
| `:click_away_without_escape` | `phx-click-away` with no matching `phx-window-keydown` + `phx-key="Escape"` (or `role="dialog"`) — keyboard users can't dismiss the overlay |
| `:debounce_without_live_region` | `<input phx-debounce>` when the page has no `aria-live` / `role="status"` region anywhere — screen readers never hear that results updated |
| `:hidden_form_control_without_aria` | Visually hidden `<input type="checkbox\|radio">` whose wrapping `<label>` doesn't expose state via `aria-checked` or `role="checkbox"`/`"radio"` |
| `:reveal_without_announcement` | An initially hidden element (`hidden` class/attribute or inline `display:none`) revealed from the server via a serialized `JS.show`/`JS.toggle` command — its own `data-*` or another element's `phx-*` `to:` target — with no `role="alert"`/`"status"`/`"log"`, `aria-live`, or live-region ancestor, so screen readers never hear it appear |

On non-Phoenix HTML (no `phx-*` attributes) these rules are no-ops, so
enabling them never adds noise for projects that don't use LiveView.

**Config:**

```elixir
# config/test.exs
config :excessibility,
  lv_rules_enabled?: true,                          # default
  lv_rules_disabled: [:phx_click_on_non_interactive] # skip specific rules
```

**Custom rules:** implement `Excessibility.LiveViewRules.Rule` and register:

```elixir
config :excessibility, custom_live_view_rules: [MyApp.Rules.MyRule]
```

## Runtime Usage (Scanner API)

In addition to the snapshot-testing workflow, Excessibility exposes
`Excessibility.Scanner.scan/2` for runtime use — call it from LiveView
handlers, background jobs, CLI wrappers, or any plain application code
to scan an arbitrary URL and get a structured axe-core report:

```elixir
case Excessibility.Scanner.scan("https://example.com") do
  {:ok, report} ->
    IO.puts("Found #{length(report.violations)} violations on #{report.final_url}")

    for v <- report.violations do
      IO.puts("  [#{v.impact}] #{v.id}: #{v.description}")
      IO.puts("     #{v.help_url}")
    end

  {:error, :timeout} ->
    Logger.warning("Scan timed out")

  {:error, {:http_error, status}} ->
    Logger.warning("Target returned HTTP #{status}")

  {:error, {:navigation_failed, msg}} ->
    Logger.warning("Navigation failed: #{msg}")

  {:error, {:invalid_url, reason}} ->
    Logger.warning("Invalid URL: #{reason}")
end
```

Pass options to control the scan:

```elixir
Excessibility.Scanner.scan("https://example.com",
  timeout: 20_000,
  wait_for: "#main",
  tags: ["wcag2a", "wcag2aa", "wcag21aa"],
  viewport: {1440, 900},
  screenshot: "/tmp/example.png"
)
```

Scan at several widths in one browser session — WCAG 1.4.10 Reflow
failures only show up at narrow viewports — and optionally measure
clipping, which axe has no rule for:

```elixir
{:ok, report} =
  Excessibility.Scanner.scan("https://example.com",
    viewports: [{1440, 900}, {320, 800}],
    check_clipping: true
  )

for %{viewport: {w, _h}, violations: violations, clipping: clipping} <- report.results do
  IO.puts("@#{w}px: #{length(violations)} violations, #{length(clipping.clipped)} clipped controls")
end
```

The same checks are available on snapshots via
`mix excessibility --viewports 1440x900,320x800 --check-clipping`.
Scan reports also carry a `:warnings` list — e.g. a linked stylesheet
that failed to load, which would silently invalidate contrast findings.

See `Excessibility.Scanner` for the full report type and options list.
Unlike Mix tasks, the Scanner is safe to call from production Phoenix
releases, which makes it easy to build things like a public URL
accessibility scanner, background monitoring jobs, or an internal
scanning service on top of the library.

## Features

- Snapshot HTML from `Plug.Conn`, `Wallaby.Session`, `Phoenix.LiveViewTest.View`, and `Phoenix.LiveViewTest.Element`
- Explicit baseline locking and comparison workflow
- Interactive good/bad approval when comparing snapshots
- Screenshots via Playwright
- Mockable system/browser calls for CI
- axe-core accessibility checking with sensible LiveView defaults

## LLM Development Features

Excessibility includes powerful features for debugging Phoenix apps with AI assistance (Claude, Cursor, etc.).

### Telemetry-Based Auto-Capture (Zero Code Changes!)

Debug **any existing LiveView test** with automatic snapshot capture - no test changes required:

```elixir
# Your test - completely vanilla, zero Excessibility code
test "user interaction flow", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/dashboard")
  view |> element("#button") |> render_click()
  view |> element("#form") |> render_submit(%{name: "Alice"})
  assert render(view) =~ "Welcome Alice"
end
```

Debug it:

```bash
mix excessibility.debug test/my_test.exs
```

> **🚀 Rich Timeline Capture**
>
> `mix excessibility.debug` automatically enables telemetry capture, dramatically increasing event visibility:
>
> - **Without telemetry:** ~4 events (mount, handle_params only)
> - **With telemetry:** 10-20x more events including **all render cycles**
>
> **Example from real test:**
> - Basic test: 4 events → **11 events** (added 7 render events)
> - Complex test: Limited snapshots → **236 timeline events** with rich analyzer insights
>
> Render events enable powerful pattern detection:
> - 🔴 Memory leak detected (2.3x growth over render cycles)
> - ⚠️ 7 consecutive renders without user interaction
> - 🔴 Performance bottleneck (15ms render blocking)
> - ⚠️ Rapid state changes (potential infinite loop)
>
> This happens automatically - no test changes needed!

**Automatically captures:**
- LiveView mount events
- All handle_event calls (clicks, submits, etc.)
- **All render cycles** (form updates, state changes triggered by `render_change`, `render_click`, `render_submit`)
- Real LiveView assigns at each step
- Complete state timeline with memory tracking and performance metrics

**Example captured snapshot:**

```html
<!--
Excessibility Telemetry Snapshot
Test: test user interaction flow
Sequence: 2
Event: handle_event:submit_form
Timestamp: 2026-01-25T10:30:12.345Z
View Module: MyAppWeb.DashboardLive
Assigns: %{
  current_user: %User{name: "Alice"},
  form_data: %{name: "Alice"},
  submitted: true
}
-->
```

### Debug Command

The debug command outputs a comprehensive markdown report with:
- Test results and error output
- All captured snapshots with inline HTML
- Event timeline showing state changes
- Real LiveView assigns at each snapshot
- Metadata (timestamps, event sequence, view modules)

The report is both human-readable and AI-parseable, perfect for pasting into Claude.

**Available formats (all args pass through to mix test):**

```bash
mix excessibility.debug test/my_test.exs                    # Markdown report (default)
mix excessibility.debug test/my_test.exs:42                 # Run specific test
mix excessibility.debug --only live_view                    # Run tests with tag
mix excessibility.debug test/my_test.exs --format=json      # Structured JSON
mix excessibility.debug test/my_test.exs --format=package   # Directory with MANIFEST
mix excessibility.latest                                    # Re-display last report
```

### 🔍 Telemetry Timeline Analysis

Automatically captures LiveView state throughout test execution and generates scannable timeline reports:

- **Smart Filtering** - Removes Ecto metadata, Phoenix internals, and other noise
- **Diff Detection** - Shows what changed between events
- **Multiple Formats** - JSON for automation, Markdown for humans/AI
- **CLI Control** - Override filtering with flags for deep debugging

```bash
mix excessibility.debug test/my_test.exs
```

This writes the full local `timeline.json`. Alongside it, capture also writes a **value-free `digest.json`** that is safe to upload to CI or hand to a reviewer/model — see [Runtime Evidence Digest](#runtime-evidence-digest) below.

See the project's `CLAUDE.md` file for detailed usage.

### Telemetry Implementation

Excessibility hooks into Phoenix LiveView's built-in telemetry events:
- `[:phoenix, :live_view, :mount, :stop]`
- `[:phoenix, :live_view, :handle_event, :stop]`
- `[:phoenix, :live_view, :handle_params, :stop]`
- `[:phoenix, :live_view, :render, :stop]` - **Captures all render cycles** (form updates, state changes)

When you run `mix excessibility.debug`, it:
1. Enables telemetry capture via environment variable
2. Attaches telemetry handlers to LiveView events
3. Runs your test
4. Captures snapshots with real assigns from the LiveView process
5. Generates a complete debug report

No test changes needed - it works with vanilla Phoenix LiveView tests!

### Manual Capture Mode

For fine-grained control, you can also manually capture snapshots:

```elixir
use Excessibility

@tag capture_snapshots: true
test "manual capture", %{conn: conn} do
  {:ok, view, _} = live(conn, "/")
  html_snapshot(view)  # Manual snapshot with auto-tracked metadata

  view |> element("#btn") |> render_click()
  html_snapshot(view)  # Another snapshot
end
```

## Runtime Evidence Digest

`mix excessibility.debug` writes **two** artifacts side by side, with very different privacy properties:

- **`timeline.json`** — the full local diagnosis. It carries real (filtered) assigns, raw SQL, bind-value-free query text, memory sizes and diffs. It is meant for **local debugging only**. It can contain application data and is **not safe to upload** to CI logs, artifact stores, or a model.
- **`digest.json`** — a **value-free, safe-by-construction** runtime-evidence artifact derived from the same in-memory timeline. It is built by explicit construction from an allowlist — it never copies an assigns map, a raw query, params, or bind values. This is the artifact you can attach to a PR, store as a CI artifact, or hand to a reviewer or model.

Both are written during capture in `Excessibility.TelemetryCapture.write_snapshots/1`. The digest builder is `Excessibility.Digest`.

Position this as **supplemental** input for debugging and code-aware review. It is a compact, trustworthy record of what a LiveView actually did — query shapes, plan shapes, assign growth, callback sequence and coverage — that a reviewer or tool can interpret **alongside the source code**. It is *not* a universal performance verdict and it does *not* replace source-aware review or profiling.

### The `excessibility.digest/v1` schema

```jsonc
{
  "schema": "excessibility.digest/v1",
  "capture": {
    "status": "ok",                 // ok | partial | failed
    "ecto_configured": true,        // false ⇒ "not measured" (≠ configured + zero queries)
    "enrichers_run": ["assign_sizes", "collection_size", "ecto_queries", "state"],
    "plan_capture": "disabled",     // disabled | explain | explain_analyze
    "timing": "non_comparable",     // single run is never treated as a base/head
    "capture_version": "0.18.1",
    "warnings": []
  },
  "coverage": {
    "tests": ["MyAppWeb.PageLiveTest: saves product"],
    "views": ["MyAppWeb.PageLive"],
    "callbacks_observed": ["mount", "handle_params", "handle_event:save", "render"],
    "event_sequence": ["mount", "handle_params", "handle_event:save", "render"],
    "fixtures": {}                  // caller-supplied cardinality only
  },
  "events": [{
    "sequence": 3,
    "callback": "handle_event:save",
    "view": "MyAppWeb.PageLive",
    "queries": {
      "count": 12,
      "shapes": [{ "fingerprint": "sha256:9f3a…", "operation": "select",
                   "source": "categories", "normalized": "select … where id = $?",
                   "count": 10, "sequences": [4,5,6,7,8,9,10,11,12,13] }],
      "repeated": [{ "fingerprint": "sha256:9f3a…", "source": "categories",
                     "repetitions": 10, "share": 0.83, "cardinality": null,
                     "severity": "advisory" }],
      "overflow": null              // explicit metadata if ever bounded — never silent truncation
    },
    "assigns": {
      "total_term_bytes": 24000,
      "shapes": [{ "name": "products", "kind": "list", "cardinality": 50,
                   "term_bytes": 18000, "path_depth": 1,
                   "delta_bytes": 18000, "growth": "increased" }]
    }
  }],
  "trajectories": {
    "MyAppWeb.PageLive": { "monotonic_growth": ["products"], "retained_after_use": [] }
  }
}
```

**Privacy guarantee.** The digest **never** contains assign values, params/form values, user/session records, SQL bind values, rendered HTML, or arbitrary inspected terms. Every field is a name, a shape, a coarse size, a count, or a fingerprint. Redaction is by omission — if a field cannot be derived safely, it is left out, not guessed.

The **coverage/status contract** makes silence interpretable: an unexercised callback is simply absent from `callbacks_observed`; `ecto_configured: false` means "queries were not measured" (distinct from measured-and-zero); a disabled enricher or failed capture shows up in `enrichers_run` / `status` + `warnings`. A missing signal is always labeled *why*.

Print the digest for the last run with:

```bash
mix excessibility.debug --format digest test/my_live_view_test.exs
```

`--format digest` only reads and prints the `digest.json` that capture already wrote; it never rebuilds it.

### Query fingerprints and N+1

Every captured Ecto query is normalized into a stable, value-free SQL shape (`Excessibility.SQLFingerprint`): keywords downcased, `$1,$2 → $?`, `IN (...)` arity folded, inline numeric/quoted literals scrubbed to `?`, whitespace collapsed. A `sha256:` fingerprint is derived from that normalized string. N+1 evidence groups by **fingerprint** (via the shared `Excessibility.QueryEvidence`), so two *different* SELECTs on the same table are counted as two shapes rather than lumped together by table name. The normalizer is Postgres-oriented (the Ecto reference adapter emits parameterized SQL); other adapters still fingerprint via the generic regex.

### Opt-in query-plan (EXPLAIN) evidence — Postgres-only

Off by default. When enabled, each recorded SELECT is run through `EXPLAIN` and a **value-free** plan summary (node types, relation names, row estimates only — never row data) is attached to its query shape, with a stable plan fingerprint over the node-type + relation tree.

| Flag | Mode | Behavior |
|------|------|----------|
| `--plan` | `EXPLAIN (FORMAT JSON)` | Plans the SELECT but **never executes** it — touches no data. SELECT-only. |
| `--plan-analyze` | `EXPLAIN ANALYZE` | *Executes* the query to gather real row counts. **Double-gated:** additionally requires `config :excessibility, query_plan_allow_analyze: true` (without it, downgrades to plain `EXPLAIN` with a warning). Run only inside a DB sandbox / read-only environment. |

```bash
mix excessibility.debug --plan test/my_live_view_test.exs
mix excessibility.debug --plan-analyze test/my_live_view_test.exs   # + query_plan_allow_analyze: true
```

Guards: only SELECTs are ever re-run; EXPLAIN's own Ecto telemetry is suppressed (re-entrancy guard); a failed EXPLAIN yields `plan: null` plus a `capture.warnings` entry rather than crashing the run. Plan capture is **Postgres-only** — on other adapters it is a documented no-op (`plan_capture` stays `disabled`). `capture.plan_capture` reports `disabled | explain | explain_analyze` so absence is interpretable.

### Comparing digests

```bash
mix excessibility.digest.compare --base base/digest.json --head head/digest.json [--format json]
```

`Excessibility.DigestCompare` reports **structural deltas only** — query fingerprints added/removed/count-changed, plan changes under stable SQL, assign `term_bytes`/cardinality deltas, and coverage differences. It is **measurement-scope-guarded**: a delta is asserted only when both sides measured the same signal, so if the base had Ecto unconfigured and the head configured, you get a coverage note ("base did not measure queries"), not a fabricated "+12 queries." It emits **no merge verdict**, no severity beyond advisory, and **always exits 0** — it is a supplemental diff, never a CI gate.

> **Rename note:** the a11y snapshot baseline task formerly at `mix excessibility.compare` is now `mix excessibility.snapshot.compare` (breaking change, no alias — see the CHANGELOG). `mix excessibility.digest.compare` is the new, unambiguous runtime-evidence comparison.

### Benchmark mode

```bash
mix excessibility.debug --benchmark=20 test/my_live_view_test.exs
```

Runs the test N times and writes a value-free `benchmark.json` with robust **cold vs warm** timing stats (median + MAD) per `(view, callback)` and per query-fingerprint. Sample 1 is treated as cold (compilation, connection warmup, cold caches); samples 2..N are warm, reported separately so a cold first run cannot poison the median. An extreme warm sample (beyond `median + k·MAD`) is surfaced as an **advisory** outlier with the raw sample attached — never a pass/fail gate.

### Timing contract — "green ≠ fast"

Single-run timing is **diagnostic only** and is marked `timing: non_comparable` in the digest — a single run is never treated as a base or head. A green result means "no relative or configured outlier **in this run**," not "this code is fast." Timing **never** enters the digest; use benchmark mode when you need comparable timing evidence.

## MCP Server & Claude Code Skills

Excessibility includes an MCP (Model Context Protocol) server and Claude Code skills plugin for AI-assisted development.

### MCP Server

The MCP server provides tools for AI assistants to run accessibility checks and debug LiveView state.

**Available tools:**

| Tool | Speed | Description |
|------|-------|-------------|
| `a11y_check` | Slow | Run axe-core accessibility checks on snapshots or URLs |
| `check_work` | Slow | Run tests + a11y check + optional perf analysis (auto-check) |
| `debug` | Slow | Run tests with telemetry capture - returns timeline for analysis |
| `get_snapshots` | Fast | List or read HTML snapshots captured during tests |
| `get_timeline` | Fast | Read captured timeline showing LiveView state evolution |
| `generate_test` | Fast | Generate test code with `html_snapshot()` calls for a route |

### Auto-Check Workflow

The installer adds `CLAUDE.md` instructions that tell Claude to automatically run `check_work` after modifying code. This creates a seamless feedback loop:

1. Claude edits your code
2. `check_work` runs automatically (tests + a11y + optional perf analysis)
3. When critical violations are found, MCP elicitation presents a triage form for you to prioritize fixes
4. Minor issues are returned directly for Claude to fix silently
5. Clean results return immediately

**Automatic Setup:**

The installer configures everything automatically:

```bash
mix excessibility.install
```

This will:
- Add configuration to `config/test.exs`
- Install Playwright and axe-core via npm
- Register the MCP server with Claude Code
- Install the Claude Code skills plugin
- Add auto-check instructions to `CLAUDE.md`

Use `--no-mcp` to skip Claude Code integration.

**Manual Setup:**

```bash
claude mcp add excessibility -s project -- mix run --no-halt -e "Excessibility.MCP.Server.start()"
claude plugins add deps/excessibility/priv/claude-plugin
```

### Claude Code Skills Plugin

Install the skills plugin for structured accessibility workflows:

```bash
claude plugins add /path/to/excessibility/priv/claude-plugin
```

**Available skills:**

| Skill | Description |
|-------|-------------|
| `/e11y-tdd` | TDD workflow with html_snapshot and axe-core - sprinkle snapshots to see what's rendered, delete when done |
| `/e11y-debug` | Debug workflow with timeline analysis - inspect state at each event, correlate with axe-core failures |
| `/e11y-fix` | Reference guide for fixing axe-core/WCAG errors with Phoenix-specific patterns |

**Example workflow:**

```
/e11y-tdd

# Claude will guide you through:
# 1. EXPLORE - Add html_snapshot() calls to see what's rendered
# 2. RED - Write test with snapshot at key moment
# 3. GREEN - Implement feature, use snapshots to debug
# 4. CHECK - Run mix excessibility for axe-core validation
# 5. CLEAN - Remove temporary snapshots
```

### Optional: Hooks for Additional Automation

For belt-and-suspenders automation, you can also configure Claude Code hooks
to run tests after file edits. Add to your `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit",
        "command": "mix test --failed"
      }
    ]
  }
}
```

This runs failing tests after each file edit, catching breakage immediately.
The `check_work` MCP tool handles accessibility and performance checking separately.

## Installation

Add to `mix.exs`:

```elixir
def deps do
  [
    {:excessibility, "~> 0.15", only: [:dev, :test]}
  ]
end
```

Fetch dependencies and run the installer:

```bash
mix deps.get
mix excessibility.install
```

**Apps with authentication:** If your app requires login to access most pages, specify a public route for extracting `<head>` content:

```bash
mix excessibility.install --head-render-path /login
```

The installer will:
- Add configuration to `config/test.exs`
- Install Playwright and axe-core via npm in your assets directory

## Quick Start

1. **Configure** the endpoint and helper modules in `config/test.exs`. The installer does this automatically, or add manually:

    ```elixir
    config :excessibility,
      endpoint: MyAppWeb.Endpoint,
      head_render_path: "/",  # use "/login" for apps with auth
      system_mod: Excessibility.System,
      browser_mod: Wallaby.Browser,
      live_view_mod: Excessibility.LiveView
    ```

2. **Add `use Excessibility`** in tests where you want snapshots:

    ```elixir
    defmodule MyAppWeb.PageControllerTest do
      use MyAppWeb.ConnCase, async: true
      use Excessibility

      test "renders home page", %{conn: conn} do
        conn = get(conn, "/")
        html_snapshot(conn, screenshot?: true)
        assert html_response(conn, 200) =~ "Welcome!"
      end
    end
    ```

3. **Typical workflow:**

    ```bash
    # Run specific test + axe-core in one command
    mix excessibility test/my_test.exs
    mix excessibility test/my_test.exs:42
    mix excessibility --only a11y

    # Or run tests separately, then check all snapshots
    mix test                    # Generates snapshots in test/excessibility/
    mix excessibility           # Runs axe-core against all snapshots

    # Lock current snapshots as known-good baseline
    mix excessibility.baseline

    # After making UI changes, run tests again, then compare
    mix test
    mix excessibility.snapshot.compare   # Review diffs, choose good (baseline) or bad (new)
    ```

## Usage

```elixir
use Excessibility

html_snapshot(conn,
  name: "homepage.html",
  screenshot?: true
)
```

The `html_snapshot/2` macro works with:
- `Plug.Conn`
- `Wallaby.Session`
- `Phoenix.LiveViewTest.View`
- `Phoenix.LiveViewTest.Element`

It returns the source unchanged, so you can use it in pipelines.

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:name` | `string` | auto-generated | Custom filename (e.g., `"login_form.html"`). Default is `ModuleName_LineNumber.html` |
| `:screenshot?` | `boolean` | `false` | Generate PNG screenshots (via Playwright) |
| `:open_browser?` | `boolean` | `false` | Open the snapshot in your browser after writing |
| `:cleanup?` | `boolean` | `false` | Delete existing snapshots for the current test module before writing |

## Baseline Workflow

Snapshots are saved to `test/excessibility/html_snapshots/` and baselines live in `test/excessibility/baseline/`.

**Setting a baseline:**

```bash
mix excessibility.baseline
```

This copies all current snapshots to the baseline directory. Run this when your snapshots represent a known-good, accessible state.

**Comparing against baseline:**

```bash
mix excessibility.snapshot.compare
```

For each snapshot that differs from its baseline:

1. **Diff files are created** — `.good.html` (baseline) and `.bad.html` (new)
2. **Both open in your browser** for visual comparison
3. **You choose which to keep** — "good" to reject changes, "bad" to accept as new baseline
4. **Diff files are cleaned up** after resolution

**Batch options:**

```bash
mix excessibility.snapshot.compare --keep good   # Keep all baselines (reject all changes)
mix excessibility.snapshot.compare --keep bad    # Accept all new versions as baseline
```

## Blast-Radius Review

Where `mix excessibility` checks each snapshot in isolation, `mix excessibility.review` answers a sharper question — *what did this change actually do?* It diffs every current snapshot against its baseline and, per view, reports the regions that changed and the accessibility findings the change **newly introduced** (axe-core violations + LiveView rules), each with a risk tier:

- `block` — a new critical/serious issue (e.g. a keyboard-inaccessible control)
- `review` — a new moderate/minor issue; worth a human glance
- `auto` — rendering changed but introduced no accessibility issues

```bash
# Generate/refresh snapshots, then review against the baseline
mix test
mix excessibility.review

# Fail the build on :block (default), :review, or never
mix excessibility.review --fail-on review
mix excessibility.review --fail-on never

# Skip the axe-core browser scans and review on the LiveView rules only
mix excessibility.review --no-axe
```

### Machine-readable output for CI

Pass `--format json` (or `--json`) to emit a single JSON object on stdout instead of the human report — a stable API for CI and PR bots, so you never scrape printed text:

```bash
mix excessibility.review --format json
```

```json
{
  "excessibility_version": "0.16.0",
  "summary": { "block": 1, "review": 0, "auto": 55 },
  "warnings": [],
  "behavioral": [],
  "changes": [
    {
      "view": "checkout_review.html",
      "tier": "block",
      "region_count": 1,
      "findings": [
        {
          "rule": "reveal_without_announcement",
          "severity": "serious",
          "source": "live_view_rules",
          "selector": "div#cap-reached-banner",
          "message": "..."
        }
      ]
    }
  ]
}
```

Every finding carries a `source` — `live_view_rules`, `axe`, or `telemetry` — so a consumer can tell which layer produced it (and, when axe degrades, that the results are rules-only). The exit code is unchanged in JSON mode, so CI can gate on the exit status and read the JSON for detail.

### Behavioral findings (telemetry)

With `--timeline`, the review folds in behavioral findings from a telemetry timeline captured by `mix excessibility.debug` — memory leaks, unbounded list growth, render thrash, N+1 queries:

```bash
mix excessibility.debug test/my_journey_test.exs        # writes test/excessibility/timeline.json
mix excessibility.review --timeline test/excessibility/timeline.json
```

Behavioral findings are **advisory by default**. Unlike accessibility findings — which are a true delta against the baseline — they have no baseline and are absolute measurements of a single run, so they don't fail the build. Opt in with `--fail-on-behavioral`:

```bash
mix excessibility.review --timeline test/excessibility/timeline.json --fail-on-behavioral
```

The analyzers group events by LiveView before comparing, so a journey test that drives several LiveViews doesn't produce cross-view artifacts (a freshly-mounted view sitting next to a loaded one is not "memory growth").

Two signals are opt-in because they need extra wiring:

- **N+1 / query analysis** needs `config :excessibility, ecto_repos: [MyApp.Repo]` (capture attaches to the repo's query telemetry).
- **`handle_info` flooding** needs the `on_mount` hook (LiveView emits no `handle_info` telemetry). Add it once to a `live_session`, then enable the analyzer:

  ```elixir
  # router.ex
  live_session :default, on_mount: [Excessibility.TelemetryCapture] do
    # ...your live routes...
  end
  ```

  ```bash
  mix excessibility.debug test/my_test.exs --analyze=message_flooding
  ```

## Configuration

All configuration goes in `test/test_helper.exs` or `config/test.exs`:

| Config Key | Required | Default | Description |
|------------|----------|---------|-------------|
| `:endpoint` | Yes | — | Your Phoenix endpoint module (e.g., `MyAppWeb.Endpoint`) |
| `:system_mod` | No | `Excessibility.System` | Module for system commands (mockable) |
| `:browser_mod` | No | `Wallaby.Browser` | Module for browser interactions |
| `:live_view_mod` | No | `Excessibility.LiveView` | Module for LiveView rendering |
| `:excessibility_output_path` | No | `"test/excessibility"` | Base directory for snapshots |
| `:axe_runner_path` | No | auto-detected | Path to axe-runner.js script |
| `:playwright_path` | No | bundled copy | Path to an existing Playwright installation to reuse (skips the second browser download) |
| `:node_modules_path` | No | bundled copy | Path to a host `node_modules` directory providing `playwright` **and** `@axe-core/playwright` (skips the bundled `npm install` entirely; pins the axe version to the host's) |
| `:viewports` | No | `[]` | `{width, height}` tuples for `mix excessibility` to scan each snapshot at |
| `:check_clipping` | No | `false` | Flag interactive elements mostly outside the visible area, plus page-level horizontal overflow |
| `:clipping_ratio` | No | `0.9` | Minimum visible-width ratio before an element counts as clipped |
| `:head_render_path` | No | `"/"` | Route used for rendering `<head>` content |
| `:ecto_repos` | No | `[]` | Repos to capture query telemetry from, enabling N+1 / query analysis in `mix excessibility.debug` and `--timeline` reviews (e.g. `[MyApp.Repo]`) |
| `:slow_event_ms` | No | `1000` | Absolute "very slow event" ceiling for the performance analyzer. Performance findings are otherwise **relative** (outliers, bottleneck-share) and computed from test timings, so uniformly-slow code isn't flagged — lower this only if your test timings are representative of production |
| `:custom_enrichers` | No | `[]` | List of custom enricher modules (see Timeline Analysis section above) |
| `:custom_analyzers` | No | `[]` | List of custom analyzer modules (see Timeline Analysis section above) |
| `:sql_dialect` | No | `:postgres` | SQL dialect for query normalization/EXPLAIN. Only `:postgres` ships today; the `Excessibility.Dialect` seam lets a new dialect drop in |
| `:query_plan_allow_analyze` | No | `false` | Second gate for `--plan-analyze` (EXPLAIN ANALYZE, which executes queries). Enable only in a read-only DB sandbox |
| `:digest_include_normalized_sql` | No | `true` | Include the normalized (value-free) SQL string in each digest query shape; set `false` to emit fingerprint-only |
| `:fixtures` | No | `%{}` | Caller-supplied fixture cardinality surfaced in the digest's `coverage.fixtures` (also settable per-run via `EXCESSIBILITY_FIXTURES` JSON, which takes precedence) |

### Runtime digest environment variables

Set on `mix excessibility.debug` runs (the `--plan`/`--plan-analyze` flags set the first for you):

| Env var | Purpose |
|---------|---------|
| `EXCESSIBILITY_QUERY_PLAN` | `explain` \| `explain_analyze` \| unset. Enables opt-in query-plan capture. `explain_analyze` still requires `:query_plan_allow_analyze`. |
| `EXCESSIBILITY_FIXTURES` | JSON object of fixture cardinalities for `coverage.fixtures`. Takes precedence over `config :excessibility, :fixtures`; malformed JSON is ignored with a warning. |

Example:

```elixir
# test/test_helper.exs
Application.put_env(:excessibility, :endpoint, MyAppWeb.Endpoint)
Application.put_env(:excessibility, :system_mod, Excessibility.System)
Application.put_env(:excessibility, :browser_mod, Wallaby.Browser)
Application.put_env(:excessibility, :live_view_mod, Excessibility.LiveView)
Application.put_env(:excessibility, :excessibility_output_path, "test/accessibility")

ExUnit.start()
```

## axe-core Configuration

axe-core runs via Playwright and reports violations with structured data including `id`, `impact` (critical, serious, moderate, minor), `description`, `helpUrl`, and affected `nodes`.

You can disable specific rules via the `--disable-rules` flag:

```bash
mix excessibility --disable-rules=color-contrast
```

Or check a specific URL directly:

```bash
mix excessibility.check http://localhost:4000/my-page
```

## Screenshots

Screenshots are captured via Playwright when using `screenshot?: true`:

```elixir
html_snapshot(conn, screenshot?: true)
```

Screenshots are saved alongside HTML files with `.png` extension. Playwright is installed automatically as part of the npm dependencies.

## Mix Tasks

| Task | Description |
|------|-------------|
| `mix excessibility.install` | Configure config/test.exs, install Playwright and axe-core via npm |
| `mix excessibility` | Run axe-core against all existing snapshots |
| `mix excessibility [test args]` | Run tests, then axe-core on new snapshots (passthrough to mix test) |
| `mix excessibility.check [url]` | Run axe-core on a live URL via Playwright |
| `mix excessibility.snapshots` | List and manage HTML snapshots |
| `mix excessibility.baseline` | Lock current snapshots as baseline |
| `mix excessibility.snapshot.compare` | Compare snapshots against baseline, resolve diffs interactively |
| `mix excessibility.snapshot.compare --keep good` | Keep all baseline versions (reject changes) |
| `mix excessibility.snapshot.compare --keep bad` | Accept all new versions as baseline |
| `mix excessibility.review` | Report the accessibility blast radius of changes vs the baseline |
| `mix excessibility.review --format json` | Emit the review as a single JSON object for CI (`--json` alias) |
| `mix excessibility.review --fail-on block\|review\|never` | Choose which tier fails the build (default: `block`) |
| `mix excessibility.review --timeline <file> --fail-on-behavioral` | Fold in behavioral findings and gate on serious ones |
| `mix excessibility.debug [test args]` | Run tests with telemetry, generate debug report (passthrough to mix test) |
| `mix excessibility.debug [test args] --format=json` | Output debug report as JSON |
| `mix excessibility.debug [test args] --format=package` | Create debug package directory |
| `mix excessibility.debug [test args] --format=digest` | Print the value-free `digest.json` runtime-evidence artifact |
| `mix excessibility.debug [test args] --plan` | Capture value-free EXPLAIN plan evidence (Postgres-only, SELECT-only, no execution) |
| `mix excessibility.debug [test args] --plan-analyze` | Capture EXPLAIN ANALYZE evidence (executes queries; requires `:query_plan_allow_analyze`) |
| `mix excessibility.debug [test args] --benchmark=N` | Run the test N times, write `benchmark.json` with cold/warm robust timing stats |
| `mix excessibility.digest.compare --base B --head H [--format json]` | Structurally compare two `digest.json` artifacts (no verdict, always exits 0) |
| `mix excessibility.latest` | Display most recent debug report |
| `mix excessibility.package [test]` | Create debug package (alias for --format=package) |

## CI and Non-Interactive Environments

For CI or headless environments where you don't want interactive prompts or browser opens, mock the system module:

```elixir
# test/test_helper.exs
Mox.defmock(Excessibility.SystemMock, for: Excessibility.SystemBehaviour)
Application.put_env(:excessibility, :system_mod, Excessibility.SystemMock)
```

Then stub in your tests:

```elixir
import Mox

setup :verify_on_exit!

test "snapshot without browser open", %{conn: conn} do
  Excessibility.SystemMock
  |> stub(:open_with_system_cmd, fn _path -> :ok end)

  conn = get(conn, "/")
  html_snapshot(conn, open_browser?: true)  # Won't actually open
end
```

## File Structure

```
test/
└── excessibility/
    ├── html_snapshots/          # Current test snapshots
    │   ├── MyApp_PageTest_42.html
    │   └── MyApp_PageTest_42.png   # (if screenshot?: true)
    └── baseline/                # Locked baselines (via mix excessibility.baseline)
        └── MyApp_PageTest_42.html
```

During `mix excessibility.snapshot.compare`, temporary `.good.html` and `.bad.html` files are created for diffing, then cleaned up after resolution.

## License

MIT © Andrew Moore
