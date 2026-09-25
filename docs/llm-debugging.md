# LLM Debugging Guide

Telemetry capture, the value-free runtime evidence digest, and the MCP server / Claude Code skills. For install and a first snapshot, see the [README](../README.md); for the snapshot/axe library reference, see the [Library Guide](library-api.md).

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
    "capture_version": "0.20.0",
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

**Privacy guarantee.** The digest **never** contains assign values, params/form values, user/session records, SQL bind values, SQL comment contents, rendered HTML, or arbitrary inspected terms. Every field is a name, a shape, a coarse size, a count, or a fingerprint. Redaction is by omission — if a field cannot be derived safely, it is left out, not guessed. Line and block comments are stripped from normalized SQL by a literal-aware scanner (comment markers inside string/dollar-quoted literals or quoted identifiers are preserved, not mistaken for comments), and `coverage.fixtures` is validated down to string-key → non-negative-integer cardinalities only — non-numeric or nested fixture values are dropped and their key names surfaced as a value-free `capture.warnings` entry.

The **coverage/status contract** makes silence interpretable: an unexercised callback is simply absent from `callbacks_observed`; `ecto_configured: false` means "queries were not measured" (distinct from measured-and-zero); a disabled enricher or failed capture shows up in `enrichers_run` / `status` + `warnings`. A missing signal is always labeled *why*.

Print the digest for the last run with:

```bash
mix excessibility.debug --format digest test/my_live_view_test.exs
```

`--format digest` only reads and prints the `digest.json` that capture already wrote; it never rebuilds it.

### Query fingerprints and N+1

Every captured Ecto query is normalized into a stable, value-free SQL shape (`Excessibility.SQLFingerprint`): keywords downcased, line/block **comments stripped** (literal-aware, so a `--` or `/* */` inside a string or quoted identifier is left intact), `$1,$2 → $?`, `IN (...)` arity folded, inline numeric/quoted literals scrubbed to `?`, whitespace collapsed. A `sha256:` fingerprint is derived from that normalized string. N+1 evidence groups by **fingerprint** (via the shared `Excessibility.QueryEvidence`), so two *different* SELECTs on the same table are counted as two shapes rather than lumped together by table name. The normalizer is Postgres-oriented (the Ecto reference adapter emits parameterized SQL); other adapters still fingerprint via the generic regex.

### Opt-in query-plan (EXPLAIN) evidence — Postgres-only

Off by default. When enabled, each recorded SELECT is run through `EXPLAIN` and a **value-free** plan summary (node types, relation names, row estimates only — never row data) is attached to its query shape, with a stable plan fingerprint over the node-type + relation tree.

The summary also carries a bounded, value-free **`node_rows`** list — one entry per plan node in depth-first order with `node`, `relation`, `depth`, `estimated_rows`, and (only under `--plan-analyze`) `actual_rows`, `loops`, `rows_touched` (= `actual_rows × loops`) and `estimate_error`. This preserves the magnitude of an expensive child scan beneath a one-row root — a query can return a single row while looping over thousands underneath, which the structural fingerprint alone discards. `mix excessibility.digest.compare` compares these node numbers **even when the plan fingerprint is unchanged**, and reports structural plan changes (a different node tree) separately from numeric ones (the same tree doing more row work).

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

Runs the test N times and writes a value-free `benchmark.json` with robust **cold vs warm** timing stats (median + MAD) per `(view, callback)` and per query-fingerprint. Sample 1 is treated as cold (compilation, connection warmup, cold caches); samples 2..N are warm, reported separately so a cold first run cannot poison the median. A warm sample is surfaced as an **advisory** outlier only when it clears **all three** gates — the statistical threshold `median + k·MAD`, a minimum absolute delta (`:benchmark_min_abs_ms`, default 1.0 ms), and a minimum relative delta (`:benchmark_min_rel_factor`, default 1.5×) — so sub-millisecond scheduler/timer jitter is never reported as actionable. Outliers from too few warm samples carry `weak_evidence: true` and the artifact adds a run-level note. Never a pass/fail gate.

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

