# Runtime Evidence Digest Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a privacy-safe, value-free `digest.json` runtime-evidence artifact (plus a `compare` task, opt-in EXPLAIN plan evidence, and benchmark mode) derived from LiveView telemetry, so a reviewer or tool can interpret query/plan/assign/coverage evidence alongside source code without ever seeing application data.

**Architecture:** SQL is normalized+fingerprinted once in the shared `build_query_record/2`. A shared `QueryEvidence` helper groups queries by fingerprint for both the N+1 analyzer and the digest. `Excessibility.Digest` builds a value-free artifact **in-memory during capture** (in `write_snapshots/1`) by constructing only allowlisted fields — never copy-then-scrub. Query-plan capture is a Postgres-only, opt-in, SELECT-only, crash-isolated capture-time step. `mix excessibility.compare` diffs two digests structurally with a measurement-scope guard and no verdict. Benchmark mode loops runs for robust cold/warm timing stats.

**Tech Stack:** Elixir, Phoenix LiveView telemetry, Ecto (Postgres reference adapter), Jason, ExUnit, Mox.

**Design doc:** `docs/plans/2026-08-10-runtime-evidence-digest-design.md`

**Conventions (from CLAUDE.md):** boolean vars/functions end with `?`. Run `mix format` before every commit. `mix credo` clean. Commit after each task.

---

## Batch 1 — SQL normalization & fingerprint

> **Dialect seam:** Postgres-only implementation, shaped so a MySQL/SQLite dialect drops in
> later. Generic normalization lives in `SQLFingerprint`; only `normalize_extras/1`,
> `explain_sql/1`, `parse_plan/1` are dialect-specific. `Excessibility.Dialect.resolve/0`
> reads `config :excessibility, sql_dialect: :postgres` (default). Do NOT build MySQL/SQLite
> — only the behaviour + the Postgres impl + the single resolution point.

### Task 0: `Excessibility.Dialect` behaviour + Postgres impl

**Files:**
- Create: `lib/excessibility/dialect.ex` (behaviour + `resolve/0`)
- Create: `lib/excessibility/dialect/postgres.ex`
- Test: `test/excessibility/dialect_test.exs`

**Step 1: Failing test**

```elixir
defmodule Excessibility.DialectTest do
  use ExUnit.Case, async: true
  alias Excessibility.Dialect

  test "resolve/0 defaults to Postgres" do
    assert Dialect.resolve() == Excessibility.Dialect.Postgres
  end

  test "postgres explain_sql wraps for json plan" do
    assert Excessibility.Dialect.Postgres.explain_sql("SELECT 1") == "EXPLAIN (FORMAT JSON) SELECT 1"
  end

  test "postgres normalize_extras is a no-op passthrough" do
    assert Excessibility.Dialect.Postgres.normalize_extras("select 1") == "select 1"
  end
end
```

**Step 2: Run** → FAIL.

**Step 3: Implement**

```elixir
# lib/excessibility/dialect.ex
defmodule Excessibility.Dialect do
  @moduledoc """
  Seam isolating the few genuinely dialect-specific SQL behaviors so a new
  database dialect is a drop-in module + one config line, not a core refactor.
  Only Postgres ships today (the Ecto reference adapter).
  """

  @callback normalize_extras(String.t()) :: String.t()
  @callback explain_sql(String.t()) :: String.t()
  @callback parse_plan(term()) :: map() | nil

  @doc "Resolve the configured dialect module (default Postgres)."
  def resolve, do: Application.get_env(:excessibility, :sql_dialect, :postgres) |> module_for()

  defp module_for(:postgres), do: Excessibility.Dialect.Postgres
  defp module_for(mod) when is_atom(mod), do: mod
end
```

```elixir
# lib/excessibility/dialect/postgres.ex
defmodule Excessibility.Dialect.Postgres do
  @moduledoc "Postgres dialect: JSON EXPLAIN + plan parsing. Generic normalization is shared."
  @behaviour Excessibility.Dialect

  @impl true
  def normalize_extras(sql), do: sql  # no pg-specific folds needed today

  @impl true
  def explain_sql(sql), do: "EXPLAIN (FORMAT JSON) " <> sql

  @impl true
  def parse_plan(explain_json), do: Excessibility.QueryPlan.summarize(explain_json)
end
```

**Step 4: Run** → PASS. `mix format`.

**Step 5: Commit** — `git commit -m "feat: add Dialect seam with Postgres impl (#154)"`

