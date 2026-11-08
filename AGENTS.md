# Repository Guidelines

## Project Structure & Module Organization
Elixir modules live in `lib/`, grouped by capability (`excessibility/html`, `excessibility/system`, etc.) and exposed through the `Excessibility.*` namespace. Assets needed for axe-core and Playwright sit under `assets/`, including the vendored npm workspace. ExUnit tests live in `test/`, with HTML snapshots stored in `test/excessibility/html_snapshots/` and approved baselines in `test/excessibility/baseline/`. Keep helper modules close to the code they exercise to simplify HexDocs generation and release reviews.

## Build, Test, and Development Commands
- `mix deps.get && mix compile` – fetch deps and verify the library still builds.
- `mix igniter.install excessibility` – apply the recommended `config/test.exs` config and install Playwright + axe-core via npm inside `assets/`.
- `mix test` – run the suite; `mix test test/source_test.exs` targets a file while iterating.
- `mix excessibility`, `mix excessibility.baseline` and `mix excessibility.snapshot.compare` – run axe-core against snapshots, lock a baseline, then resolve `.good`/`.bad` diffs (`--keep good|bad`).
- `mix format && MIX_ENV=test mix credo --strict` – enforce Quokka-backed formatting and linting before committing (Quokka takes its rules from `.credo.exs`; `mix format --dot-formatter .formatter.agent.exs FILE` formats one file without moving directives or lifting aliases).
- `mix docs` – regenerate HexDocs prior to publishing.

## Coding Style & Naming Conventions
Favor idiomatic Elixir: two-space indentation, snake_case functions, PascalCase modules (e.g., `Excessibility.SystemMock`). Keep module files focused—public API modules wrap lower-level helpers. Run `mix format` to enforce `.formatter.exs` rules (Quokka plugin) and keep imports/aliases sorted. Snapshot filenames should read like `MyModule/my_test/step.good.html` so reviewers can trace origins quickly.

## Testing Guidelines
Tests use ExUnit plus Mox; set expectations in `test/test_helper.exs` and call `html_snapshot/4` (or related helpers) inside Conn, LiveView, or Wallaby cases. When snapshots change, inspect the `.good/.bad` pair, resolve intentional diffs via `mix excessibility.snapshot.compare`, and rerun `mix test` to ensure baselines match. Include regression tests whenever you add options to `Excessibility.Snapshot` or new mix tasks so scanner behavior stays predictable. Tests that launch Playwright carry `@moduletag browser: true` (excluded when `assets/node_modules/playwright` is missing); tests that need Postgres carry `database: true` (excluded without `DATABASE_URL`).

## Commit & Pull Request Guidelines
Write imperative commit subjects (`add snapshot pruning flag`, `document igniter flow`) and keep scope narrow so changelog entries stay meaningful. PRs should describe the why, mention scanner or snapshot updates, and link to any docs that need review. A CHANGELOG entry is a few lines: what changed and what a user has to do about it. Reasoning, investigation and test narratives belong in the PR description, not the changelog. Confirm `mix test`, `mix excessibility`, and `mix format --check-formatted` locally before requesting review, and include terminal output or screenshots when touching the snapshot pipeline.

## Git: linear history

Rebase and fast-forward — never a merge commit. Bring a branch up to date by rebasing it onto the
default branch, not by merging that in. A change bigger than one review is a stack of small PRs, each
on the last (`gh stack` where the repo is on GitHub). Rewriting history that is already pushed or
shared is the human's call — ask first.
