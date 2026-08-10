# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Excessibility** is an Elixir library for accessibility snapshot testing in Phoenix applications. It captures HTML snapshots during tests and runs them through Pa11y for WCAG compliance checking.

## Development Commands

### Testing
```bash
# Run all tests
mix test

# Run specific test file
mix test test/snapshot_test.exs

# Run tests with a specific line number
mix test test/snapshot_test.exs:42

# Run tests in watch mode (interactive)
mix test.interactive
```

### Linting & Formatting
```bash
# Run static analysis
mix credo

# Format code (using Styler)
mix format
```

### Documentation
```bash
# Generate documentation
mix docs

# View docs locally
open doc/index.html
```

### Accessibility Testing
```bash
# Run Pa11y on all existing snapshots
mix excessibility

# Run specific test + Pa11y on new snapshots
mix excessibility test/my_test.exs
mix excessibility test/my_test.exs:42
mix excessibility --only a11y

# Approve pending diffs interactively
mix excessibility.approve

# Approve all diffs as good (keep baseline)
mix excessibility.approve --keep good

# Approve all diffs as bad (accept new versions)
mix excessibility.approve --keep bad
```

## Claude Workflow for Accessibility

When helping users write accessible Phoenix code, follow this workflow:

### 1. Add Snapshot Calls to Tests

For any LiveView or controller test, add `html_snapshot()` calls to capture rendered HTML:

```elixir
defmodule MyAppWeb.PageLiveTest do
  use MyAppWeb.ConnCase
  use Excessibility  # Required

  test "page is accessible", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Capture snapshot for Pa11y
    html_snapshot(view)

    # Continue with assertions...
  end
end
```

### 2. Run Tests to Generate Snapshots

```bash
mix test test/my_app_web/live/page_live_test.exs
```

This creates HTML files in `test/excessibility/html_snapshots/`.

### 3. Run Pa11y Accessibility Check

```bash
# Check all existing snapshots
mix excessibility

# Or run a specific test and check new snapshots in one command
mix excessibility test/my_app_web/live/page_live_test.exs
mix excessibility test/my_test.exs:42
mix excessibility --only a11y
```

Pa11y will report WCAG violations. Common issues:
- Missing form labels
- Low color contrast
- Missing alt text
- Invalid ARIA attributes

### 4. Fix Issues and Re-test

After fixing accessibility issues, re-run tests and Pa11y to verify.

### Timeline Analysis (for debugging)

Use `mix excessibility.debug` to analyze LiveView behavior. All arguments pass through to `mix test`:

```bash
# Run a test file with debug analysis
mix excessibility.debug test/my_live_view_test.exs

# Run specific test by line number
mix excessibility.debug test/my_live_view_test.exs:42

# Run tests with a tag
mix excessibility.debug --only live_view

# With debug options
mix excessibility.debug test/my_test.exs --analyze=memory
mix excessibility.debug test/my_test.exs --no-analyze
mix excessibility.debug test/my_test.exs --verbose
mix excessibility.debug test/my_test.exs --full
mix excessibility.debug test/my_test.exs --highlight=current_user,cart
```

This generates `timeline.json` with event flow, memory usage, and pattern analysis - useful for debugging performance but separate from accessibility testing.

### Runtime Evidence Digest (`digest.json`)

Every `mix excessibility.debug` capture writes **two** artifacts (both in `Excessibility.TelemetryCapture.write_snapshots/1`):

- **`timeline.json`** - the full local diagnosis. Contains filtered assigns, raw SQL, memory sizes/diffs. **Local debugging only** - it may contain application data and is **NOT safe to upload** to CI/artifacts/models.
- **`digest.json`** - a **value-free, safe-by-construction** artifact built by `Excessibility.Digest`. Built by explicit construction from an allowlist (never copy-then-scrub), so it is safe for CI, artifact stores, and model input. Position it as **supplemental** input for debugging and code-aware review - not a universal performance verdict and not a replacement for source-aware review.