> Forward reference: `parse_plan/1` names `Excessibility.QueryPlan.summarize/1`, created in
> Batch 4 (Task 9). Elixir compiles the reference (warning only until Task 9 lands); the
> function is never *called* until plan capture is exercised, so Batch 1–3 stay green. If the
> compile warning bothers credo, temporarily make `parse_plan/1` a `nil` passthrough and wire
> it in Task 9.

### Task 1: `Excessibility.SQLFingerprint`

**Files:**
- Create: `lib/excessibility/sql_fingerprint.ex`
- Test: `test/excessibility/sql_fingerprint_test.exs`

**Step 1: Write the failing test**

```elixir
# test/excessibility/sql_fingerprint_test.exs
defmodule Excessibility.SQLFingerprintTest do
  use ExUnit.Case, async: true
  alias Excessibility.SQLFingerprint

  describe "normalize/1" do
    test "downcases keywords and collapses whitespace" do
      assert SQLFingerprint.normalize("SELECT  *\nFROM   users") == "select * from users"
    end

    test "folds parameter placeholders to $?" do
      assert SQLFingerprint.normalize("SELECT * FROM u WHERE id = $1 AND org = $2") ==
               "select * from u where id = $? and org = $?"
    end

    test "folds IN-list arity so different lengths share a shape" do
      a = SQLFingerprint.normalize("SELECT * FROM u WHERE id IN ($1,$2,$3)")
      b = SQLFingerprint.normalize("SELECT * FROM u WHERE id IN ($1,$2)")
      assert a == b
      assert a =~ "in ($?)"
    end

    test "folds inline numeric and quoted literals to ?" do
      assert SQLFingerprint.normalize("SELECT * FROM u WHERE status = 'active' LIMIT 50") ==
               "select * from u where status = ? limit ?"
    end
  end

  describe "fingerprint/1" do
    test "is stable and prefixed" do
      fp = SQLFingerprint.fingerprint("SELECT * FROM users WHERE id = $1")
      assert fp =~ ~r/^sha256:[0-9a-f]{16}$/
      assert fp == SQLFingerprint.fingerprint("select  *  from users where id = $1")
    end

    test "differs for different query shapes" do
      refute SQLFingerprint.fingerprint("SELECT * FROM a WHERE id = $1") ==
               SQLFingerprint.fingerprint("SELECT * FROM b WHERE id = $1")
    end
  end

  # Property-style leak guard: no digit-run and no quoted literal survives.
  describe "privacy" do
    test "no quoted literal survives normalization" do
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE name = 'Alice O''Brien'") =~ ~r/[a-z]{2,}'/
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE name = 'Alice O''Brien'") =~ "alice"
    end

    test "no multi-digit literal survives" do
      refute SQLFingerprint.normalize("SELECT * FROM u WHERE age = 42 AND ssn = 123456789") =~ ~r/\d{2,}/
    end
  end
end
```

**Step 2: Run to verify it fails** — `mix test test/excessibility/sql_fingerprint_test.exs` → FAIL (module undefined).

**Step 3: Implement**

```elixir
# lib/excessibility/sql_fingerprint.ex
defmodule Excessibility.SQLFingerprint do
  @moduledoc """
  Normalizes SQL into a stable, value-free shape and derives a fingerprint.

  Postgres-oriented (the Ecto reference adapter). Ecto emits parameterized SQL
  (`$1`, `$2` …) with bind values already separated, so normalization only has
  to canonicalize whitespace/case, fold `IN (...)` arity, and scrub the few
  inline literals that appear in fragments. The fingerprint is derived from the
  normalized string, so grouping (N+1, compare) depends on this being correct —
  see the leak-guard tests.
  """

  @doc """
  Normalize SQL to a stable, value-free string. The generic folds here are
  dialect-agnostic; any dialect-specific normalization is applied last via
  `Excessibility.Dialect.normalize_extras/1` (no-op for Postgres today).
  """
  def normalize(sql) when is_binary(sql) do
    sql
    |> String.downcase()
    |> fold_quoted_literals()
    |> fold_param_lists()
    |> fold_params()
    |> fold_numeric_literals()
    |> collapse_whitespace()
    |> String.trim()
    |> Excessibility.Dialect.resolve().normalize_extras()
  end

  def normalize(_), do: ""

  @doc ~S'Fingerprint SQL as `"sha256:<16 hex>"`.'
  def fingerprint(sql) do
    hash =
      sql
      |> normalize()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    "sha256:" <> hash
  end

  # 'text' and 'escaped '' quotes' -> ?   (do this first, before digit folding)
  defp fold_quoted_literals(sql), do: Regex.replace(~r/'(?:[^']|'')*'/, sql, "?")

  # IN ($1, $2, $3) / IN (?, ?) -> IN ($?)
  defp fold_param_lists(sql),
    do: Regex.replace(~r/\bin\s*\(\s*(?:\$\d+|\?)(?:\s*,\s*(?:\$\d+|\?))*\s*\)/, sql, "in ($?)")

  # remaining $1, $2 -> $?
  defp fold_params(sql), do: Regex.replace(~r/\$\d+/, sql, "$?")

  # bare numbers (e.g. LIMIT 50) -> ?
  defp fold_numeric_literals(sql), do: Regex.replace(~r/\b\d+\b/, sql, "?")

  defp collapse_whitespace(sql), do: Regex.replace(~r/\s+/, sql, " ")
end
```

