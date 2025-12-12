# Repository Guidelines

## Project Structure & Module Organization
Elixir modules live in `lib/`, grouped by capability (`excessibility/html`, `excessibility/system`, etc.) and exposed through the `Excessibility.*` namespace. Assets needed for Pa11y and browser automation sit under `assets/`, including the vendored npm workspace. ExUnit tests live in `test/`, with HTML snapshots stored in `test/excessibility/html_snapshots/` and approved baselines in `test/excessibility/baseline/`. Keep helper modules close to the code they exercise to simplify HexDocs generation and release reviews.

## Build, Test, and Development Commands
- `mix deps.get && mix compile` – fetch deps and verify the library still builds.
- `mix igniter.install excessibility` – apply the recommended `test/test_helper.exs` config and install Pa11y’s npm dependency inside `assets/`.
- `mix test` – run the suite; `mix test test/source_test.exs` targets a file while iterating.
- `mix excessibility` and `mix excessibility.approve` – run Pa11y against snapshots, then promote `.bad` diffs into `baseline/`.
- `mix format && MIX_ENV=test mix credo --strict` – enforce Styler-backed formatting and linting before committing.
- `mix docs` – regenerate HexDocs prior to publishing.

## Coding Style & Naming Conventions
Favor idiomatic Elixir: two-space indentation, snake_case functions, PascalCase modules (e.g., `Excessibility.SystemMock`). Keep module files focused—public API modules wrap lower-level helpers. Run `mix format` to enforce `.formatter.exs` rules (Styler plugin) and keep imports/aliases sorted. Snapshot filenames should read like `MyModule/my_test/step.good.html` so reviewers can trace origins quickly.

## Testing Guidelines
Tests use ExUnit plus Mox; set expectations in `test/test_helper.exs` and call `html_snapshot/4` (or related helpers) inside Conn, LiveView, or Wallaby cases. When snapshots change, inspect the `.good/.bad` pair, approve intentional diffs via `mix excessibility.approve`, and rerun `mix test` to ensure baselines match. Include regression tests whenever you add options to `Excessibility.Snapshot` or new mix tasks so Pa11y behavior stays predictable.

## Commit & Pull Request Guidelines
Write imperative commit subjects (`add snapshot pruning flag`, `document igniter flow`) and keep scope narrow so changelog entries stay meaningful. PRs should describe the why, mention Pa11y or snapshot updates, and link to any docs that need review. Confirm `mix test`, `mix excessibility`, and `mix format --check-formatted` locally before requesting review, and include terminal output or screenshots when touching the snapshot pipeline.