**Schema `excessibility.digest/v1`** - top-level keys `capture` (status, `ecto_configured`, `enrichers_run`, `plan_capture`, `timing`, `capture_version`, `warnings`), `coverage` (tests, views, `callbacks_observed`, `event_sequence`, `fixtures`), `events[]` (per event: `queries` with fingerprint `shapes`/`repeated`/`overflow`, and `assigns` with per-assign name/kind/cardinality/`term_bytes`/`delta_bytes`/`growth`), and `trajectories` (per-view `monotonic_growth`/`retained_after_use`).

**Privacy guarantee:** the digest never contains assign values, params, form/bind values, raw SQL, rendered HTML, or arbitrary inspected terms - only names, shapes, coarse sizes, counts, and fingerprints. Missing signals are always labeled *why* via the coverage/status contract (`ecto_configured: false` = "not measured" ≠ measured-and-zero).

Print it with `mix excessibility.debug --format digest test/my_test.exs` (reads the already-written `digest.json`; does not rebuild it).

**Query fingerprints & N+1** - each Ecto query is normalized to a value-free SQL shape (`Excessibility.SQLFingerprint`) and given a `sha256:` fingerprint. N+1 evidence groups by fingerprint (via `Excessibility.QueryEvidence`), so two different SELECTs on the same table stay distinct. Postgres-oriented normalizer.

**Opt-in query-plan (EXPLAIN) evidence** (Postgres-only):
- `--plan` -> runs `EXPLAIN (FORMAT JSON)` (plans, never executes; SELECT-only). Sets `EXCESSIBILITY_QUERY_PLAN=explain`.
- `--plan-analyze` -> runs `EXPLAIN ANALYZE` (executes the query for real row counts). Double-gated: also requires `config :excessibility, query_plan_allow_analyze: true`, else downgrades to `EXPLAIN` with a warning. Sandbox/read-only only. Sets `EXCESSIBILITY_QUERY_PLAN=explain_analyze`.
- Other adapters: plan capture is a documented no-op (`plan_capture` stays `disabled`).

**Compare** - `mix excessibility.digest.compare --base B --head H [--format json]` (`Excessibility.DigestCompare`) reports structural query/plan/assign/coverage deltas only. Measurement-scope-guarded (never fabricates a delta when the two sides measured different signals), **no merge verdict**, **always exits 0**. (Note: the a11y snapshot task moved to `mix excessibility.snapshot.compare`; bare `mix excessibility.compare` was removed - breaking change in the CHANGELOG.)

**Benchmark mode** - `mix excessibility.debug --benchmark=N` runs the test N times and writes `benchmark.json` with robust cold-vs-warm stats (median + MAD) per `(view, callback)` and per fingerprint. Sample 1 = cold, 2..N = warm, reported separately. Timing **never** enters the digest.

**Timing contract** - single-run timing is diagnostic-only and marked `timing: non_comparable` in the digest. Green means "no relative/configured outlier in this run," NOT "this code is fast." Use benchmark mode for comparable timing.

**Available Analyzers (Default Enabled):**

- `memory` - Detects memory bloat and leaks using adaptive thresholds
- `performance` - Identifies slow events and bottlenecks
- `data_growth` - Analyzes list growth patterns
- `event_pattern` - Detects inefficient event patterns
- `ecto_query_analysis` - Full Ecto query analysis with N+1 detection (requires `config :excessibility, ecto_repos: [MyApp.Repo]`)
- `assign_diff` - Detects large assigns re-diffed over the wire
- `state_machine` - Analyzes state transitions
- `render_efficiency` - Detects wasted renders with no state changes
- `assign_lifecycle` - Finds dead state (assigns that never change)
- `handle_event_noop` - Detects empty event handlers
- `form_validation` - Flags excessive validation roundtrips
- `summary` - Natural language timeline overview

**Available Analyzers (Opt-in):**

- `cascade_effect` - Detects rapid event cascades (use `--analyze=cascade_effect`)
- `hypothesis` - Root cause suggestions (use `--analyze=hypothesis`)
- `code_pointer` - Maps events to source locations (use `--analyze=code_pointer`)
- `message_flooding` - Detects high-frequency handle_info patterns (needs the opt-in `on_mount Excessibility.TelemetryCapture` hook, then `--analyze=message_flooding`)
- `accessibility_correlation` - Flags state changes with a11y implications (use `--analyze=accessibility_correlation`)
- `component_rerender` - Detects unnecessary component re-renders (use `--analyze=component_rerender`)
- `push_event_volume` - Detects excessive push_event volume to JS hooks (use `--analyze=push_event_volume`)

