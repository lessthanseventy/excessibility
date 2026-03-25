# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.12.0] - 2026-03-25

### Breaking Changes
- **Pa11y + ChromicPDF replaced with Playwright + axe-core.** Accessibility checks now use axe-core via Playwright instead of Pa11y. ChromicPDF removed; screenshots now via Playwright.
- **MCP surface simplified.** Removed 8 tools, 9 prompts, 2 resources. Remaining tools: `a11y_check`, `debug`, `get_snapshots`, `get_timeline`, `generate_test`, `check_work`.
- **`.claude_docs` approach replaced with `CLAUDE.md`.** Installer now appends an Excessibility section directly to `CLAUDE.md`. The `mix excessibility.setup_claude_docs` task has been removed.

### Added
- `AxeRunner` Elixir wrapper for axe-core with Playwright
- `mix excessibility.check` for checking arbitrary URLs
- `mix excessibility.snapshots` for snapshot management
- Automatic curl fallback when Playwright fails on remote URLs, with browser-like headers to bypass WAFs
- **MCP elicitation support** — tools can request structured input from the user mid-execution via forms
- **`check_work` composite MCP tool** — runs tests + a11y check + optional perf analysis in one call, with threshold-based elicitation for triage
- **Auto-check workflow** — installer adds CLAUDE.md instructions so Claude automatically runs `check_work` after modifying code
- MCP server negotiates elicitation capability with clients and caches callback in state
- Threshold-based elicitation in `a11y_check` — only interrupts for critical/serious violations; minor issues returned silently
- Playwright and Node.js setup in CI workflow

### Fixed
- IO.Stream crash in `build_markdown_report` ([#84](https://github.com/lessthanseventy/excessibility/issues/84))
- LiveView `get_assigns` crash on unsupported `:get_state` calls ([#83](https://github.com/lessthanseventy/excessibility/issues/83))
- MCP timeline tools crash on large files ([#80](https://github.com/lessthanseventy/excessibility/issues/80))
- Added `BitString` implementation for `Excessibility.Source` protocol ([#85](https://github.com/lessthanseventy/excessibility/issues/85))
- Broken doc links in README
- `node_modules` excluded from hex package
- Credo `--strict` compliance for Elixir 1.19

### Changed
- Installer creates/appends `CLAUDE.md` instead of `.claude_docs/excessibility.md`
- README updated with auto-check workflow, `check_work` tool docs, and optional hooks guidance

## [0.10.2] - 2026-02-03

### Fixed
- Make `bin/mcp-server` a generic wrapper script that works from any Phoenix project directory
- Installer now generates correct relative path (`deps/excessibility/bin/mcp-server`) in `.mcp.json`

## [0.10.1] - 2026-02-03

### Fixed
- Include `bin/` directory in Hex package so `bin/mcp-server` is available when installed as a dependency

## [0.10.0] - 2026-02-01

### Fixed
- Fixed e11y_debug MCP tool hanging by reducing response size (24KB → ~300 bytes)
- Output now written to temp file instead of included in response
- Added recursive process tree killing on timeout to prevent zombie processes

### Added
- Debug logging for MCP server via `MCP_LOG_FILE` environment variable
- Complete MCP tools documentation in README (11 tools with speed indicators)
- Better workflow guidance in generated claude_docs

### Changed
- e11y_debug now returns `output_file` path and `result_summary` instead of full output
- Improved tool descriptions to clarify workflow (generate_test → e11y_debug)

## [0.8.3] - 2026-01-25

### Fixed
- Fixed function filtering to recursively process structs ([#48](https://github.com/lessthanseventy/excessibility/issues/48))
  - `Filter.filter_functions/1` now descends into structs and converts them to maps
  - Functions nested inside structs (e.g., `Phoenix.HTML.Form` → `Ecto.Changeset` → function) are now properly filtered
  - Prevents `Protocol.UndefinedError` when generating `timeline.json` with LiveViews that have forms or changesets with function references

## [0.8.1] - 2026-01-25

### Fixed
- Fixed JSON encoding crash when timeline contains Ecto structs ([#44](https://github.com/lessthanseventy/excessibility/issues/44))
  - `Formatter.prepare_for_json/1` now converts structs to maps before encoding
  - Removes `__meta__` fields from Ecto structs during conversion
  - Prevents `Protocol.UndefinedError` when generating `timeline.json` with LiveViews that have database records in assigns

## [0.8.0] - 2026-01-25

### Added
- Timeline analysis and debugging features
  - Automatic `timeline.json` generation for test runs
  - Markdown formatter for human-readable timeline reports
  - JSON formatter for machine-readable timeline data
  - Diff computation between telemetry snapshots
  - Key state extraction with configurable highlighting
  - CLI flags for timeline filtering control (`--full`, `--highlight`)

### Changed
- Require Elixir ~> 1.14 for Ecto dependency compatibility
- Updated CI to test on Elixir 1.14+ (removed 1.13 support)
- Streamlined CI matrix to one OTP version per Elixir version

### Improved
- Enhanced signal-to-noise ratio in telemetry snapshots
  - Configurable `filter_assigns` pipeline
  - Automatic filtering of Ecto metadata (`__meta__`, `NotLoaded` associations)
  - Automatic filtering of Phoenix internals (`flash`, `__changed__`, `__temp__`)
  - Filtering of private assigns (keys starting with `_`)

### Documentation
- Added implementation plan for telemetry signal-to-noise improvements
- Added timeline analysis usage documentation

## [0.7.0] - Earlier

See git history for changes in 0.7.0 and earlier versions.

[0.8.3]: https://github.com/lessthanseventy/excessibility/compare/v0.8.1...v0.8.3
[0.8.1]: https://github.com/lessthanseventy/excessibility/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/lessthanseventy/excessibility/compare/v0.7.0...v0.8.0