**Step 4: Run** — `mix test test/excessibility/sql_fingerprint_test.exs` → PASS. Then `mix format`.

**Step 5: Commit**

```bash
git add lib/excessibility/sql_fingerprint.ex test/excessibility/sql_fingerprint_test.exs
git commit -m "feat: add SQLFingerprint normalizer (#154)"
```

> Note for executor: run tests after each fold to confirm ordering (quoted-literals must precede numeric folding or digits inside strings leak). If a real captured query breaks a leak-guard, add a fold — do not weaken the assertion.

---

## Batch 2 — Fingerprint into query records + shared QueryEvidence

### Task 2: Add `:fingerprint`/`:normalized` to query records

**Files:**
- Modify: `lib/telemetry_capture/enrichers/ecto_queries.ex:94-108` (`build_query_record/2`)
- Test: `test/telemetry_capture/enrichers/ecto_queries_test.exs` (add cases; create file if absent)

**Step 1: Failing test**

```elixir
test "build_query_record/2 adds fingerprint and value-free normalized sql" do
  measurements = %{total_time: System.convert_time_unit(2, :millisecond, :native)}
  metadata = %{source: "products", query: "SELECT * FROM products WHERE id = $1", repo: MyRepo}

  record = Excessibility.TelemetryCapture.Enrichers.EctoQueries.build_query_record(measurements, metadata)

  assert record.operation == :select
  assert record.fingerprint =~ ~r/^sha256:[0-9a-f]{16}$/
  assert record.normalized == "select * from products where id = $?"
  assert record.query == "SELECT * FROM products WHERE id = $1"  # raw retained for local timeline
end
```

**Step 2: Run** → FAIL (no `:fingerprint`).

**Step 3: Implement** — in `build_query_record/2`, add fields:

```elixir
raw = Map.get(metadata, :query, "")

%{
  source: Map.get(metadata, :source, "unknown"),
  operation: extract_operation(raw),
  duration_ms: Float.round(duration_ms, 2),
  query: raw,
  normalized: Excessibility.SQLFingerprint.normalize(raw),
  fingerprint: Excessibility.SQLFingerprint.fingerprint(raw),
  repo: Map.get(metadata, :repo)
}
```

**Step 4: Run** → PASS. This covers BOTH recording paths (`ecto_queries.ex` handler and `telemetry_capture.ex:113` process-dict path both call `build_query_record/2`).

**Step 5: Commit** — `git commit -m "feat: fingerprint ecto query records (#154)"`

### Task 3: `Excessibility.QueryEvidence` shared grouping

**Files:**
- Create: `lib/excessibility/query_evidence.ex`
- Test: `test/excessibility/query_evidence_test.exs`

**Step 1: Failing test**

