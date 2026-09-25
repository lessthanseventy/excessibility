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

## Features

- Snapshot HTML from `Plug.Conn`, `Wallaby.Session`, `Phoenix.LiveViewTest.View`, and `Phoenix.LiveViewTest.Element`
- Explicit baseline locking and comparison workflow
- Interactive good/bad approval when comparing snapshots
- Screenshots via Playwright
- Mockable system/browser calls for CI
- axe-core accessibility checking with sensible LiveView defaults

## Installation

Add to `mix.exs`:

```elixir
def deps do
  [
    {:excessibility, "~> 0.20", only: [:dev, :test]}
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

## Guides

- [Library Guide](docs/library-api.md) — LiveView-aware rules, Scanner API, baseline and blast-radius review workflows, configuration, axe-core config, screenshots, Mix task reference, CI, file structure.
- [LLM Debugging Guide](docs/llm-debugging.md) — telemetry auto-capture, `mix excessibility.debug`, the runtime evidence digest, MCP server and Claude Code skills.

## License

MIT © Andrew Moore
