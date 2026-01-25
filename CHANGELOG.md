# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
