# Excessibility

[![Hex.pm](https://img.shields.io/hexpm/v/excessibility.svg)](https://hex.pm/packages/excessibility)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgrey.svg)](https://hexdocs.pm/excessibility)
[![CI](https://github.com/your-org/excessibility/actions/workflows/ci.yml/badge.svg)](https://github.com/your-org/excessibility/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Accessibility Snapshot Testing for Elixir + Phoenix**

Excessibility helps you test your Phoenix apps for accessibility (WCAG compliance) by taking HTML snapshots during tests and running them through Pa11y.

It integrates with Plug.Conn, Wallaby.Session, Phoenix.LiveViewTest.View, and more. You can also diff snapshots against a baseline, auto-open mismatches, and interactively approve changes.
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
  name: "homepage.html"
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

🧩 Coming Soon

    mix excessibility.lint — run Pa11y on snapshots

    mix excessibility.approve — promote diffs to baseline

    Visual snapshot diffing

📄 License

MIT © Andrew Moore