**Timeline Enrichments:**

Timeline events are automatically enriched with:
- `assign_sizes` - Per-assign byte sizes (map of assign name to bytes)
- `total_memory` - Total assigns memory in bytes
- `largest_assign` - Largest assign name and size tuple
- `event_duration_ms` - Event duration from telemetry
- `ecto_queries` - Ecto queries fired during event (list of query maps)
- `ecto_query_count` - Number of Ecto queries per event
- `ecto_total_query_ms` - Total Ecto query time per event
- `push_events` - push_event calls during event
- `push_event_count` - Number of push_event calls per event

**Captured Events:**
- `mount` - LiveView mount
- `handle_params` - URL parameter handling
- `handle_event:name` - User interactions (click, submit, etc.)
- **`render`** - Render cycles (triggered by render_change, render_click, render_submit)
  - **Most frequent event type** - provides richest timeline data
  - Enables memory leak detection, performance analysis, and event pattern detection
  - Automatically enabled when running `mix excessibility.debug`
  - See README for dramatic before/after comparison of event counts

Timeline JSON structure:
- `test` - Test name
- `duration_ms` - Total test duration
- `timeline[]` - Array of events with:
  - `sequence` - Event number
  - `event` - Event type (mount, handle_event:name, etc.)
  - `timestamp` - ISO8601 timestamp
  - `memory_size` - Byte size of assigns (added by enricher)
  - `key_state` - Extracted important state
  - `changes` - Diff from previous event

**Filtering Options:**

By default, telemetry snapshots filter out noise:
- Ecto `__meta__` fields and `NotLoaded` associations
- Phoenix internals (`flash`, `__changed__`, `__temp__`)
- Private assigns (starting with `_`)

Use `--full` to disable filtering and see complete assigns.

**Creating Custom Enrichers:**

Built-in enrichers are auto-discovered from `lib/telemetry_capture/enrichers/`.
Users can also register custom enrichers in their own apps via config:

```elixir
# lib/my_app/enrichers/custom.ex
defmodule MyApp.Enrichers.Custom do
  @behaviour Excessibility.TelemetryCapture.Enricher

  def name, do: :custom

  def enrich(assigns, _opts) do
    %{custom_field: compute_value(assigns)}
  end
end

# config/test.exs
config :excessibility,
  custom_enrichers: [MyApp.Enrichers.Custom]
```

**Creating Custom Analyzers:**

Built-in analyzers are auto-discovered from `lib/telemetry_capture/analyzers/`.
Users can also register custom analyzers in their own apps via config:

```elixir
# lib/my_app/analyzers/custom.ex
defmodule MyApp.Analyzers.Custom do
  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :custom
  def default_enabled?, do: false

  def analyze(timeline, _opts) do
    %{
      findings: [...],
      stats: %{...}
    }
  end
end

# config/test.exs
config :excessibility,
  custom_analyzers: [MyApp.Analyzers.Custom]
```

### Installation (for testing installer)
```bash
# Run the installer task
mix igniter.install excessibility
```

## Architecture

### Core Flow

The library follows this flow when a test calls `html_snapshot/2`:

1. **Entry Point** (`Excessibility` module): Provides the `html_snapshot/2` macro that tests use
2. **Source Protocol** (`Excessibility.Source`): Protocol-based HTML extraction supporting:
   - `Plug.Conn` - Controller test responses
   - `Wallaby.Session` - Browser-based tests
   - `Phoenix.LiveViewTest.View` - LiveView test views
   - `Phoenix.LiveViewTest.Element` - LiveView elements
