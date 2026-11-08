# Excessibility

[![Hex.pm](https://img.shields.io/hexpm/v/excessibility.svg)](https://hex.pm/packages/excessibility)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgrey.svg)](https://hexdocs.pm/excessibility)
[![CI](https://github.com/lessthanseventy/excessibility/actions/workflows/ci.yml/badge.svg)](https://github.com/lessthanseventy/excessibility/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

Accessibility snapshot testing for Phoenix. Your tests save the HTML they render; one mix task
runs every snapshot through [axe-core](https://github.com/dequelabs/axe-core) in a
[Playwright](https://playwright.dev/) browser and reports the WCAG violations next to your test
failures. A baseline locks the known-good state, and a review of a change says which problems the
change newly introduced, as text or as JSON for CI.

The same capture, switched on by `mix excessibility.debug`, records what a LiveView test did
step by step, for a person or an agent debugging it: every event, the assigns at each one, the
queries it ran, and the patterns that stand out.

## Install

```elixir
def deps do
  [
    {:excessibility, "~> 0.20", only: [:dev, :test]},
    {:igniter, "~> 0.7", only: [:dev, :test], runtime: false}
  ]
end
```

```bash
mix deps.get
mix excessibility.install
```

The installer writes the configuration into `config/test.exs` and installs Playwright and
axe-core with npm in your assets directory. It runs on Igniter, which is why Igniter is in the
deps above; without it the task says so and stops. An app that needs a login for most pages
names a public route to read `<head>` from: `mix excessibility.install --head-render-path /login`.

What it writes, if you would rather write it yourself:

```elixir
config :excessibility,
  endpoint: MyAppWeb.Endpoint,
  head_render_path: "/",
  system_mod: Excessibility.System,
  browser_mod: Wallaby.Browser,
  live_view_mod: Excessibility.LiveView
```

## A first snapshot

`use Excessibility` in a test module gives it `html_snapshot/2`, which writes the rendered HTML
to `test/excessibility/` and hands its argument back unchanged, so it sits in a pipeline.

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

It takes a `Plug.Conn`, a `Wallaby.Session`, a `Phoenix.LiveViewTest.View` or a
`Phoenix.LiveViewTest.Element`.

| Option | Default | |
|---|---|---|
| `:name` | `ModuleName_LineNumber.html` | the snapshot's file name |
| `:screenshot?` | `false` | a PNG of the snapshot too, through Playwright |
| `:open_browser?` | `false` | open the snapshot in your browser once written |
| `:cleanup?` | `false` | delete the module's earlier snapshots first |

## The workflow

```bash
mix excessibility test/my_test.exs       # run the test, then axe-core over its snapshots
mix excessibility test/my_test.exs:42
mix excessibility --only a11y

mix test                                 # or run the tests yourself
mix excessibility                        # then check every snapshot

mix excessibility.baseline               # lock what is there as the known-good state

mix test                                 # after a UI change
mix excessibility.snapshot.compare       # each diff: keep the baseline, or take the new one
mix excessibility.review                 # what the change newly introduced, by view, with a risk tier
mix excessibility.review --format json   # the same as one JSON object, for CI and PR bots
```

`mix excessibility` checks each snapshot on its own. `mix excessibility.review` diffs every current
snapshot against its baseline and reports, per view, the regions that changed and the axe-core
and LiveView-rule findings the change introduced, failing the build on `:block` by default
(`--fail-on review`, `--fail-on never`, `--no-axe` to skip the browser scans).

`Excessibility.Scanner.scan/2` is the same axe-core scan as a function: give it a URL from a
LiveView handler, a job or a script and get the structured report back.

## Debugging a LiveView test

```bash
mix excessibility.debug test/my_test.exs
```

No change to the test. Telemetry capture records every mount, `handle_event` and render, the
assigns at each step and the Ecto queries between them, and writes a timeline and a digest beside
the snapshots. The report that comes out names what stands out: renders with no interaction
between them, assigns that grow every cycle, a slow event, a query run in a loop. `--profile`
picks a set of analyzers and `--analyze` names them one by one; a name it does not know is an
error, not a silence.

The same evidence is served to an agent over MCP (`Excessibility.MCP.Server`, started with
`claude mcp add excessibility -s project -- mix run --no-halt -e "Excessibility.MCP.Server.start()"`),
with the Claude Code skills in `docs/llm-debugging.md`.

## While you build

Snapshot checks run in your tests. For looking at components as you build them, the companion
package [excessibility_storybook](https://github.com/lessthanseventy/excessibility_storybook) adds
pages to [phoenix_storybook](https://github.com/phenixdigital/phoenix_storybook): a contrast matrix
for your theme, what each component sounds like to a screen reader, its focus order, and how it
holds up at 320px, 200% text and WCAG text spacing. It is a separate dev-only dependency, so
Excessibility does not pull in storybook.

## Guides

- [Library Guide](docs/library-api.md): the LiveView-aware rules, the Scanner API, the baseline
  and review workflows, configuration, axe-core options, screenshots, every mix task, CI.
- [LLM Debugging Guide](docs/llm-debugging.md): telemetry capture, the debug report and the
  digest, the analyzers, the MCP server and the skills.
- [Telemetry Analysis](docs/telemetry-analysis.md): writing an enricher or a pattern analyzer
  of your own.

## License

MIT © Andrew Moore
