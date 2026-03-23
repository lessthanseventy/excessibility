# Axe-Core Migration Design

Replace Pa11y + ChromicPDF with Playwright + axe-core. Simplify MCP surface. Add snapshot management task.

## Motivation

- Pa11y wraps HTML CodeSniffer; axe-core is the industry standard with richer output (impact levels, help URLs, DOM node references)
- ChromicPDF is redundant if Playwright is present (Playwright does screenshots too)
- Playwright supports live URLs natively, enabling future phx_storybook integration
- MCP tool surface (11 tools, 4 resources, 9 prompts) is bloated — most tools duplicate knowledge the AI already has or overlap with each other

## Dependency Changes

**Remove:**
- `pa11y` ^9.0.0 (npm)
- `ChromicPDF` (hex)

**Add:**
- `@axe-core/playwright` ^4.0.0 (npm — pulls in Playwright as peer dep)

**assets/package.json:**
```json
{
  "dependencies": {
    "@axe-core/playwright": "^4.0.0"
  }
}
```

## Core Engine: axe-runner.js

A small (~30 line) Node script at `assets/axe-runner.js` replaces both Pa11y and ChromicPDF:

1. Takes a URL (file:// or http://) as first argument
2. Launches Playwright Chromium
3. Navigates to URL (with optional `--wait-for <selector>`)
4. Runs axe-core via `@axe-core/playwright`
5. Prints JSON results to stdout
6. Optional `--screenshot <path>` flag captures a PNG

Called from Elixir:
```elixir
System.cmd("node", ["assets/axe-runner.js", url, "--screenshot", png_path])
```

An Elixir module `Excessibility.AxeRunner` wraps this call, parses JSON output, returns structured results.

**axe-core result format:**
```json
{
  "violations": [
    {
      "id": "image-alt",
      "impact": "critical",
      "description": "Images must have alternate text",
      "helpUrl": "https://dequeuniversity.com/rules/axe/4.x/image-alt",
      "nodes": [{"html": "<img src=\"...\">", "target": ["img"]}]
    }
  ],
  "passes": [...],
  "incomplete": [...]
}
```

**Live URL support** comes free — Playwright navigates to http:// URLs the same as file:// URLs. This enables future phx_storybook integration without additional work.

## Mix Tasks

### Modified

**`mix excessibility`** — same interface, calls axe-runner.js instead of Pa11y. Output format updated to show axe-core's impact levels and help URLs.

**`mix excessibility.debug`** — unchanged (timeline/telemetry, orthogonal to a11y engine).

**`mix excessibility.install`** — installs `@axe-core/playwright` instead of Pa11y, runs `npx playwright install chromium`. Drops `pa11y.json`, adds axe config if needed (e.g., ignoring phx-submit false positive).

### New

**`mix excessibility.snapshots`** — manage snapshot files:
- `mix excessibility.snapshots` — list all snapshots with file sizes
- `mix excessibility.snapshots --clean` — delete all snapshots (with confirmation prompt)
- `mix excessibility.snapshots --open NAME` — open snapshot in default browser

### Unchanged

**`mix excessibility.approve`** — diff management is orthogonal to engine swap.

## MCP Tools (11 → 3)

Each tool is a thin wrapper that calls the corresponding mix task via Subprocess and returns structured JSON.

| Tool | Wraps | Input | Returns |
|---|---|---|---|
| `a11y_check` | `mix excessibility` | `url` (live URL) or `test_args` (snapshot flow) or nothing (check existing) | axe-core violations JSON |
| `debug` | `mix excessibility.debug` | `test_args`, analyzer options | Timeline + analysis |
| `get_snapshots` | `mix excessibility.snapshots` | none | Snapshot file list with sizes |

**Removed tools:** `check_route`, `e11y_check`, `list_violations`, `suggest_fixes`, `explain_issue`, `get_timeline`, `analyze_timeline`, `list_analyzers`

**`a11y_check`** absorbs `check_route` (pass a URL) and `e11y_check` (pass test_args or nothing).

**`debug`** absorbs `e11y_debug`, `get_timeline`, `analyze_timeline`, `list_analyzers`.

## MCP Resources (4 → 2)

**Keep:**
- `snapshot` — read snapshot file contents
- `config` — read excessibility configuration

**Remove:**
- `timeline` — debug tool returns this data
- `analyzer` — debug tool returns this data

## MCP Prompts (9 → 0)

Remove all prompts. They duplicate knowledge the AI already has (WCAG rules, Phoenix patterns, LiveView debugging) and reference Pa11y-specific patterns that would need rewriting.

## What Doesn't Change

- Snapshot capture: `html_snapshot/2` macro, `Excessibility.Source` protocol (including new BitString impl), `Excessibility.HTML` wrapping
- Timeline/telemetry/debug infrastructure
- Diff/approval flow (`mix excessibility.approve`)
- Mox-based test patterns (SystemBehaviour, BrowserBehaviour)
- MCP server protocol, registry, subprocess management

## Testing Strategy

- Tests mocking Pa11y CLI calls → mock axe-runner.js calls instead
- ChromicPDF screenshot tests → verify axe-runner.js `--screenshot` flag
- MCP tool tests — 3 tools instead of 11
- New tests for `mix excessibility.snapshots` task
- Integration test: axe-runner.js loads a local HTML file and returns valid axe-core JSON
