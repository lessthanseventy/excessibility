# Library Guide

Reference for the snapshot/axe-core library: LiveView-aware rules, the runtime Scanner API, the baseline and review workflows, configuration, and Mix tasks. For install and a first snapshot, see the [README](../README.md). For telemetry, the digest, and AI tooling, see the [LLM Debugging Guide](llm-debugging.md).

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
Add `--screenshots` to also save a full-page PNG per snapshot per width
(`landing.320x800.png`) — the evidence a reflow claim needs. It is off by
default because it drives a browser screenshot for every snapshot at every
width. Screenshots taken during a test run (`html_snapshot(view,
screenshot?: true)`) honour the same `:viewports` list, so a suite can emit
its narrow-width images without a separate pass.
Scan reports also carry a `:warnings` list — e.g. a linked stylesheet
that failed to load, which would silently invalidate contrast findings.

See `Excessibility.Scanner` for the full report type and options list.
Unlike Mix tasks, the Scanner is safe to call from production Phoenix
releases, which makes it easy to build things like a public URL
accessibility scanner, background monitoring jobs, or an internal
scanning service on top of the library.

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
  "excessibility_version": "0.20.0",
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
| `:viewports` | No | `[]` | `{width, height}` tuples to scan each snapshot at — used by `mix excessibility` and by `html_snapshot(source, screenshot?: true)`, which writes one PNG per width |
| `:screenshots` | No | `false` | Make `mix excessibility` save a full-page PNG beside each snapshot (one per viewport). Equivalent to `--screenshots` |
| `:check_clipping` | No | `false` | Flag interactive elements mostly outside the visible area, plus page-level horizontal overflow |
| `:clipping_ratio` | No | `0.9` | Minimum visible-width ratio before an element counts as clipped |
| `:head_render_path` | No | `"/"` | Route used for rendering `<head>` content |
| `:ecto_repos` | No | `[]` | Repos to capture query telemetry from, enabling N+1 / query analysis in `mix excessibility.debug` and `--timeline` reviews (e.g. `[MyApp.Repo]`) |
| `:slow_event_ms` | No | `1000` | Absolute "very slow event" ceiling for the performance analyzer. Performance findings are otherwise **relative** (outliers, bottleneck-share) and computed from test timings, so uniformly-slow code isn't flagged — lower this only if your test timings are representative of production |
| `:custom_enrichers` | No | `[]` | List of custom enricher modules (see [Telemetry Timeline Analysis](llm-debugging.md#-telemetry-timeline-analysis)) |
| `:custom_analyzers` | No | `[]` | List of custom analyzer modules (see [Telemetry Timeline Analysis](llm-debugging.md#-telemetry-timeline-analysis)) |
| `:sql_dialect` | No | `:postgres` | SQL dialect for query normalization/EXPLAIN. Only `:postgres` ships today; the `Excessibility.Dialect` seam lets a new dialect drop in |
| `:query_plan_allow_analyze` | No | `false` | Second gate for `--plan-analyze` (EXPLAIN ANALYZE, which executes queries). Enable only in a read-only DB sandbox |
| `:digest_include_normalized_sql` | No | `true` | Include the normalized (value-free) SQL string in each digest query shape; set `false` to emit fingerprint-only |
| `:fixtures` | No | `%{}` | Caller-supplied fixture cardinality surfaced in the digest's `coverage.fixtures` (also settable per-run via `EXCESSIBILITY_FIXTURES` JSON, which takes precedence). Validated to string-key → non-negative-integer entries only; strings, floats, and nested maps/lists are dropped (rejected key names appear in `capture.warnings`) |
| `:digest_min_assign_delta_bytes` | No | `64` | `mix excessibility.digest.compare` suppresses byte-only assign deltas below this many bytes when the cardinality is unchanged (tiny per-assign jitter is noise); a cardinality change is never suppressed. Set `0` for exact-byte behavior |
| `:benchmark_min_abs_ms` | No | `1.0` | Benchmark outliers must exceed the median by at least this many ms (kills sub-millisecond scheduler/timer jitter). Set `0.0` with `:benchmark_min_rel_factor` `1.0` to restore pure-statistical flagging |
| `:benchmark_min_rel_factor` | No | `1.5` | Benchmark outliers must also be at least this multiple of the median (a meaningful relative effect on top of the absolute floor) |

### Runtime digest environment variables

Set on `mix excessibility.debug` runs (the `--plan`/`--plan-analyze` flags set the first for you):

| Env var | Purpose |
|---------|---------|
| `EXCESSIBILITY_QUERY_PLAN` | `explain` \| `explain_analyze` \| unset. Enables opt-in query-plan capture. `explain_analyze` still requires `:query_plan_allow_analyze`. |
| `EXCESSIBILITY_FIXTURES` | JSON object of fixture cardinalities for `coverage.fixtures`. Takes precedence over `config :excessibility, :fixtures`; malformed JSON is ignored with a warning. Entries are validated to non-negative-integer cardinalities — string/nested values are dropped, never copied into the digest. |

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

To shoot the same snapshot at several widths — the only way to produce
evidence for a WCAG 1.4.10 Reflow claim — pass `:viewports`, or set the
`:viewports` config key once and let every `screenshot?: true` call inherit it:

```elixir
html_snapshot(conn, screenshot?: true, viewports: [{1440, 900}, {320, 800}])
#=> MyApp_PageTest_42.1440x900.png
#=> MyApp_PageTest_42.320x800.png
```

Each width gets its own suffixed PNG; the unsuffixed `.png` is written only
when no viewports are configured (pass `viewports: []` at the call site to
opt one snapshot back out of a suite-wide setting). The previous run's images
are cleared before each capture, so a leftover narrow-width PNG can never sit
beside fresh ones pretending to be current evidence. Note that the runner
analyses each width in turn, so N viewports costs N axe runs per screenshot. To capture images for snapshots you already
have, run `mix excessibility --screenshots --viewports 1440x900,320x800`.

## Mix Tasks

| Task | Description |
|------|-------------|
| `mix excessibility.install` | Configure config/test.exs, install Playwright and axe-core via npm |
| `mix excessibility` | Run axe-core against all existing snapshots |
| `mix excessibility [test args]` | Run tests, then axe-core on new snapshots (passthrough to mix test) |
| `mix excessibility --screenshots` | Also save a full-page PNG beside each snapshot, one per `--viewports` width |
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

