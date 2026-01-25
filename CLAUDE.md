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
# Generate snapshots (run tests first)
mix test

# Run Pa11y against snapshots
mix excessibility

# Approve pending diffs interactively
mix excessibility.approve

# Approve all diffs as good (keep baseline)
mix excessibility.approve --keep good

# Approve all diffs as bad (accept new versions)
mix excessibility.approve --keep bad
```

### Timeline Analysis

The telemetry capture automatically generates `timeline.json` for each test run:

```bash
# Run test with telemetry capture
mix test test/my_live_view_test.exs

# View timeline
cat test/excessibility/timeline.json

# Generate debug report with filtering options
mix excessibility.debug test/my_live_view_test.exs
mix excessibility.debug test/my_live_view_test.exs --full
mix excessibility.debug test/my_live_view_test.exs --highlight=current_user,cart
```

Timeline JSON structure:
- `test` - Test name
- `duration_ms` - Total test duration
- `timeline[]` - Array of events with:
  - `sequence` - Event number
  - `event` - Event type (mount, handle_event:name, etc.)
  - `timestamp` - ISO8601 timestamp
  - `key_state` - Extracted important state
  - `changes` - Diff from previous event

**Filtering Options:**

By default, telemetry snapshots filter out noise:
- Ecto `__meta__` fields and `NotLoaded` associations
- Phoenix internals (`flash`, `__changed__`, `__temp__`)
- Private assigns (starting with `_`)

Use `--full` to disable filtering and see complete assigns.

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
- `:pa11y_config` - Path to pa11y.json (default: `"pa11y.json"`)
- `:head_render_path` - Route for `<head>` extraction (default: `"/"`)

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