```elixir
defmodule Excessibility.QueryEvidenceTest do
  use ExUnit.Case, async: true
  alias Excessibility.QueryEvidence

  defp q(op, source, fp), do: %{operation: op, source: source, fingerprint: fp, normalized: "n"}

  test "shapes/1 groups by fingerprint with complete counts, no truncation" do
    queries = [q(:select, "categories", "sha256:aaa"), q(:select, "categories", "sha256:aaa"),
               q(:select, "products", "sha256:bbb")]
    shapes = QueryEvidence.shapes(queries)
    assert length(shapes) == 2
    aaa = Enum.find(shapes, &(&1.fingerprint == "sha256:aaa"))
    assert aaa.count == 2
    assert aaa.source == "categories"
  end

  test "repeated/2 flags fingerprints at/over min_repetitions with share" do
    queries = List.duplicate(q(:select, "categories", "sha256:aaa"), 10) ++
              [q(:select, "products", "sha256:bbb"), q(:insert, "orders", "sha256:ccc")]
    [rep] = QueryEvidence.repeated(queries, min_repetitions: 3)
    assert rep.fingerprint == "sha256:aaa"
    assert rep.repetitions == 10
    assert_in_delta rep.share, 10 / 12, 0.001
    assert rep.severity == :advisory
  end

  test "select?/1 tolerates string operations from reloaded json (issue #151)" do
    assert QueryEvidence.select?(%{operation: "select"})
    assert QueryEvidence.select?(%{operation: :select})
  end
end
```

**Step 2: Run** → FAIL.

**Step 3: Implement**

```elixir
# lib/excessibility/query_evidence.ex
defmodule Excessibility.QueryEvidence do
  @moduledoc """
  Fingerprint-based query grouping shared by the `ecto_query_analysis` analyzer
  (which wraps it in severity) and `Excessibility.Digest` (which emits it raw).
  Tolerates string values from reloaded `timeline.json` (issue #151).
  """

  @default_min_repetitions 3

  def shapes(queries) do
    queries
    |> Enum.with_index(1)
    |> Enum.group_by(fn {q, _i} -> q.fingerprint end)
    |> Enum.map(fn {fp, pairs} ->
      {first, _} = hd(pairs)
      %{
        fingerprint: fp,
        operation: to_string(first.operation),
        source: to_string(first.source),
        normalized: Map.get(first, :normalized, ""),
        count: length(pairs),
        sequences: Enum.map(pairs, fn {_q, i} -> i end)
      }
    end)
    |> Enum.sort_by(& &1.fingerprint)
  end

  def repeated(queries, opts \\ []) do
    min = Keyword.get(opts, :min_repetitions, @default_min_repetitions)
    total = max(length(queries), 1)

    queries
    |> Enum.filter(&select?/1)
    |> Enum.group_by(& &1.fingerprint)
    |> Enum.filter(fn {_fp, group} -> length(group) >= min end)
    |> Enum.map(fn {fp, group} ->
      first = hd(group)
      %{
        fingerprint: fp,
        source: to_string(first.source),
        operation: to_string(first.operation),
        repetitions: length(group),
        share: length(group) / total,
        cardinality: nil,
        severity: :advisory
      }
    end)
    |> Enum.sort_by(& &1.fingerprint)
  end

  def select?(%{operation: op}), do: to_string(op) == "select"
  def select?(_), do: false
end
```

**Step 4: Run** → PASS. `mix format`.

**Step 5: Commit** — `git commit -m "feat: add shared QueryEvidence fingerprint grouping (#154)"`

### Task 4: Switch N+1 analyzer to fingerprint grouping

**Files:**
- Modify: `lib/telemetry_capture/analyzers/ecto_query_analysis.ex:80-117` (`detect_n_plus_one`, keep thresholds)
- Test: `test/telemetry_capture/analyzers/ecto_query_analysis_test.exs`

**Step 1: Failing test** — add:

```elixir
test "N+1 distinguishes two different SELECTs on the same table" do
  # 3x fingerprint A + 3x fingerprint B, both source "categories":
  # grouping by source alone would over-count; fingerprint grouping yields two findings.
  # (build a timeline event with 6 select queries: 3 with query "... id = $1", 3 with "... slug = $1")
  ...
  assert length(findings) == 2
end
```

**Step 2: Run** → FAIL (source grouping yields 1).

**Step 3: Implement** — replace the `group_by(& &1.source)` block with `Excessibility.QueryEvidence.repeated(queries, min_repetitions: 3)` and map each `repeated` entry to the existing finding shape (message like `"#{rep.source} #{rep.operation} repeated #{rep.repetitions}x (same query shape)"`, `severity: :warning`). Preserve `select?/1` tolerance by using `QueryEvidence.select?/1`.

**Step 4: Run** full analyzer suite → PASS. Confirm existing N+1 tests still pass.

**Step 5: Commit** — `git commit -m "feat: group N+1 by query fingerprint (#154)"`

---

## Batch 3 — Digest builder + schema, emitted during capture

