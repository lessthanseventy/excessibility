# Runtime Evidence Digest — Design

**Issue:** #154 — Feature: first-class privacy-safe runtime evidence artifacts
**Date:** 2026-08-10
**Status:** Approved design, pre-implementation

## Goal

Add first-class, privacy-safe **runtime evidence artifacts** for Phoenix LiveView
debugging and code-aware review. The product is not a universal performance verdict; it
is a trustworthy, compact record of what a LiveView actually did — query shapes, plan
shapes, assign growth, callback sequence and coverage — that another tool or reviewer can
interpret alongside source code.

Boundary:

- **raw timeline** (`timeline.json`) — full local diagnosis, unchanged;
- **value-free digest** (`digest.json`) — safe-by-construction CI/artifact/model input;
- **deterministic comparison** (`mix excessibility.compare`) — structural deltas, no
  autonomous merge verdict;
- attribution and review policy left to the consumer.

## Scope

Full scope on one branch, built in layers:

1. SQL normalization + fingerprint (foundational).
2. Value-free digest schema `excessibility.digest/v1`, emitted during capture.
3. Fingerprint-based N+1 grouping (shared evidence helper).
4. Assign-shape/growth evidence + coverage/status contract.
5. Opt-in `EXPLAIN` query-plan evidence (safety-gated).
6. `mix excessibility.compare` structural deltas.
7. Benchmark mode (cold/warm, robust stats).
8. Callback-attribution regression tests.

## Grounding (current code)

- No digest / compare / SQL-fingerprint code exists. Only fingerprint precedent is a11y
  findings (`lib/excessibility/review.ex:234`).
- Query records are `%{source, operation, duration_ms, query, repo}` with **raw SQL** and
  no normalization (`lib/telemetry_capture/enrichers/ecto_queries.ex:94`,
  `extract_operation/1` is the only SQL parsing).
- N+1 detection groups by `source` (table name), not fingerprint
  (`lib/telemetry_capture/analyzers/ecto_query_analysis.ex:80`).
- Redaction is two-layer (`extract_clean_assigns/1` at capture, `Filter` at build) but
  redacts structure/noise, not PII values.
- Timeline is built + written in `write_snapshots/1` (`lib/telemetry_capture.ex:330`) via
  `Timeline.build_timeline/3` + `Formatter.format_json/1`.
