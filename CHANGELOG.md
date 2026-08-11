# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Real-Postgrex privacy regression for mixed-case dollar and E-string SQL** ([#175](https://github.com/lessthanseventy/excessibility/issues/175)). The #166 final-digest guard hand-built its query metadata via `EctoQueries.build_query_record/2`, so it never crossed the real Ecto/Postgrex adapter boundary that produces that metadata in production — the suite could stay green while that boundary regressed. Adds a DB-gated test (`test/telemetry_capture_real_postgres_test.exs`) that executes the reported mixed-case dollar-quoted (`$TAG$ … $tag$ … $TAG$`) and escaped `E'…'` SQL through a real repo against a disposable PostgreSQL database, captures the genuine `[:excessibility, :test_repo, :query]` telemetry event (not a constructed record), builds the digest, and scans the complete artifact — asserting no email, comment body, or bare numeric literal leaks while the trailing SQL shape (column aliases past each folded literal) and a legitimate numeric fixture cardinality survive. The test runs only when `DATABASE_URL` is set (CI adds a disposable Postgres service; `test_helper.exs` excludes the `:database` tag otherwise, so local `mix test` with no database is unchanged). `postgrex` and `ecto_sql` are added as `only: :test` dependencies and are not part of the published package.

### Changed
- **Release flow no longer tags on every main push; orphaned `v0.19.0` tag resolved** ([#176](https://github.com/lessthanseventy/excessibility/issues/176)). [#168](https://github.com/lessthanseventy/excessibility/issues/168) hardened `version-tag.yml` to fail a main push when an existing `v$VERSION` tag did not target `HEAD`, but that also failed a corrected release commit (whose only delta may be outside the Hex package surface) and made re-tagging a version impossible. It is replaced by two workflows: `version-check.yml` (validation only — on push to main it checks README consistency and, when `v$VERSION` is already tagged, that the declared **Hex package surface** (the files `mix hex.build` ships) is unchanged; it never fails merely because `HEAD` diverges from a tag on non-package files, and never creates or moves tags) and `release.yml` (a deliberate `workflow_dispatch` path, run after the release PR merges and CI is green: it refuses to move an existing tag, runs a final `mix test` gate, then creates the tag and GitHub release). The already-public but unshipped `v0.19.0` tag (never published to Hex, no GitHub release) was resolved via **Option B**: the abandoned remote tag was deliberately deleted so the corrected line ships as `0.19.0`. `v0.18.1` and its Hex release remain immutable.

### Fixed
- **Snapshot capture no longer flakes on a destroyed ETS table.** The `:excessibility_snapshots` ETS table was created by — and therefore owned by — whichever process first called `Excessibility.TelemetryCapture.attach/0`. ETS tables die with their owner, so when that test process finished (or a later `attach/0` saw the table still owned by a previous, mid-teardown test process and skipped creating it), the table could vanish mid-run of another test, surfacing intermittently as `ArgumentError: the table identifier does not refer to an existing ETS table` and a missing `timeline.json`. A dedicated long-lived owner (`Excessibility.TelemetryCapture.SnapshotStore`) now holds the table for the whole run, decoupling its lifetime from test scheduling. The table stays `:public`, so read/write behaviour is unchanged.
- **Plan comparison preserves every distinct structural variant under one query fingerprint** ([#173](https://github.com/lessthanseventy/excessibility/issues/173)). A parameterized query can pick different plans by selectivity, so one SQL fingerprint legitimately carries several plan structures across a journey. [#167](https://github.com/lessthanseventy/excessibility/issues/167)'s `QueryPlan.aggregate/1` collapsed them to the single heaviest representative, so a secondary plan path that changed or regressed while an unchanged heavier path stayed dominant produced a **false-negative** plan comparison. New `Excessibility.QueryPlan.aggregate_variants/1` keeps the bounded **set** of distinct structural variants (the heaviest instance of each structure, sorted by fingerprint); `Excessibility.QueryEvidence.shapes/1` emits it as `plans` (capped at 8, with `variants_omitted` recording truncation) in place of the single `plan`. `Excessibility.DigestCompare` compares the variant *set* per fingerprint: a structure present on only one side is reported as `variants_added`/`variants_removed`, and a structure present on both sides still surfaces numeric root and per-node row deltas (the #167 behaviour) as a `variant_delta`. An equal-count `{heavy A, light B}` → `{same heavy A, changed light C}` journey now reports the B→C change end to end where it previously reported nothing. (`digest/v1` query shapes now carry `plans[]`/`variants_omitted` in place of `plan`; `aggregate/1` is unchanged and still returns the single heaviest representative.) Follow-up to #167.
- **Real-Postgrex privacy regression now guards timing/duration absence** ([#185](https://github.com/lessthanseventy/excessibility/issues/185)). [#175](https://github.com/lessthanseventy/excessibility/issues/175)'s acceptance criteria included "absence of generic email, literal, comment, **and duration** canaries," but the committed real-adapter test injected `%{duration: 50}` and asserted only the email/comment/numeric-literal canaries — nothing checked that the native duration measurement or a derived `duration_ms` stayed out of the value-free digest, so a future change copying event/query timing into the digest could ship while the privacy test stayed green. The test now injects a distinctive generic duration canary (`424_242_424_000_000`) and asserts both it and its `System.convert_time_unit/3`-derived millisecond value are absent from the raw artifact, plus a recursive scan of the complete decoded digest that rejects any *numeric* value under a timing-shaped key (`duration`, `timing`, `elapsed`, `latency`, or a `_ms`/`_time`/`_ns`/… suffix). The intended `capture.timing: "non_comparable"` **string** sentinel stays allowed and is now explicitly asserted. A colocated DB-free companion (`@tag database: false`, enabled by #186) proves the scan actually bites — a representative timing value copied into an event or query block is caught — so the guard cannot silently pass. Real PostgreSQL execution, the trailing-SQL-shape assertions, and the numeric fixture-cardinality survival check are unchanged. Follow-up to #175.
- **`@tag database: false` can now opt a DB-free guard back into the no-database suite** ([#186](https://github.com/lessthanseventy/excessibility/issues/186)). `test_helper.exs` excluded database tests without `DATABASE_URL` via `ExUnit.start(exclude: [:database])`, but an atom ExUnit filter matches the tag *key* regardless of value — so a pure guard colocated in the `@moduletag :database` integration module could not run even when tagged `@tag database: false`; it stayed silently excluded, and the tag value falsely suggested an override the harness did not honour. The filter is now `exclude: [database: true]`, so only tests whose tag value is exactly `database: true` are excluded while `database: false` (and untagged) tests run. A new `test/database_tag_filter_test.exs` regression asserts the value-scoped semantics (including that the old atom filter would have wrongly excluded `database: false`) and a live `@tag database: false` test proves it runs in the default no-DB suite. With `DATABASE_URL` set the real PostgreSQL integration test still runs; the default suite still makes no connection attempts. Follow-up to #175.
- **Plan comparison no longer renders a bound-omitted variant as "no change"** ([#183](https://github.com/lessthanseventy/excessibility/issues/183)). [#173](https://github.com/lessthanseventy/excessibility/issues/173) bounds each SQL fingerprint's plan-variant set at 8 (`QueryEvidence`'s `@max_plan_variants`) and records truncation as `variants_omitted`, but `Excessibility.DigestCompare.plan_delta/5` carried that count only as a field on an *otherwise-emitted* delta and returned `[]` whenever the retained variant sets and numerics matched — so when the variant the bound dropped was the one that changed, comparison reported nothing at all (no plan delta, no coverage note). That is the #173/#167 class of false negative reappearing at the truncation boundary. The bound is correct and stays; the incompleteness is now made explicit. `DigestCompare` forces a `plans` entry whenever either side omitted variants (even with empty `variants_added`/`variants_removed`/`variant_deltas`) and surfaces per-side `base_variants_omitted`/`head_variants_omitted` counts in place of the old single `variants_omitted` boolean; it also adds a `coverage.notes` entry when either side omitted anything — which additionally covers SQL fingerprints present on only one side, since `plan_diffs/3` iterates the intersection and never reaches those. The omission note is gated on plans actually being comparable (matching `plan_capture`, both `ecto_configured`), so a scope difference is never double-reported. `mix excessibility.digest.compare` renders the per-side counts and states plainly that the omitted variants were never compared, so a header-only entry cannot read as a clean result. A 9-distinct-variant journey whose lone differing structure is exactly the one the bound drops now surfaces end to end where it previously printed `## Plans\n\nnone`. Follow-up to #173.
- **`mix test` no longer requires `chromedriver` on `PATH`** ([#183](https://github.com/lessthanseventy/excessibility/issues/183)). Wallaby is a `:test`-only, optional dependency, but its OTP application auto-started under `mix test` and `Wallaby.start/2` *raises* via `Wallaby.Chrome.validate/0` when no `chromedriver` executable is found — so the pure-unit suite could not boot on a machine without a browser driver, even though every test mocks `:browser_mod` and never drives a live session. The Wallaby dep is now declared `runtime: false`: its modules stay compiled and on the code path (so the `Wallaby.Session` struct and the `Code.ensure_loaded?(Wallaby.Session)` guard in `Excessibility.Source` are unchanged), but the application — and its chromedriver validation — no longer auto-starts. Downstream consumers that opt into Wallaby are unaffected; they declare their own Wallaby dependency and start it themselves.
- **`Subprocess.run/3` cd-option test no longer fails on macOS** ([#183](https://github.com/lessthanseventy/excessibility/issues/183)). `test/mcp/subprocess_test.exs`'s "respects cd option" asserted the subprocess `pwd` output equalled `/tmp`, but macOS resolves the symlinked `/tmp` to `/private/tmp`, so the physical path `pwd` prints never matched. The test now creates a fresh temp directory and compares by filesystem identity — the `(device, inode)` pair, which is stable across symlinked path spellings — instead of a brittle string compare, so it passes identically on Linux and macOS.
- **Plan digest bounds `relations` with explicit omission metadata** ([#174](https://github.com/lessthanseventy/excessibility/issues/174)). [#167](https://github.com/lessthanseventy/excessibility/issues/167) bounded `nodes`/`node_rows` (with `nodes_omitted`) but still emitted `relations` whole, so a pathological or partition-heavy plan could grow the public `digest.json` without the visible truncation metadata #167 required. `Excessibility.QueryPlan.summarize/1` now caps the sorted unique `relations` set at the same `@max_nodes` (100) and always emits `relations_omitted` (`0` when nothing is dropped), so no structural array ships unbounded and a missing tail is never silent. The structural `fingerprint` still hashes the full untruncated tree. Follow-up to #167.

## [0.19.0] - 2026-08-10

### Added
- **Plan evidence preserves and compares child-node row work** ([#157](https://github.com/lessthanseventy/excessibility/issues/157)). `Excessibility.QueryPlan.summarize/1` now emits a bounded, deterministic, value-free `node_rows` list (one entry per plan node in depth-first order: `node`, `relation`, `depth`, `estimated_rows`, plus `actual_rows`/`loops`/`rows_touched`/`estimate_error` only under EXPLAIN ANALYZE). `rows_touched` = `actual_rows × loops`, so a large child scan looping beneath a one-row root is represented numerically rather than discarded. `Excessibility.DigestCompare` now compares plan row work **even when the structural fingerprint is unchanged** — a plan whose shape is stable but whose actual rows jump from 1 to 10,000 now produces a plan delta instead of `{"plans": []}`. Structural plan changes (`structural_change: true`, differing node tree) and numeric row deltas (root `estimated_rows_delta`/`actual_rows_delta` and per-node `node_deltas`) are reported separately.

### Changed
- **Runtime evidence hardened against assign, warning, and benchmark noise** ([#159](https://github.com/lessthanseventy/excessibility/issues/159)). Three advisory surfaces turned expected test/runtime jitter into noise:
  - **Tiny byte-only assign deltas are suppressed.** `mix excessibility.digest.compare` no longer reports a per-assign `term_bytes` change below `:digest_min_assign_delta_bytes` (default 64) when the cardinality is unchanged — two unchanged runs stop emitting a wall of `+1 byte` deltas. A cardinality change is **never** suppressed, and exact `delta_bytes` stays on any reported entry. Set the threshold to `0` for exact-byte behavior.
  - **One ANALYZE-downgrade warning per run.** `--plan-analyze` without the `:query_plan_allow_analyze` gate downgraded to `EXPLAIN` and warned once *per process*; a journey spans many LiveView processes, so the command flooded. The warn-once flag is now global to the run, so exactly one warning is emitted, and the downgrade is surfaced once in the digest's value-free `capture.warnings` (requested vs effective mode).
  - **Benchmark outliers require a meaningful effect size.** A warm sample must now clear the statistical threshold **and** a minimum absolute delta (`:benchmark_min_abs_ms`, default 1.0 ms) **and** a minimum relative delta (`:benchmark_min_rel_factor`, default 1.5×), so sub-millisecond jitter is no longer flagged. Outliers computed from too few warm samples carry `weak_evidence: true` and add a run-level "weak evidence" note. All three surfaces remain advisory and never gate CI.

### Fixed
- **Plan evidence aggregates row work across every occurrence of a query fingerprint** ([#167](https://github.com/lessthanseventy/excessibility/issues/167)). A query fingerprint can fire many times in one journey, and a *later* occurrence can do far more row work than the first — but `Excessibility.QueryEvidence.shapes/1` kept only the first occurrence's plan, so a child scan growing 10,000 → 20,000 rows under an unchanged root was discarded before comparison and `mix excessibility.digest.compare` reported `plans: []`. `Excessibility.QueryPlan.aggregate/1` now merges the plan summaries of all occurrences of a fingerprint by keeping the **maximum** comparable row work per structural node path (estimated/actual rows, loops, `rows_touched`); `max/2` is commutative so the result is independent of occurrence order, and plans with differing structures are grouped by structural fingerprint with the heaviest chosen as a deterministic representative. `Excessibility.DigestCompare` applies the same max-merge when one fingerprint's plan spans multiple events of a `{view, callback}`, so a later heavier occurrence now surfaces as a node-level delta. Every emitted structural array is bounded: `nodes` and `node_rows` are capped at 100 and the number of dropped nodes is surfaced as a value-free `nodes_omitted` count, so truncation is never silent (the `nodes` list was previously unbounded while `node_rows` capped silently). The structural fingerprint still hashes the full untruncated tree, so distinct large plans stay distinct. Follow-up to [#157](https://github.com/lessthanseventy/excessibility/issues/157).
- **Privacy: case-sensitive SQL literal scanning stops mixed-case dollar tags leaking into `digest.json`** ([#166](https://github.com/lessthanseventy/excessibility/issues/166)). `Excessibility.SQLFingerprint.normalize/1` lowercased the whole SQL string *before* its literal-aware scan, but Postgres dollar-quote tags (`$TAG$`) and E-string escapes are case-sensitive — so a lowercase `$tag$` inside an uppercase-tagged `$TAG$…$TAG$` literal became a false closing delimiter, splitting the literal and leaving its tail (e.g. an email) in the normalized shape and the emitted digest. The scanner now runs first, on the **original-case** SQL: it matches dollar tags case-sensitively, honours backslash (`\'`) and doubled-quote (`''`) escapes in `E'…'` strings so a `--` inside one no longer starts a comment that truncates the trailing shape, and folds every string/dollar/E-string literal to `?` before the result is downcased. Downstream regex literal-folding passes were removed in favour of the single scanner. Adds direct-normalizer regression tests for the reported cases plus an end-to-end digest regression (via adapter telemetry) asserting the marker value is absent from the complete emitted digest. Follow-up to [#156](https://github.com/lessthanseventy/excessibility/issues/156).
- **`mix excessibility.review --timeline` no longer crashes on analyzer-filtered timelines** ([#158](https://github.com/lessthanseventy/excessibility/issues/158)). A timeline captured with a filtered enricher set (e.g. `mix excessibility.debug --analyze=ecto_query_analysis`) omits the memory/duration fields, but review ran all default analyzers regardless — the memory analyzer read `event.total_memory` directly and raised `KeyError`, so no review was emitted. Review now inspects which enricher data a timeline actually carries and **skips analyzers whose required enricher is absent**, recording an explicit value-free warning (`memory analysis skipped: required enricher data (assign_sizes) was not captured in this timeline`) in the report's `warnings`. A per-analyzer rescue backstops any residual field gap, and the memory analyzer tolerates a missing `total_memory`. Full-enricher timelines still run the complete default set.
- **Privacy: strip SQL comments and validate fixture metadata in `digest.json`** ([#156](https://github.com/lessthanseventy/excessibility/issues/156)). `Excessibility.SQLFingerprint.normalize/1` now removes SQL line (`-- …`) and block (`/* … */`) comments before any value folding, using a literal-aware scanner so comment markers inside string/dollar-quoted literals or quoted identifiers are preserved rather than mistaken for comments. Comments no longer affect fingerprints (they never reach the normalized string), so grouping stays stable. `coverage.fixtures` is validated at the digest boundary — both the `EXCESSIBILITY_FIXTURES` env JSON and `config :excessibility, :fixtures` are reduced to string-key → non-negative-integer cardinalities; strings, floats, and nested maps/lists are dropped and their key names surfaced as a value-free `capture.warnings` entry. This closes two paths that could copy arbitrary application values into the "value-free" artifact.

### BREAKING
- **`mix excessibility.compare` renamed to `mix excessibility.snapshot.compare`** ([#154](https://github.com/lessthanseventy/excessibility/issues/154)). The snapshot baseline-diff task moves under the `snapshot` namespace to make room for the new runtime-evidence digest tasks. There is no deprecated alias — update any scripts, CI steps, or editor tasks that call `mix excessibility.compare` (including `--keep good`/`--keep bad`) to `mix excessibility.snapshot.compare`. The task's behavior is unchanged.


## [0.18.1] - 2026-08-07

### Fixed
- **`ecto_query_analysis` N+1 detection fires on the `--timeline` path** ([#151](https://github.com/lessthanseventy/excessibility/issues/151)). `detect_n_plus_one` filtered on `operation == :select` (an atom), but `mix excessibility.review --timeline` loads with `Jason.decode(keys: :atoms)`, which atomises keys and leaves values as strings — so `operation` was `"select"`, every query was dropped, and the precise, `:critical`, table-naming N+1 finding never appeared (only the raw count survived). The comparison is now string-tolerant, so the shape detector fires on both the in-process and reloaded-timeline paths.
- **Test-setup queries are no longer attributed to `mount`** ([#151](https://github.com/lessthanseventy/excessibility/issues/151)). Ecto queries accumulate in the emitting process's dictionary and only clear on flush at each captured event's `:stop`. Seed INSERTs from a test's `setup` block run before the LiveView exists — in the same process as the static mount — so they flushed onto `mount`, inflating exactly the event most likely to be flagged. Capture now resets the accumulator on the LiveView `mount` `:start`, keeping pre-mount queries out of the timeline.

### Changed
- **The excessive-query count detector uses a conservative threshold** ([#151](https://github.com/lessthanseventy/excessibility/issues/151)). Real Phoenix mounts with nested preloads routinely run more than a handful of queries, so the old absolute threshold of 5 flagged every healthy view as `:serious`. The floor is now 10 (with `:critical` reserved for >20); the precise signal is the shape-based N+1 detector, and this count remains a coarse backstop for genuinely high volume. (A per-view budget/baseline for this detector is still open in #151.)


## [0.18.0] - 2026-08-06

### Added
- **Opt-in `handle_info` capture, reviving `message_flooding`** ([#147](https://github.com/lessthanseventy/excessibility/issues/147)). Phoenix LiveView emits no `handle_info` telemetry, so there was nothing to attach to globally. `Excessibility.TelemetryCapture` now exports an `on_mount/4` hook that uses `Phoenix.LiveView.attach_hook/4` on the `:handle_info` stage to record each message as a `handle_info:<name>` timeline event. It is opt-in — wire it where you want it, e.g. one line on a router `live_session`: `live_session :default, on_mount: [Excessibility.TelemetryCapture]`. It attaches nothing unless telemetry capture is running and the socket is connected, so it is safe in all environments. Pair it with the (still opt-in) `message_flooding` analyzer.

### Fixed
- **`message_flooding` no longer crashes on a captured timeline** ([#147](https://github.com/lessthanseventy/excessibility/issues/147)). Its sliding window called `DateTime.diff` on `event.timestamp`, but a timeline read back from `timeline.json` has no `%DateTime{}` — timestamps serialize to a struct-map that does not round-trip. Timeline events now carry a JSON-safe numeric `timestamp_ms`, and the window uses it (falling back to a `%DateTime{}` when present, e.g. in-memory).
- **`mix excessibility.debug --analyze` / `--no-analyze` / `--profile` are honored** ([#147](https://github.com/lessthanseventy/excessibility/issues/147)). These flags were dropped while building the internal filter options, so analyzer selection silently always fell back to the default set — which is why enabling an opt-in analyzer (or `--analyze=all`) appeared to do nothing.


## [0.17.0] - 2026-08-06

### Added
- **Ecto query capture, so `ecto_query_analysis` can actually fire** ([#147](https://github.com/lessthanseventy/excessibility/issues/147)). The analyzer reads `ecto_queries`/`ecto_query_count`, but nothing populated them — the capture layer only attached to LiveView telemetry, so N+1 detection (the most common real LiveView performance defect) silently never ran. Capture now attaches to each configured repo's `[..., :query]` telemetry event, accumulates queries in the emitting process, and attributes them to the LiveView event that ran them. Configure the repos to watch: `config :excessibility, ecto_repos: [MyApp.Repo]`. When `ecto_query_analysis` would run but no repos are configured, capture logs that N+1 detection is off instead of reporting a green (empty) section.

### Changed
- **`message_flooding` is no longer enabled by default** ([#147](https://github.com/lessthanseventy/excessibility/issues/147)). It reads `handle_info:*` timeline events, but Phoenix LiveView emits no `handle_info` telemetry and the capture layer doesn't hook it, so the analyzer could never fire — shipping it enabled implied working coverage while staying silent. It is now opt-in until `handle_info` capture lands.
- **The performance analyzer's "very slow" ceiling is configurable, and its relative nature is documented.** It is an outlier detector (an event much slower than the rest of the run, the event dominating total time, or one over an absolute ceiling) computed from test timings — so *uniformly* slow code in the ~100 ms–1 s band isn't flagged. That's deliberate (sandbox/cold-mount timings aren't production latency), but it's now called out in the analyzer docs and README, and the absolute ceiling is tunable for teams with representative timings via `config :excessibility, slow_event_ms: 400` (default 1000).

### Fixed
- **Memory analyzer no longer reports a flat plateau as growth** ([#146](https://github.com/lessthanseventy/excessibility/issues/146)). The 0.16.0 absolute floor gated the size but not the ratio, so a run holding steady at 1.3 MB (a global outlier above the floor) was reported `[serious] Memory grew 1.0x`. A "grew Nx" finding now also requires the ratio to clear a minimum — a flat or shrinking transition isn't bloat. (The `consecutive growth` leak path already required a strict increase, so a flat plateau never qualified there.)


## [0.16.0] - 2026-08-06

### Added
- **`mix excessibility.review --format json`** (`--json` alias) ([#143](https://github.com/lessthanseventy/excessibility/issues/143)). Emits the review as a single JSON object on stdout — `excessibility_version`, `summary`, `warnings`, `behavioral`, and per-change `view`/`tier`/`region_count`/`findings` — so CI and PR bots consume a stable API instead of scraping the printed report. Every finding carries a `source` (`live_view_rules` / `axe` / `telemetry`), which makes "axe degraded, so these results are rules-only" expressible without matching prose. The human report stays the default; the stale-snapshot notice moves into the `warnings` array so stdout is only the JSON object.
- **`mix excessibility.review --fail-on-behavioral`** ([#142](https://github.com/lessthanseventy/excessibility/issues/142)). Opt in to failing the build on a serious behavioral (telemetry) finding.

### Changed
- **Behavioral findings are advisory by default** ([#142](https://github.com/lessthanseventy/excessibility/issues/142)). A serious behavioral finding (memory bloat, render thrash, etc.) no longer fails `mix excessibility.review`. Unlike accessibility findings — a true delta against the baseline — behavioral findings are absolute measurements of a single run, so they are advisory unless you opt in with `--fail-on-behavioral`. Accessibility tiers still gate the build via `--fail-on` (default `block`).

### Fixed
- **Behavioral analyzers no longer compare across different LiveViews** ([#142](https://github.com/lessthanseventy/excessibility/issues/142)). A journey test drives several LiveViews, so the timeline interleaves unrelated processes; the analyzers compared consecutive events without grouping by view, producing 5 serious findings (and exit 1) on a healthy 12-event timeline. `memory`, `data_growth`, `render_efficiency`, `state_machine`, and `event_pattern` now group events by `view_module` before any consecutive-event comparison, so a freshly-mounted 220-byte `UserLoginLive` sitting next to a loaded 109 KB render is no longer read as "507x memory growth", and an Index→Login boundary is no longer phantom "keys added/removed" or "unstable state".
- **Absolute floors alongside ratios** ([#142](https://github.com/lessthanseventy/excessibility/issues/142)). Memory findings require the larger side to clear ~256 KB regardless of ratio (109 KB is an ordinary LiveView heap); a list going `0 → 1` is treated as "appeared", not `∞x` growth. Performance slow/bottleneck findings require an absolute duration floor, so a 40 ms first mount that is "60% of total time" on a short timeline is not flagged.
- **`render_efficiency` no longer flags healthy renders as wasted** ([#142](https://github.com/lessthanseventy/excessibility/issues/142)). LiveView captures a `handle_event` and its `render` as two events, so the render's own diff is empty even though the interaction changed state. Wasted renders are now measured against the *previous render in the same view*, and the initial paint is never wasted — so a `render_click` that genuinely changed state is not reported as a wasted render.
- **Consecutive mounts are not flagged as unnecessary re-renders** ([#142](https://github.com/lessthanseventy/excessibility/issues/142)). Repeated mounts come from `LiveViewTest.live/2`'s disconnected+connected double-mount and re-navigation — a capture artifact, not render churn — so `event_pattern`'s rapid-repeat heuristics skip lifecycle events (`mount`, `handle_params`).
- **Assign traversal stops at opaque library structs** ([#142](https://github.com/lessthanseventy/excessibility/issues/142)). `Ecto.Changeset`, `DateTime`/`Date`/`Time`/`NaiveDateTime`, and `Decimal` collapse to a scalar leaf instead of being walked, so changeset internals (`.types`, `.mappings`, `.validations`) and timestamp microsecond tuples no longer surface as tracked app state in `data_growth`.
- **Memory growth messages report the actual factor** ([#142](https://github.com/lessthanseventy/excessibility/issues/142)). "Memory grew 0.5x" (which printed `delta/prev`) now reads "grew 1.5x" (`curr/prev`), so the number matches the byte sizes shown alongside it.


## [0.15.3] - 2026-08-05

### Changed
- **Content-change findings are opt-in for reviews** ([#139](https://github.com/lessthanseventy/excessibility/issues/139)). `mix excessibility.review` compares a baseline and a current snapshot that normally come from two independent `mix test` runs, where the rendered text differs wherever fixtures do (record ids, generated names) — on one real PR that produced 319 false `content_change_without_live_region` findings. The rule is only meaningful when both sides rendered the same fixture data, so `Excessibility.Review` now folds it in only with `content_diff: true` (`mix excessibility.review --content-diff`). Within-run sequence scanning (`SnapshotDiff.scan_sequence/2`, used by `mix excessibility`) and the MCP `diff_snapshots` tool (before/after around a single edit, same fixtures) keep the rule unconditionally.

### Fixed
- **Finding fingerprints no longer depend on database ids** ([#140](https://github.com/lessthanseventy/excessibility/issues/140)). Reviews identify pre-existing findings by `{rule, selector}`, and selectors are built from DOM ids — which Phoenix idiomatically derives from record ids (`id={"row-#{@row.id}"}`). Fixture ids shift between the baseline run and the current run, so a pre-existing finding could resurface under a new id (`#section-2` → `#section-7`) and be reported as a newly introduced `:block`. Digit runs in the selector are now collapsed for fingerprinting (`#section-2` and `#section-7` both compare as `#section-N`); the raw selector is unchanged in the reported finding.


## [0.15.2] - 2026-08-05

### Fixed
- **A genuinely missing stylesheet is again reported as `stylesheet failed to load`** ([#137](https://github.com/lessthanseventy/excessibility/issues/137)). The `link.sheet` gate from 0.15.1 assumed a failed sheet leaves `link.sheet` null, but under `file://` Chromium attaches a non-null empty `CSSStyleSheet` to a `<link>` whose file is missing — so the severe warning never fired and the run was understated as `stylesheet import failed`. Failures are now classified by the network signal: a failed stylesheet request matching a `link[rel~="stylesheet"]` href is that link failing (`stylesheet failed to load: … — contrast/layout findings are invalid until it exists`); any other failed stylesheet request is a nested `@import` (`stylesheet import failed: … — text metrics may differ from production`). The null-sheet list is still unioned in for sheets that downloaded but failed to parse, and the 0.15.1 fix for [#132](https://github.com/lessthanseventy/excessibility/issues/132) (loaded sheet with a failing `@import` must not warn `failed to load`) is regression-tested alongside.

## [0.15.1] - 2026-08-05

### Fixed
- **Reviews now run axe-core** ([#131](https://github.com/lessthanseventy/excessibility/issues/131)). `mix excessibility.review` (and `Excessibility.Review`) scans both sides of every changed snapshot pair through the configured scanner and folds axe violations into the finding-delta — one finding per offending node, fingerprinted `{id, target}` — so a newly introduced critical (e.g. a button losing its accessible name) is `:block` and `--fail-on block` exits non-zero. If a scan fails (e.g. Playwright isn't installed) the review degrades to the LiveView rules and says so in the report's `:warnings`. Opt out with `--no-axe` (or `axe: false` in the API).
- **False `stylesheet failed to load` when a nested `@import` fails** ([#132](https://github.com/lessthanseventy/excessibility/issues/132)). Chromium fires an `error` event on a `<link>` whose sheet loaded fine but whose nested `@import` failed, which previously warned that the stylesheet was missing and invalidated the whole run's contrast findings. The warning is now gated on `link.sheet` (null exactly when the sheet did not load or parse); failing imports are surfaced separately and accurately as `stylesheet import failed: <url> — text metrics may differ from production`.
- **Telemetry capture no longer crashes on lists of Ecto structs** ([#133](https://github.com/lessthanseventy/excessibility/issues/133)). `Filter.filter_ecto_metadata/1` converts structs (dropping `__meta__`, `NotLoaded` becomes `nil`) instead of `Enum.reduce`-ing them, so index/detail LiveViews with `[%Schema{}]` assigns capture cleanly. Independently, `write_snapshots/1` now logs a timeline failure instead of raising out of the `on_exit` hook — instrumentation can no longer fail the test it observes.
- **`mix excessibility.compare` in non-interactive shells** ([#134](https://github.com/lessthanseventy/excessibility/issues/134)). Without `--keep`, a non-TTY stdin (CI, editor task runners) previously crashed on `:eof` deep in the prompt and leaked `.good.html`/`.bad.html` temp files. The task now refuses up front with the actual guidance (`--keep good|bad`), cleans up temp files even when resolution errors, and if stdin closes mid-run it keeps the baseline (fail-safe) instead of silently accepting the new version.

### Added
- **`node_modules_path` config** ([#135](https://github.com/lessthanseventy/excessibility/issues/135)). `@axe-core/playwright` now gets the same override → bundled → ambient resolution as Playwright, so `config :excessibility, node_modules_path: "assets/node_modules"` reuses a host `node_modules` (providing both `playwright` and `@axe-core/playwright`) and removes the `deps/excessibility/assets` npm install from the workflow entirely. Caveat: the host then pins the axe-core version, and `engine.axe_version` in reports follows it — an axe minor bump can change finding sets vs earlier baselines.

## [0.15.0] - 2026-08-05

### Added
- **`mix excessibility.review` — accessibility blast-radius report** ([#117](https://github.com/lessthanseventy/excessibility/pull/117)). Diffs every current snapshot against its baseline and reports, per view, the rendered regions that changed and the accessibility findings the change *newly introduced* (a finding-delta, so pre-existing issues aren't re-flagged), with a risk tier: `:block` (new critical/serious), `:review` (new moderate/minor or content changed without `aria-live`), `:auto` (rendering changed, nothing broke). `--fail-on block|review|never` controls the exit code. Public API: `Excessibility.Review.review/1`, `review_pairs/2`, `review_pair/4`.
- **Pluggable risk judge** ([#118](https://github.com/lessthanseventy/excessibility/pull/118)). `Excessibility.Review.Judge` turns a change into a verdict (tier, blast-radius summary, structured risks). Ships a transparent `Heuristic` judge (default) and an `LLM` judge where the host app injects the model call as a `completion` function — no HTTP dependency; a missing, erroring, raising, or malformed-output model always degrades to the heuristic. `mix excessibility.review --judge`.
- **MCP `diff_snapshots` tool** ([#119](https://github.com/lessthanseventy/excessibility/pull/119)). Lets an agent diff two rendered HTML states (before/after an edit) and get changed regions, newly introduced findings, and a tier — a blast-radius check for "did I change rendered behavior I didn't intend?".
- **Behavioral findings in reviews** ([#120](https://github.com/lessthanseventy/excessibility/pull/120)). `mix excessibility.review --timeline timeline.json` runs the telemetry analyzers (N+1 queries, dead assigns, render thrash, …) and folds their findings into the review; a critical analyzer finding fails the run like a serious accessibility regression. `Excessibility.Review.Behavioral` normalizes analyzer severities onto the review scale.
- **Multiple viewports per scan** ([#122](https://github.com/lessthanseventy/excessibility/issues/122)). `Excessibility.Scanner.scan(url, viewports: [{1440, 900}, {320, 800}])` runs axe once per width in a single browser session and returns per-viewport results, so WCAG 1.4.10 Reflow failures are actually exercised. Also available as `mix excessibility --viewports 1440x900,320x800` or the `:viewports` config key; screenshots are suffixed per viewport (`name.1440x900.png`). The single `:viewport` option keeps the flat report shape.
- **`:reveal_without_announcement`** ([#123](https://github.com/lessthanseventy/excessibility/issues/123)) — new LiveView rule flagging an initially hidden element (a `hidden` class/attribute or inline `display:none`) that is revealed from the server via a serialized `JS.show`/`JS.toggle` command — either its own `data-*` attribute (the `push_event("js-exec")` idiom) or another element's `phx-*` op whose `to` targets it — while exposing no `role="alert"`/`"status"`/`"log"`, `aria-live`, or live-region ancestor. axe-core cannot catch this because the element is hidden at rest. Severity `:serious`. Dialog targets (`role="dialog"`/`aria-modal`) are skipped.
- **Reuse an existing Playwright installation** ([#124](https://github.com/lessthanseventy/excessibility/issues/124)) via `config :excessibility, playwright_path: "..."`. Resolution order: override → bundled copy → ambient Node resolution. The bundled `playwright` is now pinned (`~1.58.2`) and `assets/package-lock.json` ships in the hex package, so a fresh install resolves the version the browsers were downloaded for. Chromium launch failures now include the exact directory-qualified `npx playwright install chromium` command.
- Scan reports gained a `:warnings` list ([#121](https://github.com/lessthanseventy/excessibility/issues/121)), surfaced by `mix excessibility` (even for passing files) and the MCP `a11y_check` tool — e.g. a linked stylesheet that failed to load, which invalidates contrast/layout findings.
- **Browser-assisted clipping detection** (follow-up to [#122](https://github.com/lessthanseventy/excessibility/issues/122)). `check_clipping: true` (or `mix excessibility --check-clipping`) measures interactive elements — `a`, `button`, `input`, `select`, `textarea`, `[phx-click]`, `[role="button"]` — whose visible width falls below `:clipping_ratio` (default `0.9`), and reports page-level horizontal overflow, per viewport. axe has no rule for a control that is technically in the DOM but only 6% visible; this is the actual user-facing WCAG 1.4.10 failure.

### Fixed
- **`html_snapshot/2` no longer kills LiveView tests** ([#125](https://github.com/lessthanseventy/excessibility/issues/125)). Capture-metadata assigns are now read from the LiveView channel process via `:sys.get_state/2` instead of sending `:get_state` to the test client proxy, which has no matching `handle_call/3` clause and crashed — taking the linked test down with it. Any failure degrades to empty metadata.
- **Screenshot failures are non-fatal and legible** ([#126](https://github.com/lessthanseventy/excessibility/issues/126)). A failed screenshot logs the actual `inspect/1`-ed scanner reason instead of raising `Protocol.UndefinedError` (String.Chars for tuples) and failing the test; the HTML snapshot is kept.
- **axe no longer scans `file://` snapshots before CSS applies** ([#121](https://github.com/lessthanseventy/excessibility/issues/121)). Navigation defaults to `load` and the runner additionally waits until every linked stylesheet has loaded or errored (plus `document.fonts.ready`) before analyzing, so results no longer depend on a race between stylesheet loading and axe injection.
- **Counted finding-delta** ([#130](https://github.com/lessthanseventy/excessibility/pull/130)). The review's `{rule, selector}` fingerprint swallowed *all* current occurrences when the baseline had one, so a second identical violation introduced next to a pre-existing one reported nothing. Baseline occurrences are now consumed per fingerprint.
- `mix excessibility.review` warns when the current snapshots predate the baseline instead of silently describing the previous run ([#130](https://github.com/lessthanseventy/excessibility/pull/130)).
- `--timeline` failures (missing file, invalid JSON) raise a friendly Mix error with the regeneration command instead of a raw `File.Error`/`Jason.DecodeError` ([#130](https://github.com/lessthanseventy/excessibility/pull/130)).

### Changed
- Dependency requirements are now bounded (`~>` instead of open-ended `>=`) for `floki`, `igniter`, `phoenix`, and `phoenix_live_view`, so a future breaking major is not silently accepted into consumer apps.
- **A judge can no longer fully green-light a deterministic `:block`** ([#129](https://github.com/lessthanseventy/excessibility/pull/129)). When the heuristic tier is `:block` (new critical/serious findings from the rules engine) and the judge says `:auto`, `Judge.verdict/2` floors the verdict to `:review` and records the judge's raw tier in `:judge_tier` (printed by `mix excessibility.review`). Rendered page content feeds LLM prompts, so "nobody looks at this" is not a downgrade a model may make alone; judges may still raise tiers without restriction.
- **Run-level behavioral findings stay at the report level** ([#129](https://github.com/lessthanseventy/excessibility/pull/129)). `--timeline` findings are no longer appended to every changed view (one unrelated N+1 no longer marked every view `:block` and double-counted the summary). They still fail the run via the exit gate and reach the LLM judge as prompt context. The judging orchestration is now public as `Excessibility.Review.judge_changes/2`.

## [0.14.0] - 2026-06-24

### Added
- **Cross-snapshot diffing — `Excessibility.SnapshotDiff`** ([#104](https://github.com/lessthanseventy/excessibility/issues/104)). Compares consecutive snapshots of the same test to catch content that changed without an `aria-live` region — a WCAG 2.1 SC 4.1.3 (Status Messages) failure that no single-snapshot tool, axe-core included, can detect. Public API: `diff/3` (a content-agnostic semantic DOM diff that localizes each change to the deepest stable container), `live_region_findings/3`, `scan_sequence/2`, and `scan_files/2`. Wired into `mix excessibility`; gated by `:cross_snapshot_enabled?` (default `true`).
- Default snapshots now embed `Test:`/`Sequence:` capture metadata so cross-snapshot diffing can pair them, **without changing the `Module_line.html` filename scheme** (no baseline churn). Adds `:auto`/`:default` capture modes and `Excessibility.Capture.init_default_context/1`.

### Fixed
- **`:toggle_missing_aria_state`** ([#110](https://github.com/lessthanseventy/excessibility/issues/110)) no longer fires on dismiss patterns: hide-only actions, and toggles whose target is the element's own ancestor container (e.g. a menu item that dismisses its own menu). `aria-expanded` would be wrong on both.
- **`:phx_click_on_non_interactive`** ([#110](https://github.com/lessthanseventy/excessibility/issues/110)) ignores `phx-click-away` (dismissal, not activation), removing false positives on the standard dialog `focus_wrap` pattern. Elements with `phx-click` are unchanged.
- **`:click_away_without_escape`** ([#110](https://github.com/lessthanseventy/excessibility/issues/110)) detects a miscased `phx-key="escape"` (rather than the literal `"Escape"` that matches `KeyboardEvent.key`, which silently never fires) and explains it; the generic message also notes the required capitalization.
- Corrected the `t:Excessibility.LiveViewRules.Rule.finding/0` type cross-reference so `mix docs` builds without warnings.

## [0.13.0] - 2026-04-10

### Added
- **`Excessibility.Scanner` — public runtime scanning API** ([#107](https://github.com/lessthanseventy/excessibility/issues/107)). Call `Excessibility.Scanner.scan(url, opts)` from LiveViews, Oban jobs, CLI wrappers, or any application code to get a structured axe-core report. Returns `{:ok, report}` with atom-keyed fields (`:violations`, `:final_url`, `:duration_ms`, `:engine`, `:timestamp`, `:passes_count`, `:inapplicable_count`) or `{:error, reason}` with typed tuples (`:timeout`, `{:http_error, status}`, `{:navigation_failed, msg}`, `{:playwright_error, msg}`, `{:invalid_url, reason}`).
- Scanner options: `:timeout`, `:wait_for`, `:wait_until`, `:viewport`, `:tags`, `:user_agent`, `:screenshot`, `:disable_rules`, `:fallback`.
- Richer `axe-runner.js` output: `final_url` (after redirects), `duration_ms`, `engine.axe_version`, `engine.chromium_version`, `passes_count`, `inapplicable_count`.
- `mix excessibility.check` gains `--wait-until`, `--tags`, `--timeout`, `--viewport`, `--user-agent` flags.
- **`Excessibility.LiveViewRules` — LiveView-aware accessibility rules** that complement axe-core on Phoenix-specific patterns. Rules auto-discovered from `lib/excessibility/live_view_rules/rules/`; custom rules registered via `config :excessibility, custom_live_view_rules: [...]`. `mix excessibility` now runs both axe-core AND these rules on each snapshot and fails if either finds issues. Rules are no-ops on HTML without `phx-*` attributes, so the feature is safe on non-Phoenix snapshots.
- Config knobs: `:lv_rules_enabled?` (default `true`) and `:lv_rules_disabled` (list of rule ids to skip).
- **Built-in LiveView rules:**
  - **`:phx_click_on_non_interactive`** ([#101](https://github.com/lessthanseventy/excessibility/issues/101)) — flags `phx-click` / `phx-click-away` on elements that are not natively keyboard-accessible (anything other than `<a>`/`<button>`/`<input>`/`<select>`/`<textarea>`/`<summary>`/`<details>`, or elements with `tabindex` or an interactive `role`).
  - **`:toggle_missing_aria_state`** ([#102](https://github.com/lessthanseventy/excessibility/issues/102)) — flags elements whose `phx-click` serializes `JS.toggle/show/hide` but have no `aria-expanded`. Parses the serialized JSON to detect toggle operations and target ids.
  - **`:click_away_without_escape`** ([#103](https://github.com/lessthanseventy/excessibility/issues/103)) — flags `phx-click-away` without a matching `phx-window-keydown`/`phx-keydown` + `phx-key="Escape"` (or `role="dialog"`), so keyboard users can actually dismiss the overlay.
  - **`:debounce_without_live_region`** ([#105](https://github.com/lessthanseventy/excessibility/issues/105)) — flags `<input phx-debounce>` when the snapshot has no `aria-live`, `role="status"`, `role="alert"`, or `role="log"` region anywhere. Conservative: only fires when the whole snapshot lacks any live region.
  - **`:hidden_form_control_without_aria`** ([#106](https://github.com/lessthanseventy/excessibility/issues/106)) — flags `<input type="checkbox|radio">` hidden via `hidden` or `sr-only` when the wrapping `<label>` does not expose state via `aria-checked`, `aria-pressed`, `role="checkbox"`, or `role="radio"`.
- `Excessibility.LiveViewRules` registers discovered rule files as `@external_resource` so edits to existing rules trigger recompilation of the scanner module.

### Changed
- **`Excessibility.AxeRunner` removed and folded into `Excessibility.Scanner`.** The old module was an internal helper; all callers (`mix excessibility`, `mix excessibility.check`, the `a11y_check` MCP tool, snapshot screenshotting) now go through `Scanner.scan/2`. No end-user behavior change for existing Mix task users.
- Violation shape returned from `Scanner.scan/2` is now atom-keyed with normalized `:impact` atoms (`:critical | :serious | :moderate | :minor`), not the raw string-keyed axe-core output.

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
