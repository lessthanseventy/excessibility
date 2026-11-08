defmodule Mix.Tasks.Excessibility.Debug do
  @shortdoc "Debug a test with comprehensive snapshot analysis"

  @moduledoc """
  Run tests and generate a comprehensive debug report with all snapshots.

  All arguments are passed through to `mix test`, so you can use any
  test filtering options.

  This command automatically enables telemetry capture by setting
  `EXCESSIBILITY_TELEMETRY_CAPTURE=true`, which captures:
  - Mount events
  - handle_event calls (clicks, submits)
  - handle_params calls (navigation)
  - **All render cycles** (form updates, state changes)

  Render event capture dramatically increases timeline visibility (often 10-20x more events),
  enabling powerful analyzer insights like memory leak detection, performance bottlenecks,
  and event pattern analysis.

  ## Usage

      # Run a test file
      mix excessibility.debug test/my_test.exs

      # Run a specific test by line number
      mix excessibility.debug test/my_test.exs:42

      # Run tests with a tag
      mix excessibility.debug --only live_view

      # Run a describe block
      mix excessibility.debug test/my_test.exs:10

      # With debug options
      mix excessibility.debug test/my_test.exs --format=json
      mix excessibility.debug test/my_test.exs --full
      mix excessibility.debug test/my_test.exs --minimal
      mix excessibility.debug test/my_test.exs --highlight=current_user,cart_items

  ## Flags

  - `--format=markdown|json|package|digest` - Output format (default: markdown)
  - `--full` - Disable all filtering, show complete assigns
  - `--minimal` - Timeline only, no detailed snapshots
  - `--no-filter-ecto` - Keep Ecto metadata (__meta__, NotLoaded)
  - `--no-filter-phoenix` - Keep Phoenix internals (flash, __changed__)
  - `--highlight=field1,field2` - Custom fields to highlight in timeline

  ## Analysis Options

  - `--analyze=NAMES` - Run specific analyzers (comma-separated). Available: memory, performance, data_growth, event_pattern, ecto_query_analysis, state_machine
  - `--analyze=all` - Run all available analyzers
  - `--profile=NAME` - Use a predefined profile (quick, memory, performance, full)
  - `--no-analyze` - Skip analysis, show timeline only
  - `--verbose` - Show detailed stats even when no issues found

  ## Query Plan Evidence (opt-in, Postgres-only)

  - `--plan` - Boolean flag. Capture value-free `EXPLAIN` plan evidence for
    each SELECT and attach it to the digest's query shapes. Runs
    `EXPLAIN (FORMAT JSON) <query>` — it plans but never executes the query,
    so it touches no data. SELECT-only.
  - `--plan-analyze` - Boolean flag. Capture `EXPLAIN ANALYZE` plan evidence,
    which includes actual row counts. This *executes* the query, so it is
    double-gated: it additionally requires
    `config :excessibility, query_plan_allow_analyze: true`. Only run inside a
    DB sandbox / read-only environment.

  Both are bare boolean flags and can be combined with a test path in any
  order, e.g. `mix excessibility.debug --plan test/foo.exs` or
  `mix excessibility.debug test/foo.exs --plan`.

  Safety notes:

  - **SELECT-only.** Only `SELECT` queries are ever run through `EXPLAIN`;
    non-SELECT statements are never re-executed.
  - **`EXPLAIN` does not `ANALYZE` by default.** Plain `--plan` runs
    `EXPLAIN (FORMAT JSON) <query>`, which plans but never executes the query,
    so it touches no data.
  - **`ANALYZE` is double-gated.** `--plan-analyze` *executes* the query to
    gather real row counts, so it additionally requires
    `config :excessibility, query_plan_allow_analyze: true`. Without that
    config it downgrades to plain `EXPLAIN` with a warning. Only run `ANALYZE`
    inside a DB sandbox.

  ## Benchmark Mode (opt-in)

  - `--benchmark=N` - Run the test N times and write a value-free
    `benchmark.json` with robust cold/warm timing stats (median + MAD) per
    `(view, callback)` and per query-fingerprint. Sample 1 is treated as **cold**
    (compilation, connection warmup, cold caches); samples 2..N are **warm**, and
    the two are reported separately so a cold first run cannot poison the median.

    Timing is diagnostic ONLY and never enters the digest. An advisory outlier
    (a warm sample beyond `median + k*mad`) means "green = no relative outlier in
    these samples, **not** 'fast'." It is never a pass/fail gate.

        mix excessibility.debug --benchmark=20 test/my_live_view_test.exs

  ## Formats

  - `markdown` (default) - Human and AI-readable report with inline HTML
  - `json` - Structured JSON output for programmatic parsing
  - `package` - Creates a directory with MANIFEST, timeline, and all snapshots
  - `digest` - Prints the value-free `digest.json` runtime-evidence artifact

  ## Output

  The command outputs the report to stdout and also saves it to:
  - Markdown: `test/excessibility/latest_debug.md`
  - JSON: `test/excessibility/latest_debug.json`
  - Timeline: `test/excessibility/timeline.json` (always generated)
  - Package: `test/excessibility/debug_packages/[test_name]_[timestamp]/`
  """

  use Mix.Task

  alias Excessibility.Debug.BenchmarkRun
  alias Excessibility.Debug.Report
  alias Excessibility.TelemetryCapture.Profiles
  alias Excessibility.TelemetryCapture.Registry

  @impl Mix.Task
  def run(args) do
    {opts, test_args, _} =
      OptionParser.parse(args,
        strict: [
          format: :string,
          full: :boolean,
          minimal: :boolean,
          no_filter_ecto: :boolean,
          no_filter_phoenix: :boolean,
          highlight: :string,
          analyze: :string,
          profile: :string,
          no_analyze: :boolean,
          verbose: :boolean,
          plan: :boolean,
          plan_analyze: :boolean,
          benchmark: :integer
        ],
        aliases: [f: :format, p: :profile]
      )

    format = Keyword.get(opts, :format, "markdown")
    minimal_mode = Keyword.get(opts, :minimal, false)
    filter_opts = build_filter_opts(opts)

    # Store opts in process dictionary for use during formatting
    Process.put(:excessibility_debug_opts, %{
      format: format,
      minimal: minimal_mode,
      filter_opts: filter_opts,
      plan_env: plan_env(opts)
    })

    if test_args == [] do
      Mix.shell().error("Usage: mix excessibility.debug [mix test args]")
      Mix.shell().info("\nExamples:")
      Mix.shell().info("  mix excessibility.debug test/my_test.exs")
      Mix.shell().info("  mix excessibility.debug test/my_test.exs:42")
      Mix.shell().info("  mix excessibility.debug --only live_view")
      exit({:shutdown, 1})
    end

    # Benchmark mode short-circuits the single-run report: it loops the test,
    # collects robust timing stats, and writes benchmark.json instead.
    case Keyword.get(opts, :benchmark) do
      nil -> run_single(test_args)
      runs -> BenchmarkRun.run_benchmark(runs, test_args)
    end
  end

  defp run_single(test_args) do
    format = :excessibility_debug_opts |> Process.get(%{}) |> Map.get(:format, "markdown")

    # Run the test and capture output
    {test_output, exit_code} = run_test(test_args)

    # Gather snapshots
    snapshots = Report.gather_snapshots()

    # Build report based on format
    test_description = Enum.join(test_args, " ")

    report_data = %{
      test_path: test_description,
      status: if(exit_code == 0, do: "passed", else: "failed"),
      test_output: test_output,
      snapshots: snapshots,
      timestamp: DateTime.utc_now()
    }

    case format do
      "json" ->
        Report.output_json(report_data)

      "package" ->
        Report.output_package(report_data)

      "digest" ->
        Report.output_digest(report_data)

      _ ->
        Report.output_markdown(report_data)
    end

    if exit_code != 0, do: exit({:shutdown, exit_code})
  end

  defp build_filter_opts(opts) do
    full_mode = Keyword.get(opts, :full, false)

    filter_opts =
      if full_mode do
        [filter_ecto: false, filter_phoenix: false]
      else
        [
          filter_ecto: not Keyword.get(opts, :no_filter_ecto, false),
          filter_phoenix: not Keyword.get(opts, :no_filter_phoenix, false)
        ]
      end

    # Carry the analyzer-selection flags through: parse_analyzer_selection reads
    # these off filter_opts, so without them --analyze/--no-analyze/--profile
    # are silently ignored and the run always falls back to the default set.
    filter_opts = Keyword.merge(filter_opts, Keyword.take(opts, [:analyze, :no_analyze, :profile]))

    # Parse highlight fields if provided
    case Keyword.get(opts, :highlight) do
      nil ->
        filter_opts

      fields_str ->
        highlight_fields = fields_str |> String.split(",") |> Enum.map(&String.to_atom/1)
        Keyword.put(filter_opts, :highlight_fields, highlight_fields)
    end
  end

  @doc false
  @spec run_test([String.t()]) :: {String.t(), non_neg_integer()}
  def run_test(test_args) do
    # Enable telemetry capture
    System.put_env("EXCESSIBILITY_TELEMETRY_CAPTURE", "true")

    # Get opts from process dictionary
    debug_opts = Process.get(:excessibility_debug_opts, %{})
    filter_opts = Map.get(debug_opts, :filter_opts, [])
    plan_env = Map.get(debug_opts, :plan_env, [])

    # Resolve which analyzers to run and pass via env var
    analyzer_names = parse_analyzer_selection(filter_opts)
    analyzers_env = Enum.map_join(analyzer_names, ",", &to_string/1)

    # Run the test with all args passed through
    Mix.shell().info("Running: mix test #{Enum.join(test_args, " ")}\n")

    {output, exit_code} =
      System.cmd("mix", ["test" | test_args],
        stderr_to_stdout: true,
        env:
          [
            {"MIX_ENV", "test"},
            {"EXCESSIBILITY_TELEMETRY_CAPTURE", "true"},
            {"EXCESSIBILITY_ANALYZERS", analyzers_env}
          ] ++ plan_env
      )

    # Echo the output to the console; the string is also returned.
    Mix.shell().info(output)

    {output, exit_code}
  end

  # Public (but @doc false) so the opt->env translation can be unit-tested
  # without shelling out. Translates the boolean `--plan` / `--plan-analyze`
  # opts into the `EXCESSIBILITY_QUERY_PLAN` env passed to the `mix test`
  # subprocess:
  #   neither          -> []           (plan capture stays disabled)
  #   --plan           -> [{"EXCESSIBILITY_QUERY_PLAN", "explain"}]
  #   --plan-analyze   -> [{"EXCESSIBILITY_QUERY_PLAN", "explain_analyze"}]
  # Both booleans, so plain `--plan test/foo.exs` does not swallow the test
  # path as a value. When both are set, analyze wins.
  @doc false
  def plan_env(opts) do
    cond do
      Keyword.get(opts, :plan_analyze, false) -> [{"EXCESSIBILITY_QUERY_PLAN", "explain_analyze"}]
      Keyword.get(opts, :plan, false) -> [{"EXCESSIBILITY_QUERY_PLAN", "explain"}]
      true -> []
    end
  end

  @doc false
  @spec parse_analyzer_selection(keyword()) :: [atom()] | nil
  def parse_analyzer_selection(opts) do
    cond do
      Keyword.get(opts, :no_analyze) -> []
      profile = Keyword.get(opts, :profile) -> profile_analyzers(profile)
      analyze = Keyword.get(opts, :analyze) -> named_analyzers(analyze)
      true -> Enum.map(Registry.get_default_analyzers(), & &1.name())
    end
  end

  defp profile_analyzers(profile) do
    case Enum.find(Profiles.list(), &(Atom.to_string(&1) == profile)) do
      nil -> Mix.raise("Unknown profile #{profile}. Known: #{Enum.join(Profiles.list(), ", ")}")
      profile_name -> Profiles.get(profile_name)
    end
  end

  defp named_analyzers("all"), do: Enum.map(Registry.get_all_analyzers(), & &1.name())

  defp named_analyzers(names_str) do
    case Registry.analyzer_names_from_string(names_str) do
      {:ok, names} -> names
      {:error, unknown} -> Mix.raise("Unknown analyzers: #{Enum.join(unknown, ", ")}")
    end
  end
end