### Task 5: `Excessibility.Digest` — query + coverage core

**Files:**
- Create: `lib/excessibility/digest.ex`
- Test: `test/excessibility/digest_test.exs`

**Step 1: Failing test** (build against an in-memory timeline map, the same shape `Timeline.build_timeline/3` returns):

```elixir
defmodule Excessibility.DigestTest do
  use ExUnit.Case, async: true
  alias Excessibility.Digest

  defp timeline do
    %{
      test: "PageLiveTest: saves",
      timeline: [
        %{sequence: 1, event: "mount", view_module: "PageLive", ecto_queries: [], assign_sizes: %{}},
        %{sequence: 2, event: "handle_event:save", view_module: "PageLive",
          ecto_queries: List.duplicate(
            %{operation: :select, source: "categories", fingerprint: "sha256:aaa",
              normalized: "select … where id = $?", duration_ms: 1.0, query: "SELECT ..."}, 10),
          assign_sizes: %{"products" => 18_000}, total_memory: 18_000,
          list_sizes: %{"products" => 50}}
      ]
    }
  end

  test "emits versioned schema and value-free query shapes with no raw sql" do
    d = Digest.build(timeline(), ecto_configured?: true, enrichers_run: [:ecto_queries, :assign_sizes])
    assert d.schema == "excessibility.digest/v1"
    assert d.capture.status == :ok
    assert d.capture.ecto_configured == true

    ev = Enum.find(d.events, &(&1.callback == "handle_event:save"))
    assert ev.queries.count == 10
    [shape] = ev.queries.shapes
    assert shape.fingerprint == "sha256:aaa"
    assert shape.count == 10
    # NO raw sql anywhere in the digest
    refute Jason.encode!(d) =~ "SELECT ..."
  end

  test "N+1 evidence groups by fingerprint" do
    d = Digest.build(timeline(), ecto_configured?: true)
    ev = Enum.find(d.events, &(&1.callback == "handle_event:save"))
    assert [%{fingerprint: "sha256:aaa", repetitions: 10, severity: :advisory}] = ev.queries.repeated
  end

  test "coverage distinguishes unconfigured from configured-and-clean" do
    d = Digest.build(timeline(), ecto_configured?: false)
    assert d.capture.ecto_configured == false
  end
end
```

**Step 2: Run** → FAIL.

**Step 3: Implement** — `Digest.build(timeline, opts \\ [])`:
- `@schema_version "excessibility.digest/v1"`.
- Wrap body in `try/rescue`; on rescue return a digest with `capture.status: :failed`, `warnings: [Exception.message]`, empty events.
- `capture`: `status: :ok`, `ecto_configured:` from opts, `enrichers_run:` from opts, `plan_capture:` from opts (default `:disabled`), `timing: :non_comparable`, `capture_version: Excessibility.MixProject.project()[:version]` (or read `Application.spec(:excessibility, :vsn)`), `warnings: []`.
- `coverage`: `tests` (list with `timeline.test`), `views` (unique `view_module`), `callbacks_observed`/`event_sequence` (from `event`), `fixtures: opts[:fixtures] || %{}`.
- `events`: map each timeline entry → `%{sequence, callback: event, view: view_module, queries: query_block(entry), assigns: assign_block(entry)}`.
- `query_block`: `%{count: length(ecto_queries), shapes: QueryEvidence.shapes(q), repeated: QueryEvidence.repeated(q, min_repetitions: 3), overflow: nil}`.
- Respect `config :excessibility, digest_include_normalized_sql: false` → strip `:normalized` from each shape.
- `assign_block`: implemented in Task 6 (return `%{total_term_bytes: 0, shapes: []}` stub for now).

**Step 4: Run** → PASS. `mix format`, `mix credo`.

**Step 5: Commit** — `git commit -m "feat: add Digest builder with query+coverage evidence (#154)"`

### Task 6: Assign-shape/growth + trajectories

**Files:**
- Modify: `lib/excessibility/digest.ex` (`assign_block/2`, add `trajectories/1`)
- Test: `test/excessibility/digest_test.exs` (add)

**Step 1: Failing test**

