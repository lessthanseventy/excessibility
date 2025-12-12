# Repository Guidelines

## Project Structure & Module Organization
Elixir sources live in `lib/`, organized by domain (`excessibility/html`, `excessibility/system`, etc.), and should mirror the public API exposed via `Excessibility.*` modules. Shared compile-time config belongs in `mix.exs`, while CLI scaffolding or JS helpers stay under `assets/`. Tests sit in `test/`, with helpers in `test/support/`. Snapshot artifacts are nested under `test/excessibility/html_snapshots/` and `test/excessibility/baseline/`; keep each test module’s files in its own folder so reviewers can diff quickly. Documentation content is generated from module docs plus `README.md`.

## Build, Test, and Development Commands
- `mix deps.get && mix compile` – install deps and build the library.
- `mix excessibility.install` – install Pa11y into `assets/node_modules/` so `mix excessibility` can run offline.
- `mix test` – run the ExUnit suite; use `mix test path/to/file_test.exs` for targeted loops.
- `mix excessibility` / `mix excessibility.approve` – run Pa11y on snapshots and promote `.good/.bad` diffs back into `baseline/`.
- `MIX_ENV=test mix credo --strict` – lint and catch common pitfalls; resolves most CI style failures.
- `mix format` – run the Styler-backed formatter before committing; `mix docs` regenerates HexDocs when touching public APIs.

## Configuration & Tooling
Add required config in `config/test.exs` or `test/test_helper.exs`:

```elixir
config :excessibility,
  :endpoint, Excessibility.TestEndpoint,
  :browser_mod, Wallaby.Browser,
  :live_view_mod, Excessibility.LiveView,
  :system_mod, Excessibility.System,
  :excessibility_output_path, "test/excessibility"
```

Start `{ChromicPDF, name: ChromicPDF}` in tests or rely on `Excessibility.Snapshot` auto-start before generating screenshots; keep `assets/node_modules/` ignored via `.gitignore`.

## Coding Style & Naming Conventions
Follow idiomatic Elixir with two-space indentation, snake_case function names, and PascalCase modules (e.g., `Excessibility.SystemMock`). Keep functions pure where possible and push side effects into dedicated modules under `Excessibility.System`. Always run `mix format` to apply `.formatter.exs` with the Styler plugin, and fix lint warnings flagged by Credo. Snapshot files should use the `{module}/{test}/name.good.html` pattern so automated diffs remain deterministic.

## Testing Guidelines
Tests use ExUnit plus Mox stubs configured in `test/test_helper.exs`. Add unit coverage near the module under test (e.g., `lib/excessibility/source` -> `test/source_test.exs`) and keep integration flows in `test/integration_test.exs`. When snapshots change, inspect both `.good.html` and `.bad.html`, approve intentional changes with `mix excessibility.approve`, and rerun `mix test` to ensure baselines align. Prefer descriptive `test "describes behavior"` names and include assertions around Pa11y failure thresholds or ChromicPDF screenshot flows when touching those code paths.

## Commit & Pull Request Guidelines
Recent history favors concise, imperative commits such as `add max_failures ...` or `move capture_html ...`; emulate that style and keep unrelated changes separate. Each PR should summarize the change, link to any HexDocs or issue references, note snapshot/baseline updates, and attach screenshots or terminal output for accessibility diffs when relevant. Ensure CI-critical commands (`mix test`, `mix credo --strict`, `mix format --check-formatted`) pass locally before opening the PR, and mention any follow-up steps or configuration toggles reviewers must apply.
