# Excessibility demo

A small, runnable Phoenix app that exercises [Excessibility](../) end to end. Every
page is a deliberate example — some accessible, most not — so you can see exactly
what the tooling catches.

The app depends on Excessibility via a relative path (`{:excessibility, path: ".."}`),
so it always runs against the code in this repo.

## Run it

```bash
mix setup            # deps.get
mix phx.server       # browse http://localhost:4000
mix test             # generates snapshots + timelines
```

## What it demonstrates

The landing page groups the examples by what Excessibility does with them.

### Accessibility (static snapshots → axe-core + LiveView rules)

| Route | What it shows |
|-------|---------------|
| `/accessible` | The happy path — labelled inputs, `alt` text, real buttons, an `aria-live` status, an `aria-expanded` disclosure. A review comes back clean. |
| `/a11y/form` | Common **form** failures: missing labels, no `<select>` name, duplicate id, icon button with no name, plus the LiveView rules `debounce_without_live_region` and `hidden_form_control_without_aria`. |
| `/a11y/widgets` | Custom **widgets**: an `<a>` with no text, positive `tabindex`, a heading jump, a header-less table, plus the LiveView rules `phx_click_on_non_interactive`, `toggle_missing_aria_state`, `reveal_without_announcement`, and `click_away_without_escape`. |

Between the two messy pages they trip **all six** LiveView-specific rules that
axe-core can't see.

```bash
mix test test/demo_web/accessibility_test.exs   # write the snapshots
mix excessibility                               # axe-core + LiveView rules over them
```

> `mix excessibility` runs axe-core through Playwright. If it isn't installed yet,
> run `mix excessibility.install` first (the LiveView rules run without it).

### Review (two renders of the same commit → no findings)

| Route | What it shows |
|-------|---------------|
| `/review/orders` | An accessible page built from what differs on every render of a real app: random ids, UUIDs in DOM ids, sequenced emails, a clock, a CSRF form and link, a signed token in a URL, an upload input, a stream, live components. Its dialog fades in over 300ms and its sync indicator animates forever. Buyer names are drawn at random, so the page counts as changed and axe scans both renders. |
| `/review/messy-orders` | Deliberate violations (an unlabelled input and a clickable `<div>` per order) on elements whose ids differ on every render. They exist on both sides, so a review reports none of them as new. |

```bash
mix review.same_commit
```

That runs the tests, locks the snapshots as the baseline, runs the tests again and
reviews the second render against the first. The code is the same both times, so
the expected report is the two `/review` pages as `auto` (their names changed) and
nothing as `review` or `block`; the command fails otherwise. Every other page
differs only in per-render tokens and is not scanned at all. CI runs this on every
pull request, which makes this app the regression test for false positives in
`mix excessibility.review`.

### Performance (telemetry timeline → behavioral analyzers)

| Route | What it shows | Caught by |
|-------|---------------|-----------|
| `/perf/n-plus-one` | One query per row in a single event | `ecto_query_analysis` |
| `/perf/memory` | An assign that grows unbounded every click | `memory`, `data_growth` |
| `/perf/renders` | Events that re-assign identical state | `handle_event_noop` |
| `/perf/messages` | A burst of `handle_info` messages | `message_flooding` |

```bash
# one test at a time keeps each timeline focused
mix excessibility.debug test/demo_web/performance_test.exs:19
mix excessibility.debug test/demo_web/performance_test.exs:47 --analyze=message_flooding
```

## How the wiring works

- **`config/test.exs`** sets `:endpoint`, and `ecto_repos: [Demo.Repo]` so query
  telemetry is captured for the N+1 example (the demo emits query telemetry
  directly, so no database is needed).
- **`test/test_helper.exs`** calls `Excessibility.TelemetryCapture.attach()` when
  running under `mix excessibility.debug`.
- **`router.ex`** wires the opt-in `handle_info` hook in one line:
  `live_session :default, on_mount: [Excessibility.TelemetryCapture]`.
