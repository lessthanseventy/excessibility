# Excessibility

[![Hex.pm](https://img.shields.io/hexpm/v/excessibility.svg)](https://hex.pm/packages/excessibility)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgrey.svg)](https://hexdocs.pm/excessibility)
[![CI](https://github.com/lessthanseventy/excessibility/actions/workflows/ci.yml/badge.svg)](https://github.com/lessthanseventy/excessibility/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

**Accessibility Snapshot Testing for Elixir + Phoenix**

Excessibility helps you test your Phoenix apps for accessibility (WCAG compliance) by taking HTML snapshots during tests and running them through [Pa11y](https://pa11y.org/).

## Why Excessibility?

- **Keep accessibility in your existing test feedback loop.** Snapshots are captured inside ExUnit, Wallaby, and LiveView tests, so regressions surface together with your functional failures.
- **Ship safer refactors.** Baseline comparison saves `.good/.bad.html` (plus screenshots when enabled) so reviewers can see exactly what changed and approve intentionally.
- **Debug CI-only failures quickly.** Pa11y output points to the failing snapshot, and the saved artifacts make it easy to reproduce locally.

## Features

- Snapshot HTML from `Plug.Conn`, `Wallaby.Session`, `Phoenix.LiveViewTest.View`, and `Phoenix.LiveViewTest.Element`
- Automatically diff against saved baselines
- Interactive approval (good/bad) when snapshots change
- Optional PNG screenshots via ChromicPDF
- Mockable system/browser calls for CI
- Pa11y configuration with sensible LiveView defaults

## Installation

Add to `mix.exs`:

```elixir
def deps do
  [
    {:excessibility, "~> 0.5", only: [:dev, :test]}
  ]
end
```

Fetch dependencies and run the installer:

```bash
mix deps.get
mix igniter.install excessibility
```

The installer will:
- Add configuration to `test/test_helper.exs`
- Create a `pa11y.json` with sensible defaults for Phoenix/LiveView
- Install Pa11y via npm in your assets directory

## Quick Start

1. **Configure** the endpoint and helper modules in `test/test_helper.exs`. The installer does this automatically, or add manually:

    ```elixir
    Application.put_env(:excessibility, :endpoint, MyAppWeb.Endpoint)
    Application.put_env(:excessibility, :system_mod, Excessibility.System)
    Application.put_env(:excessibility, :browser_mod, Wallaby.Browser)
    Application.put_env(:excessibility, :live_view_mod, Excessibility.LiveView)
    ```

2. **Add `use Excessibility`** in tests where you want snapshots:

    ```elixir
    defmodule MyAppWeb.PageControllerTest do
      use MyAppWeb.ConnCase, async: true
      use Excessibility

      test "renders home page", %{conn: conn} do
        conn = get(conn, "/")

        html_snapshot(conn,
          prompt_on_diff: false,
          screenshot?: true
        )

        assert html_response(conn, 200) =~ "Welcome!"
      end
    end
    ```

3. **Run tests and Pa11y:**

    ```bash
    mix test                    # Generates snapshots
    mix excessibility           # Runs Pa11y against snapshots
    mix excessibility.approve   # Approve diffs interactively
    ```

## Usage

```elixir
use Excessibility

html_snapshot(conn,
  name: "homepage.html",
  prompt_on_diff: false,
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
| `:prompt_on_diff` | `boolean` | `true` | Interactively choose which snapshot to keep when diff detected |
| `:tag_on_diff` | `boolean` | `true` | Save diffs as `.bad.html` and `.good.html` files |
| `:screenshot?` | `boolean` | `false` | Generate PNG screenshots (requires ChromicPDF) |
| `:open_browser?` | `boolean` | `false` | Open the snapshot in your browser after writing |
| `:cleanup?` | `boolean` | `false` | Delete existing snapshots for the current test module before writing |

## Snapshot Diffing

Snapshots are saved to `test/excessibility/html_snapshots/` and baselines live in `test/excessibility/baseline/`.

When a snapshot differs from baseline:
1. `.good.html` (baseline) and `.bad.html` (new) files are created
2. If `prompt_on_diff: true`, you're prompted to keep good or bad
3. The baseline is updated with your choice

## Configuration

All configuration goes in `test/test_helper.exs` or `config/test.exs`:

| Config Key | Required | Default | Description |
|------------|----------|---------|-------------|
| `:endpoint` | Yes | — | Your Phoenix endpoint module (e.g., `MyAppWeb.Endpoint`) |
| `:system_mod` | No | `Excessibility.System` | Module for system commands (mockable) |
| `:browser_mod` | No | `Wallaby.Browser` | Module for browser interactions |
| `:live_view_mod` | No | `Excessibility.LiveView` | Module for LiveView rendering |
| `:excessibility_output_path` | No | `"test/excessibility"` | Base directory for snapshots |
| `:pa11y_path` | No | auto-detected | Path to Pa11y executable |
| `:pa11y_config` | No | `"pa11y.json"` | Path to Pa11y config file |
| `:head_render_path` | No | `"/"` | Route used for rendering `<head>` content |

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

## Pa11y Configuration

The installer creates a `pa11y.json` in your project root with sensible defaults for Phoenix/LiveView:

```json
{
  "ignore": [
    "WCAG2AA.Principle3.Guideline3_2.3_2_2.H32.2"
  ]
}
```

The ignored rule (H32.2) is "Form does not contain a submit button" — a common false positive for LiveView forms that use `phx-submit` without traditional submit buttons.

Add additional rules to ignore as needed for your project:

```json
{
  "ignore": [
    "WCAG2AA.Principle3.Guideline3_2.3_2_2.H32.2",
    "WCAG2AA.Principle1.Guideline1_4.1_4_3.G18.Fail"
  ]
}
```

## Screenshots

To enable PNG screenshots, add ChromicPDF to your supervision tree:

```elixir
# application.ex
children = [
  {ChromicPDF, name: ChromicPDF},
  # ...
]
```

Then use `screenshot?: true` in your snapshots:

```elixir
html_snapshot(conn, screenshot?: true)
```

Screenshots are saved alongside HTML files with `.png` extension.

## Mix Tasks

| Task | Description |
|------|-------------|
| `mix igniter.install excessibility` | Configure test helper, create pa11y.json, install Pa11y via npm |
| `mix excessibility` | Run Pa11y against all generated snapshots |
| `mix excessibility.approve` | Interactively approve pending diffs |
| `mix excessibility.approve --keep good` | Keep all baseline (good) versions |
| `mix excessibility.approve --keep bad` | Accept all new (bad) versions as baseline |

## Testing / Mocking

For CI environments where you don't want interactive prompts or browser opens, mock the system module:

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
    │   ├── MyApp_PageTest_42.png
    │   ├── MyApp_PageTest_42.bad.html
    │   └── MyApp_PageTest_42.good.html
    └── baseline/                # Approved baselines
        └── MyApp_PageTest_42.html
```

## License

MIT © Andrew Moore