- Reloaded `timeline.json` has **string** values where live capture has atoms (issue
  #151) — avoided here by building the digest **in-memory during capture**.
- Attribution is temporal: process-dict flush on each `:stop`. `mount.start` flushes so
  `setup` seeds don't attach to `mount` (#151).

## Architecture

### 1. `Excessibility.SQLFingerprint` (new)

Pure module, zero deps. Postgres-aware regex normalizer:

- downcase keywords; `$1,$2 → $?`; fold `IN (...)` arity → `IN (?)`; inline
  numeric/quoted literals → `?`; collapse whitespace.
- `normalize(sql) → normalized_string` (value-free).
- `fingerprint(sql) → "sha256:<16 hex>"` computed from the normalized string.
- Pluggable behaviour so a parser backend could slot in later.
- **Property test:** no digit-run and no quoted literal survives normalization (this is
  load-bearing — the fingerprint is derived from it, so N+1 grouping depends on it).

Rationale for regex over a SQL parser: Ecto emits deterministic, parameterized SQL, so a
native parser NIF's formatting-immunity buys little and adds build fragility.

**Dialect:** Postgres-only *implementation*, but shaped behind a seam so a MySQL/SQLite
dialect is a drop-in later — not a refactor. A thin `Excessibility.Dialect` behaviour
isolates the genuinely dialect-specific bits; everything generic stays shared. Only
`Excessibility.Dialect.Postgres` ships now; `Excessibility.Dialect.resolve/0` reads
`config :excessibility, sql_dialect: :postgres` (default) and returns the module. Adding a
dialect = new module implementing the behaviour + one config line, no core changes.

Behaviour callbacks (the only places dialect actually differs):

- `normalize_extras/1` — dialect-specific normalization on top of the shared generic
  regex (params, whitespace, IN-arity, quoted/numeric literals are generic and stay in
  `SQLFingerprint`). Postgres impl is a no-op today.
- `explain_sql/1` — wraps SQL for a JSON plan (`"EXPLAIN (FORMAT JSON) " <> sql` for
  Postgres; a MySQL impl would emit `"EXPLAIN FORMAT=JSON " <> sql`).
- `parse_plan/1` — turns the adapter's EXPLAIN-JSON result into the value-free plan map.

Non-Postgres adapters today: fingerprints still work (generic regex); plan capture is a
documented no-op unless a dialect module is provided.

### 2. Query record changes

`build_query_record/2` gains `:fingerprint` and `:normalized`. Raw `:query` stays (raw
timeline only; digest never copies it).

**Implementation check:** unify the two query-record build paths (process-dict path in
`telemetry_capture.ex`, Agent path in `ecto_queries.ex`) so a record never arrives
fingerprint-less and silently falls out of grouping.

### 3. `Excessibility.QueryEvidence` (new, shared)

Fingerprint-based grouping used by **both** the analyzer (wrapped in severity) and the
digest (raw evidence). Avoids divergence. Emits per `(view, callback)`: shapes (fingerprint,
operation, source, normalized, count, sequences) and repeated-group evidence (repetitions,
share, cardinality, severity: `advisory`).

`ecto_query_analysis` N+1 switches from `group_by(&.source)` to fingerprint grouping via
this helper. Keeps the #151 string/atom tolerance.

### 4. `Excessibility.Digest` (new)

Builds `digest.json` from the enriched in-memory timeline + capture context. Constructs
**only** allowlisted fields — never copies-then-scrubs. Crash-isolated (`try/rescue`); on
failure writes `status: :failed | :partial` + `warnings`. Called from `write_snapshots/1`.

Config toggle `digest_include_normalized_sql: false` drops `normalized` to
fingerprint-only (default: included).

## Digest schema `excessibility.digest/v1`

```jsonc
{
  "schema": "excessibility.digest/v1",
  "capture": {
    "status": "ok",                 // ok | partial | failed
    "ecto_configured": true,        // false ⇒ "not measured" (≠ configured+zero)
    "enrichers_run": ["assign_sizes","collection_size","ecto_queries","state"],
    "plan_capture": "disabled",     // disabled | explain | explain_analyze
    "timing": "non_comparable",     // single run never treated as base/head
    "capture_version": "0.18.1",
    "warnings": []
  },
  "coverage": {
    "tests": ["MyAppWeb.PageLiveTest: saves product"],
    "views": ["MyAppWeb.PageLive"],
    "callbacks_observed": ["mount","handle_params","handle_event:save","render"],
    "event_sequence": ["mount","handle_params","handle_event:save","render"],
    "fixtures": {}                  // caller-supplied cardinality only
  },
  "events": [{
    "sequence": 3,
    "callback": "handle_event:save",
    "view": "MyAppWeb.PageLive",
    "queries": {
      "count": 12,
      "shapes": [{                  // COMPLETE — no top-N truncation
        "fingerprint": "sha256:9f3a…",
        "operation": "select", "source": "categories",
        "normalized": "select … where id = $?",
        "count": 10, "sequences": [4,5,6,7,8,9,10,11,12,13]
      }],
      "repeated": [{                // N+1 evidence, grouped by fingerprint
        "fingerprint": "sha256:9f3a…", "source": "categories",
        "repetitions": 10, "share": 0.83, "cardinality": null, "severity": "advisory"
      }],
      "overflow": null              // explicit metadata IF ever bounded — never silent
    },
    "assigns": {
      "total_term_bytes": 24000,
      "shapes": [{ "name": "products", "kind": "list", "cardinality": 50,
                   "term_bytes": 18000, "path_depth": 2,
                   "delta_bytes": 18000, "growth": "increased" }]
    }
  }],
  "trajectories": {                 // per-view cross-event assign patterns
    "MyAppWeb.PageLive": {
      "monotonic_growth": ["products"],
      "retained_after_use": []
    }
  }
}
```

### Assign evidence

Reuses enrichers that already emit only sizes/counts (`assign_sizes`, `collection_size`,
`state`) — value-free by construction. Per assign: `name`, `kind` (list | map | scalar |
`struct:Module`, type only), `cardinality`, `term_bytes`, `path_depth` (bounded),
`delta_bytes`, `growth` (new | increased | decreased | stable | removed). Cross-event
trajectory summary surfaces `monotonic_growth` and `retained_after_use`.

### Coverage/status contract

Makes silence interpretable. The four required distinctions:

- **exercised, no change** → event present, `growth: stable`, `queries.count: 0`.
- **not exercised** → callback absent from `callbacks_observed`.
- **Ecto not configured** → `ecto_configured: false` (≠ `true` + zero queries).
- **enricher disabled / capture failed** → absent from `enrichers_run` / `status:
  partial|failed` + `warnings`.

A missing signal is always labeled *why*.

### Privacy allowlist

Digest never contains: assign values, params/form values, user/session records, SQL bind
values, rendered HTML, arbitrary inspected terms. Redaction by omission — the builder
emits only the fields above; if a field can't be derived safely it is omitted, not
guessed.

## Query-plan evidence (opt-in)

Capture-time step (needs live connection + SQL), **not** a build-time enricher.

Mechanism: on a recorded `:select` query, if enabled, run
`repo.query("EXPLAIN (FORMAT JSON) " <> sql, params)`. Params used transiently to plan,
then discarded. Guards:

- **Re-entrancy:** process-dict flag suppresses EXPLAIN's own Ecto telemetry.
- **Crash isolation:** `try/rescue`; failure ⇒ `plan: null` + `capture.warnings`.

Safety contract (matches issue):

- opt-in only (default `false`); `config :excessibility, query_plan: :explain` or
  `mix excessibility.debug --plan`.
- SELECT-only.
- `EXPLAIN` without `ANALYZE` by default (plans, no side effects).
- `ANALYZE` double-gated: `--plan=analyze` **and**
  `config :excessibility, query_plan_allow_analyze: true`. Loud warning. Read-only
  sandbox only.

Plan evidence per query shape (value-free):

```jsonc
"plan": {
  "mode": "explain",
  "fingerprint": "sha256:…",        // hash of node-type+relation tree, stable
  "nodes": ["Seq Scan on categories","Index Scan on products"],
  "relations": ["categories","products"],
  "estimated_rows": 1000,
  "actual_rows": null, "loops": null, "estimate_error": null  // analyze only
}
```

`plan_capture` in coverage reports `disabled | explain | explain_analyze` so absence is
interpretable.

## `mix excessibility.digest.compare`

> The existing a11y snapshot task `mix excessibility.compare` is renamed to
> `mix excessibility.snapshot.compare` (bare name removed, no alias — BREAKING) so the
> evidence comparison gets an unambiguous, explicit name.

```bash
mix excessibility.digest.compare --base base.json --head head.json [--format json]
```

Input is two **digests** (value-free, timing-omitted, comparable). Events align by
`(view, callback)` aggregated; unmatched callbacks reported as coverage deltas, never
dropped.

Deltas:

- **Queries** — fingerprints `added`/`removed`/`count_changed`; new fingerprint = new
  query source; rising repeat-count = emerging N+1.
- **Plans** — same query fingerprint, different plan fingerprint = plan changed under
  stable SQL; `estimated_rows` delta.
- **Assigns** — `cardinality`/`term_bytes` deltas; newly-appearing `monotonic_growth` /
  `retained_after_use`.
- **Coverage** — callbacks/views newly or no-longer exercised; schema-version mismatch.

**Measurement-scope guard:** a delta is asserted only when *both* sides measured the same
signal. If base `ecto_configured: false` and head `true`, report "base did not measure
queries," not "+12 queries." Same for `plan_capture` / disabled enrichers.

No verdict. Deterministic sorted report (markdown default, `--format json`). Exit `0`
always; severity stays `advisory`.

## Timing contract

- single run: diagnostic only; timing omitted from digest (`timing: non_comparable`).
- benchmark mode: repeated samples, cold vs warm separated, robust stats.
- absolute budget: user-configured, environment-specific (existing analyzers).
- green ⇒ "no relative/configured outlier in this run," not "fast."

### Benchmark mode

```bash
mix excessibility.debug --benchmark=20 test/…_test.exs
```

Loops the test N times, one `timeline.json` per run, collects per-`(view, callback)` and
per-query-fingerprint duration samples → writes `benchmark.json`:

- cold (sample 1) vs warm (2…N) separated;
- median + MAD (not mean/stddev); optional p50/p90;
- extreme-outlier finding: advisory, with raw sample + run config, never a gate.

Timing never enters the comparable digest.

## Callback-attribution regression tests

Attribution is temporal, so boundaries need explicit guarding. Driving telemetry through a
fake LiveView + repo:

1. Pre-mount `setup` seeds do **not** attach to `mount` (locks #151).
2. Query in `handle_event` attributes to that event, not the following `render`.
3. Adjacent `handle_event`s don't bleed queries across.
4. `handle_info` span lands buffered queries on the correct message callback.

Each asserts the query appears on the expected callback's `ecto_queries` and nowhere else.

## Non-goals

- Claim that runtime evidence detects every performance regression.
- Universal latency/query-count budget.
- Replacing source-aware review or profiling.
- Uploading raw timelines by default.
- Base/head checkout orchestration inside the library.

## Acceptance criteria mapping

| Criterion | Covered by |
|---|---|
| Full local timeline remains | unchanged `timeline.json` |
| Versioned value-free digest | `Digest` + `excessibility.digest/v1` |
| No values/params/binds/HTML/terms | allowlist builder, redaction by omission |
| Complete op/source/fingerprint/seq/count | query `shapes`, no top-N |
| No top-N; explicit overflow metadata | `overflow` field |
| N+1 groups fingerprints + cardinality/coverage | `QueryEvidence` `repeated` |
| Coverage distinguishes clean/unexercised/unconfigured | coverage/status contract |
| Assign names + coarse sizes only | assign evidence from size enrichers |
| Plan SELECT-only/opt-in safety | query-plan section |
| Single-run timings omitted/non-comparable | `timing: non_comparable` |
| Benchmark cold/warm + robust stats | benchmark mode |
| Callback-attribution regression tests | attribution tests |
| Compare structural deltas, no verdict | `mix excessibility.compare` |
| Docs position evidence as supplemental | docs update |
