# Excessibility

[![Hex.pm](https://img.shields.io/hexpm/v/excessibility.svg)](https://hex.pm/packages/excessibility)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgrey.svg)](https://hexdocs.pm/excessibility)
[![CI](https://github.com/lessthanseventy/excessibility/actions/workflows/ci.yml/badge.svg)](https://github.com/lessthanseventy/excessibility/actions)
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

Add to `mix.exs`:

```elixir
def deps do
  [
    {:excessibility, "~> 0.5"}
  ]
end
```

Fetch dependencies with `mix deps.get`, then run `mix igniter.install excessibility` to insert the recommended `test/test_helper.exs` configuration and install Pa11y’s npm dependency inside `assets/`.

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

3. Run `mix test`. Snapshots land in `test/excessibility/html_snapshots/` and baselines in `test/excessibility/baseline/`. Run `mix excessibility` to execute Pa11y, and `mix excessibility.approve [--keep bad|good]` to promote intentional diffs. If you enable `screenshot?: true`, ensure `ChromicPDF` is supervised (e.g., `{ChromicPDF, name: ChromicPDF}`) so PNG rendering works automatically.

📸 Usage

```elixir
import Excessibility

html_snapshot(conn, __ENV__, __MODULE__,
  name: "homepage.html",
  prompt_on_diff: false,
  screenshot?: true
)
```

`html_snapshot/4` works with `Plug.Conn`, `Wallaby.Session`, `Phoenix.LiveViewTest.View`, and `Phoenix.LiveViewTest.Element`. Options let you control prompts, cleanup, tagging, screenshot generation, and custom filenames on a per-snapshot basis.

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

- `mix igniter.install excessibility` – inserts the recommended `test/test_helper.exs` configuration and installs Pa11y via npm.
- `mix excessibility` – runs Pa11y against every generated snapshot (fails fast if Pa11y is missing).
- `mix excessibility.approve [--keep good|bad]` – promotes `.good/.bad.html` diffs back into the `baseline/` directory without rerunning the test suite.

📄 License

MIT © Andrew Moore