```elixir
test "assign shapes carry names and coarse sizes only, with per-event growth" do
  d = Digest.build(timeline(), ecto_configured?: true)
  ev = Enum.find(d.events, &(&1.callback == "handle_event:save"))
  [a] = ev.assigns.shapes
  assert a.name == "products"
  assert a.kind == "list"
  assert a.cardinality == 50
  assert a.term_bytes == 18_000
  assert a.growth in ["new", "increased", "decreased", "stable", "removed"]
  refute Map.has_key?(a, :value)
end

test "trajectories flag monotonic growth across events" do
  # timeline where products grows 0 -> 9000 -> 18000
  d = Digest.build(growing_timeline(), ecto_configured?: true)
  assert "products" in d.trajectories["PageLive"].monotonic_growth
end
```

**Step 2: Run** → FAIL.

**Step 3: Implement**
- `assign_block(entry, prev_entry)`: for each key in `entry.assign_sizes`, build `%{name, kind, cardinality, term_bytes, path_depth, delta_bytes, growth}`. `kind` from `list_sizes`/value type (list | map | scalar | `"struct:Module"`); `cardinality` from `list_sizes[name]` (nil if scalar); `term_bytes` from `assign_sizes[name]`; `delta_bytes` = current − prev; `growth` classification (`new` if absent before, `removed` if absent now, else compare bytes). `total_term_bytes` from `total_memory`.
- Thread `prev_entry` by folding over events per view (reuse `Analyzer.group_by_view/1` conceptually, or track a `%{name => bytes}` accumulator).
- `trajectories/1`: per view, `monotonic_growth` = assigns whose `term_bytes` is non-decreasing and strictly increases at least once across the view's events; `retained_after_use` = grew then stayed ≥ that size through the final event.

**Step 4: Run** → PASS.

**Step 5: Commit** — `git commit -m "feat: add assign-shape evidence and trajectories to digest (#154)"`

### Task 7: Emit `digest.json` during capture

**Files:**
- Modify: `lib/telemetry_capture.ex:343-351` (inside `write_snapshots/1`, after timeline write)
- Test: `test/telemetry_capture_test.exs` (add a write test, or an integration assertion)

**Step 1: Failing test** — assert that after `write_snapshots/1` runs with snapshots present, a `digest.json` exists at the output path, decodes, and has `"schema" => "excessibility.digest/v1"` with no raw SQL substring.

**Step 2: Run** → FAIL (no digest written).

**Step 3: Implement** — after `File.write!(timeline_path, timeline_json)`:

```elixir
digest =
  Excessibility.Digest.build(timeline,
    ecto_configured?: configured_repos() != [],
    enrichers_run: enricher_names(enrichers),
    plan_capture: plan_capture_mode(),
    fixtures: fixtures_from_env()
  )

File.write!(Path.join(output_path, "digest.json"), Formatter.format_json(digest))
```

Add private helpers: `enricher_names/1` (map modules→`name/0`, or `[]` when `:all`/list), `plan_capture_mode/0` (reads env set in Task 12; default `:disabled`), `fixtures_from_env/0` (default `%{}`). `Digest.build` is already crash-isolated, but keep the outer `write_snapshots/1` rescue as the backstop.

**Step 4: Run** → PASS. Run a real `mix excessibility.debug` against an existing telemetry test and eyeball `digest.json`.

**Step 5: Commit** — `git commit -m "feat: emit digest.json during capture (#154)"`

### Task 8: `--format digest` reads/prints the digest

**Files:**
- Modify: `lib/mix/tasks/excessibility_debug.ex:135-144` (add case clause), add `output_digest/1`
- Test: task-level or manual

**Step 3: Implement** — add `"digest" -> output_digest(report_data)` to the format `case`; `output_digest/1` reads `<output_path>/digest.json` and prints it (pretty JSON) or its path. No new capture logic (digest already written in Task 7).

**Step 5: Commit** — `git commit -m "feat: add --format digest output (#154)"`

---

## Batch 4 — Opt-in query-plan evidence (Postgres-only)

### Task 9: Plan extraction from EXPLAIN JSON

**Files:**
- Create: `lib/excessibility/query_plan.ex`
- Test: `test/excessibility/query_plan_test.exs`

**Step 1: Failing test** — feed a captured `EXPLAIN (FORMAT JSON)` structure (a decoded map/list) into `QueryPlan.summarize/1`; assert it returns `%{fingerprint: "sha256:…", nodes: [...], relations: [...], estimated_rows: n, actual_rows: nil, loops: nil, estimate_error: nil}` and that the fingerprint is stable across two plans that differ only in cost/row estimates.

