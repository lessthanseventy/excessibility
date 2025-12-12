# Excessibility

[![Hex.pm](https://img.shields.io/hexpm/v/excessibility.svg)](https://hex.pm/packages/excessibility)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgrey.svg)](https://hexdocs.pm/excessibility)
[![CI](https://github.com/your-org/excessibility/actions/workflows/ci.yml/badge.svg)](https://github.com/your-org/excessibility/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Accessibility Snapshot Testing for Elixir + Phoenix**

Excessibility helps you test your Phoenix apps for accessibility (WCAG compliance) by taking HTML snapshots during tests and running them through Pa11y.

It integrates with Plug.Conn, Wallaby.Session, Phoenix.LiveViewTest.View, and more. You can also diff snapshots against a baseline, auto-open mismatches, and interactively approve changes.
## Why Excessibility?

- Keep accessibility in your existing test feedback loop. Snapshots are captured inside ExUnit, Wallaby, and LiveView tests, so regressions surface together with your functional failures.
- Ship safer refactors. Baseline comparison saves `.good/.bad.html` (plus screenshots when enabled) so reviewers can see exactly what changed and approve intentionally.
- Debug CI-only failures quickly. Pa11y output points to the failing snapshot, and the saved artifacts make it easy to reproduce locally.
✨ Features

    ✅ Snapshot HTML from Conn/LiveView/Wallaby

    ✅ Save and manage snapshot files

    ✅ Automatically diff against saved baselines

    ✅ Interactive approval (good/bad) when snapshots change

    ✅ Mockable system/browser calls for CI

    ✅ Clean test output and file organization

🛠 Installation

Add to mix.exs:

def deps do
  [
    {:excessibility, github: "your-org/excessibility"}
  ]
end

Run `mix igniter.install excessibility` after fetching deps so Pa11y’s npm dependency is installed and the recommended configuration is added.

## Quick Start

1. Configure the endpoint and helper modules in `test/test_helper.exs` (or `config/test.exs`). The installer command (`mix igniter.install excessibility`) can do this for you, or add the following manually:

    ```elixir
    Application.put_env(:excessibility, :endpoint, MyAppWeb.Endpoint)
    Application.put_env(:excessibility, :system_mod, Excessibility.System)
    Application.put_env(:excessibility, :browser_mod, Wallaby.Browser)
    Application.put_env(:excessibility, :live_view_mod, Excessibility.LiveView)
    ```

2. Import `Excessibility` in the tests where you want snapshots (ConnCase, LiveViewCase, FeatureCase, etc.):

    ```elixir
    defmodule MyAppWeb.PageControllerTest do
      use MyAppWeb.ConnCase, async: true
      import Excessibility

      test "renders home page", %{conn: conn} do
        conn = get(conn, "/")

        html_snapshot(conn, __ENV__, __MODULE__,
          prompt_on_diff: false,
          screenshot?: true
        )

        assert html_response(conn, 200) =~ "Welcome!"
      end
    end
    ```

3. Run `mix test`. Snapshots land in `test/excessibility/html_snapshots/` and baselines in `test/excessibility/baseline/`. Run `mix excessibility` to execute Pa11y, and `mix excessibility.approve [--keep bad|good]` to promote intentional diffs.

### Configuration

Add the endpoint and optional overrides to your config or test helper:

```elixir
config :excessibility,
  :endpoint, MyAppWeb.Endpoint,
  :system_mod, Excessibility.System,
  :browser_mod, Wallaby.Browser,
  :live_view_mod, Excessibility.LiveView,
  :excessibility_output_path, "test/excessibility"
```

If you enable `screenshot?: true`, ensure `ChromicPDF` is supervised in your application (e.g., `{ChromicPDF, name: ChromicPDF}`) so the library can render PNGs of each snapshot.

📸 Usage
In your test:

import Excessibility

html_snapshot(conn, __ENV__, __MODULE__)

You can snapshot from:

    Plug.Conn

    Wallaby.Session

    Phoenix.LiveViewTest.View

    Phoenix.LiveViewTest.Element

Options

html_snapshot(source, env, mod, [
  open_browser?: true,
  cleanup?: true,
  tag_on_diff: true,
  prompt_on_diff: true,
  name: "homepage.html",
  screenshot?: true
])

🔍 Snapshot Diffing

    Snapshots are saved to: test/excessibility/html_snapshots/

    Baselines live in: test/excessibility/baseline/

If a snapshot differs:

    You’ll be shown .good.html (baseline) and .bad.html (new).

    You're prompted to keep the good or bad version.

    The baseline is updated accordingly.

🧪 Testing

Set up mocks in test/test_helper.exs:

Mox.defmock(Excessibility.SystemMock, for: Excessibility.SystemBehaviour)
Application.put_env(:excessibility, :system_mod, Excessibility.SystemMock)

Then define expectations in your test:

SystemMock
|> expect(:open_with_system_cmd, fn path -> ... end)

🧼 Cleaning Up

To remove old snapshots for a test module:

html_snapshot(conn, env, mod, cleanup?: true)

🧰 Mix Tasks

- `mix igniter.install excessibility` – configures `test/test_helper.exs` and installs Pa11y via npm.
- `mix excessibility` – runs Pa11y against every generated snapshot (fails fast if Pa11y is missing).
- `mix excessibility.approve [--keep good|bad]` – promotes `.good/.bad.html` diffs back into the `baseline/` directory without rerunning the test suite.

🧩 Coming Soon

    mix excessibility.lint — run Pa11y on snapshots

    mix excessibility.approve — promote diffs to baseline

    Visual snapshot diffing

📄 License

MIT © Andrew Moore
