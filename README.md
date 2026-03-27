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
4. **Compare changes** with `mix excessibility.compare` to review what changed and approve/reject
5. **In CI**, axe-core reports accessibility violations alongside your test failures

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
    {:excessibility, "~> 0.12", only: [:dev, :test]}
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
    mix excessibility.compare   # Review diffs, choose good (baseline) or bad (new)
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
mix excessibility.compare
```

For each snapshot that differs from its baseline:

1. **Diff files are created** — `.good.html` (baseline) and `.bad.html` (new)
2. **Both open in your browser** for visual comparison
3. **You choose which to keep** — "good" to reject changes, "bad" to accept as new baseline
4. **Diff files are cleaned up** after resolution

**Batch options:**

```bash
mix excessibility.compare --keep good   # Keep all baselines (reject all changes)
mix excessibility.compare --keep bad    # Accept all new versions as baseline
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
| `:head_render_path` | No | `"/"` | Route used for rendering `<head>` content |
| `:custom_enrichers` | No | `[]` | List of custom enricher modules (see Timeline Analysis section above) |
| `:custom_analyzers` | No | `[]` | List of custom analyzer modules (see Timeline Analysis section above) |

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
| `mix excessibility.compare` | Compare snapshots against baseline, resolve diffs interactively |
| `mix excessibility.compare --keep good` | Keep all baseline versions (reject changes) |
| `mix excessibility.compare --keep bad` | Accept all new versions as baseline |
| `mix excessibility.debug [test args]` | Run tests with telemetry, generate debug report (passthrough to mix test) |
| `mix excessibility.debug [test args] --format=json` | Output debug report as JSON |
| `mix excessibility.debug [test args] --format=package` | Create debug package directory |
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

During `mix excessibility.compare`, temporary `.good.html` and `.bad.html` files are created for diffing, then cleaned up after resolution.

## License

MIT © Andrew Moore