**Step 3: Implement** — `summarize(explain_json)` walks the plan tree, collects `"Node Type"` + `"Relation Name"` into `nodes`/`relations`, reads `"Plan Rows"`→`estimated_rows`, `"Actual Rows"`/`"Actual Loops"` when present (analyze). `fingerprint` = `SQLFingerprint`-style sha256 over the node-type+relation tree only (exclude costs/rows so it is stable). `estimate_error` = ratio when both estimated and actual present.

**Step 5: Commit** — `git commit -m "feat: summarize EXPLAIN json into value-free plan evidence (#154)"`

### Task 10: Capture-time EXPLAIN with re-entrancy + crash guards

**Files:**
- Modify: `lib/telemetry_capture.ex` (`handle_ecto_query/4:112` path) — after building the record, if plan capture enabled and `record.operation == :select`, attach a `:plan`.
- Test: `test/telemetry_capture_test.exs`

**Step 1: Failing test** — with a stub repo whose `query/2` returns a canned EXPLAIN JSON, and plan capture enabled, assert the flushed query record for a SELECT gains `:plan` with the expected fingerprint; assert a non-SELECT gets `plan: nil`; assert that the EXPLAIN's own `[:ecto, :query]` telemetry (simulated re-entrant call) does NOT get recorded (re-entrancy guard via process-dict flag).

**Step 3: Implement**
- Guard flag: `Process.get(:excessibility_in_explain)` — set true around the `repo.query(Excessibility.Dialect.resolve().explain_sql(sql), params)` call (dialect supplies EXPLAIN syntax); in `handle_ecto_query/4`, if the flag is set, return early (do not record).
- Parse the EXPLAIN result via the dialect: `plan = Excessibility.Dialect.resolve().parse_plan(decoded_json)` (Postgres delegates to `QueryPlan.summarize/1`). Attach `plan` to the record.
- Params: read from `metadata[:params]` transiently; never store them on the record.
- Wrap EXPLAIN in `try/rescue` → on failure `plan: nil` + accumulate a warning (process-dict list drained into digest `capture.warnings`).
- `plan_capture_mode/0`: `:explain` | `:explain_analyze` | `:disabled` from `EXCESSIBILITY_QUERY_PLAN` env; `:explain_analyze` additionally requires `config :excessibility, query_plan_allow_analyze: true` else downgrade to `:explain` + warning.

**Step 5: Commit** — `git commit -m "feat: opt-in capture-time EXPLAIN plan evidence (#154)"`

### Task 11: Thread plan into digest + `--plan` flag

**Files:**
- Modify: `lib/excessibility/digest.ex` (query shape gains `:plan` when present)
- Modify: `lib/mix/tasks/excessibility_debug.ex` (add `plan: :string` to strict opts; set `EXCESSIBILITY_QUERY_PLAN` env in `run_test/1`)
- Test: digest test + task