3. **HTML Wrapping** (`Excessibility.HTML`): Wraps partial HTML in complete document structure:
   - Extracts `<head>` from Phoenix endpoint
   - Prefixes static asset paths with `file://` for local Pa11y access
   - Removes `<script>` tags (can't execute in static snapshots)
4. **Snapshot Management** (`Excessibility.Snapshot`): Handles file I/O and diffing:
   - Writes snapshots to `test/excessibility/html_snapshots/`
   - Compares against baselines in `test/excessibility/baseline/`
   - Creates `.good.html` and `.bad.html` when diffs detected
   - Optionally generates PNG screenshots via ChromicPDF
   - Interactive diff resolution (prompt user to keep good or bad)

### Key Design Patterns

**Protocol-Based Extensibility**: The `Excessibility.Source` protocol allows supporting multiple test source types without coupling to specific implementations.

**Behavior-Based Mocking**: System operations (file opening, browser calls) use behaviors (`SystemBehaviour`, `BrowserBehaviour`) to enable mocking in tests and CI environments. Configuration is application-env based:
```elixir
Application.get_env(:excessibility, :system_mod, Excessibility.System)
```

**Compile-Time Configuration**: Paths like `:excessibility_output_path` are read at compile time via `Application.compile_env/3` for performance, but most config is runtime via `Application.get_env/3`.

**Macro-Based Context Capture**: The `html_snapshot/2` macro captures `__ENV__` and `__MODULE__` at call site to auto-generate meaningful filenames like `MyApp_PageTest_42.html` (module_line.html).

### Module Responsibilities

- **`Excessibility`**: Public API macro
- **`Excessibility.Snapshot`**: Core snapshot generation, diffing, file management
- **`Excessibility.Source`**: Protocol for HTML extraction from test sources
- **`Excessibility.HTML`**: HTML wrapping and static path resolution
- **`Excessibility.LiveView`**: LiveView-specific rendering logic
- **`Excessibility.System`**: System command wrapper (implements `SystemBehaviour`)
- **Behaviors**: `SystemBehaviour`, `BrowserBehaviour` for mockable dependencies
- **Mix Tasks**:
  - `Mix.Tasks.Excessibility` - Run Pa11y on snapshots
  - `Mix.Tasks.Excessibility.Approve` - Interactive diff approval
  - `Mix.Tasks.Excessibility.Install` - Configure project, install Pa11y via npm

### Configuration Points

All configuration in `test/test_helper.exs` or `config/test.exs`:

- `:endpoint` - Phoenix endpoint module (required)
- `:system_mod` - System command module (default: `Excessibility.System`)
- `:browser_mod` - Browser module (default: `Wallaby.Browser`)
- `:live_view_mod` - LiveView module (default: `Excessibility.LiveView`)
- `:excessibility_output_path` - Base directory (default: `"test/excessibility"`)
- `:pa11y_path` - Path to Pa11y executable (auto-detected)
- `:playwright_path` - Path to an existing Playwright installation to reuse (default: bundled copy in `assets/`)
- `:node_modules_path` - Path to a host `node_modules` providing `playwright` and `@axe-core/playwright` (default: bundled copy in `assets/`)
- `:pa11y_config` - Path to pa11y.json (default: `"pa11y.json"`)
- `:head_render_path` - Route for `<head>` extraction (default: `"/"`)
- `:ecto_repos` - Repos to capture query telemetry from for N+1/query analysis (default: `[]`, e.g. `[MyApp.Repo]`)
- `:custom_enrichers` - List of custom enricher modules (default: `[]`)
- `:custom_analyzers` - List of custom analyzer modules (default: `[]`)
- `:sql_dialect` - SQL dialect for query normalization/EXPLAIN (default: `:postgres`; only Postgres ships, behind the `Excessibility.Dialect` seam)
- `:query_plan_allow_analyze` - Second gate for `--plan-analyze` / `EXPLAIN ANALYZE`, which executes queries (default: `false`; enable only in a read-only DB sandbox)
- `:fixtures` - Caller-supplied fixture cardinalities surfaced in the digest's `coverage.fixtures` (default: `%{}`; `EXCESSIBILITY_FIXTURES` env JSON takes precedence)
- `:digest_include_normalized_sql` - Include the normalized value-free SQL string in digest query shapes (default: `true`; `false` = fingerprint-only)

**Runtime digest env vars** (set on `mix excessibility.debug` runs):
- `EXCESSIBILITY_QUERY_PLAN` - `explain` | `explain_analyze` | unset; enables opt-in query-plan capture (`--plan`/`--plan-analyze` set this). `explain_analyze` still requires `:query_plan_allow_analyze`.
- `EXCESSIBILITY_FIXTURES` - JSON object of fixture cardinalities for `coverage.fixtures`; precedence over `config :excessibility, :fixtures`; malformed JSON is ignored with a warning.

## Testing Strategy

### Mocking Pattern

Tests use Mox to mock system operations and avoid side effects:

```elixir
# In test/test_helper.exs
Mox.defmock(Excessibility.SystemMock, for: Excessibility.SystemBehaviour)
Mox.defmock(Excessibility.BrowserMock, for: Excessibility.BrowserBehaviour)
Mox.defmock(Excessibility.LiveViewMock, for: Excessibility.LiveView.Behaviour)

Application.put_env(:excessibility, :system_mod, Excessibility.SystemMock)
Application.put_env(:excessibility, :browser_mod, Excessibility.BrowserMock)
Application.put_env(:excessibility, :live_view_mod, Excessibility.LiveViewMock)
```

### Test Setup Patterns

Always include Mox setup in tests that mock:

```elixir
defmodule MyTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!  # Ensures all expectations are satisfied

  test "example" do
    expect(Excessibility.SystemMock, :open_with_system_cmd, fn path ->
      assert path =~ ".html"
      :ok
    end)

    # test code...
  end
end
```

### Testing Snapshots

When testing snapshot functionality, use `prompt_on_diff: false` to avoid interactive prompts:

```elixir
Excessibility.Snapshot.html_snapshot(conn, %{line: 42}, __MODULE__,
  prompt_on_diff: false,
  screenshot?: true,
  name: "custom_name.html"
)
```

Clean up generated files in tests:

```elixir
File.rm(full_path)
File.rm_rf!("test/excessibility/html_snapshots")
File.rm_rf!("test/excessibility/baseline")
```

### Creating Test Fixtures

**Plug.Conn for testing:**

```elixir
conn =
  :get
  |> Plug.Test.conn("/")
  |> Plug.Conn.put_resp_content_type("text/html")
  |> Plug.Conn.send_resp(200, "<html><body>Content</body></html>")
```

**LiveView fixtures:**

```elixir
view = %Phoenix.LiveViewTest.View{
  proxy: {nil, "topic", proxy_pid},
  target: "target"
}

element = %Phoenix.LiveViewTest.Element{
  proxy: {nil, "topic", proxy_pid}
}
```

For LiveView tests, you may need to create a GenServer proxy (see `test/live_view_test.exs` for an example).

### Test Support Files

The project has `test/support/test_endpoint.ex` which provides a minimal Phoenix endpoint for testing HTML attribute extraction. ChromicPDF is started in `test_helper.exs` for screenshot testing.

## Coding Conventions

**Boolean Variables:**
- All boolean variables and local bindings should end with `?` (e.g., `verbose?`, `enabled?`)
- Boolean function names should end with `?` (e.g., `default_enabled?()`, `is_valid?()`)
- CLI option keys don't need `?` as they're just atoms (e.g., `:verbose`, `:no_analyze`)

**Example:**
```elixir
# Good
def format_section(data, opts) do
  verbose? = Keyword.get(opts, :verbose, false)
  if verbose?, do: detailed_output(data), else: brief_output(data)
end

# Bad
def format_section(data, opts) do
  verbose = Keyword.get(opts, :verbose, false)
  if verbose, do: detailed_output(data), else: brief_output(data)
end
```

## Dependencies

- **Phoenix & LiveView**: Core Phoenix integration
- **Wallaby**: Browser-based testing support
- **Floki**: HTML parsing and manipulation
- **ChromicPDF**: Screenshot generation
- **Mox**: Test mocking
- **Igniter**: Installer infrastructure
- **Credo & Styler**: Code quality tools

## Pa11y Integration

Pa11y is installed via npm in the `assets/` directory by the installer. The `mix excessibility` task runs Pa11y against generated snapshots. Default config ignores LiveView-specific false positives (e.g., forms without submit buttons that use `phx-submit`).