**Step 3: Implement** — `--plan` → `EXCESSIBILITY_QUERY_PLAN=explain`; `--plan=analyze` → `explain_analyze`. `Digest` copies `entry` query `:plan` into the corresponding shape (attach plan to the shape's first representative; plans are per-fingerprint-stable). `capture.plan_capture` already surfaced (Task 7).

**Step 5: Commit** — `git commit -m "feat: wire query-plan evidence through digest and --plan (#154)"`

---

## Batch 5 — `mix excessibility.compare`

### Task 12: Structural digest diff

**Files:**
- Create: `lib/excessibility/digest_compare.ex` (pure diff logic)
- Test: `test/excessibility/digest_compare_test.exs`

**Step 1: Failing test** — cover:
- new fingerprint in head → `queries.added`;
- rising repeat-count → `queries.count_changed` / emerging N+1;
- same query fingerprint, different plan fingerprint → `plans.changed`;
- assign `term_bytes` delta;
- **measurement-scope guard:** base `ecto_configured: false`, head `true` → a `coverage` note "base did not measure queries", and NO fabricated `queries.added`.

**Step 3: Implement** — `DigestCompare.diff(base, head)` returns a deterministic, sorted map keyed by `(view, callback)` plus a top-level `coverage` section. Only assert a signal delta when both sides have `ecto_configured`/matching `plan_capture`/matching `enrichers_run`; otherwise emit a scope note. No severity beyond `advisory`; no verdict field.

**Step 5: Commit** — `git commit -m "feat: add structural digest compare logic (#154)"`

### Task 13: `mix excessibility.compare` task

**Files:**
- Create: `lib/mix/tasks/excessibility_compare.ex` — WAIT: `lib/mix/tasks/excessibility_compare.ex` already exists (accessibility snapshot compare). Use a distinct task name to avoid collision: `lib/mix/tasks/excessibility.evidence_compare.ex` (`mix excessibility.evidence_compare`) OR add a subcommand. **Decision needed at execution time — see open question below.**
- Test: task smoke test.

**Step 3: Implement** — parse `--base`/`--head`/`--format`; `Jason.decode!` both (keys: :atoms); call `DigestCompare.diff/2`; render markdown (default) or JSON; always exit 0.

**Step 5: Commit** — `git commit -m "feat: add evidence compare mix task (#154)"`

---

## Batch 6 — Benchmark mode

### Task 14: Repeated-run benchmark with robust stats

**Files:**
- Create: `lib/excessibility/benchmark.ex` (stats: median, MAD)
- Modify: `lib/mix/tasks/excessibility_debug.ex` (add `benchmark: :string`; when set, loop `run_test/1` N times, collect per-`(view, callback)` and per-fingerprint `duration_ms`, write `benchmark.json`)
- Test: `test/excessibility/benchmark_test.exs` (unit-test `median/1`, `mad/1`, cold/warm split, and the aggregate shape)

**Step 1: Failing test** — `Benchmark.summarize(samples)` where sample 1 is cold, 2..N warm; assert output separates `cold`/`warm`, reports `median`+`mad` per key, and marks an extreme outlier advisory with the raw sample attached.

**Step 3: Implement** — pure stats module + task loop. Median/MAD implemented directly (no dep). Outlier: sample > median + k·MAD (k configurable, default 6) → advisory finding, never a failure.

**Step 5: Commit** — `git commit -m "feat: add benchmark mode with cold/warm robust stats (#154)"`

---

## Batch 7 — Callback-attribution regression tests + docs

### Task 15: Attribution regression tests

**Files:**
- Create/extend: `test/telemetry_capture/attribution_test.exs`

Drive telemetry through a fake LiveView process + fake repo emitting `[:ecto, :query]` events (mirror the existing `test/live_view_test.exs` proxy pattern). Assert, each with "appears on expected callback AND nowhere else":
1. Pre-mount `setup` seed queries do NOT attach to `mount` (locks #151).
2. Query fired in `handle_event` attributes to that event, not the following `render`.
3. Adjacent `handle_event`s don't bleed queries across.
4. `handle_info` span (opt-in hook) lands buffered queries on the correct message callback.

**Step 5: Commit** — `git commit -m "test: callback-attribution boundary regression tests (#154)"`

### Task 16: Documentation

**Files:**
- Modify: `README.md`, `CLAUDE.md` (Timeline Analysis section)

Document: `digest.json` (value-free, safe for CI/model upload) vs `timeline.json` (local only); the schema and privacy allowlist; `--plan` opt-in safety + Postgres-only limitation; `mix excessibility.evidence_compare`; benchmark mode; and the timing contract ("green ≠ fast"). Position runtime evidence as **supplemental** input for debugging and code-aware review (acceptance criterion).

**Step 5: Commit** — `git commit -m "docs: document runtime evidence digest, compare, plan, benchmark (#154)"`

---

## Final verification (before PR)

Use superpowers:verification-before-completion. Run and paste output:
- `mix format --check-formatted`
- `MIX_ENV=test mix credo --strict`
- `mix test`
- `mix excessibility.debug test/<a telemetry test>` → confirm `digest.json` is written, value-free (grep it for any known assign value / bind value → expect none), schema `excessibility.digest/v1`.
- Re-check every issue #154 acceptance criterion against the mapping table in the design doc.

Then `superpowers:finishing-a-development-branch` to open the PR referencing #154.

---

## Open questions for execution time

1. **Compare task name.** `mix excessibility.compare` already exists for a11y snapshot compare (`lib/mix/tasks/excessibility_compare.ex`). Plan assumes a new name `mix excessibility.evidence_compare`. Confirm with maintainer (issue's names are explicitly "illustrative").
2. **`capture_version` source.** Use `Application.spec(:excessibility, :vsn)` at runtime; confirm it's available in the test process.
3. **Fixtures input channel.** `fixtures_from_env/0` — decide the mechanism (env var JSON vs config) for caller-supplied cardinality; default `%{}` ships regardless.
