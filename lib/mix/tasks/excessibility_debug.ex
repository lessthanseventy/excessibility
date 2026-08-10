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

  alias Excessibility.TelemetryCapture.Analyzer
  alias Excessibility.TelemetryCapture.Formatter
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
      runs -> run_benchmark(runs, test_args)
    end
  end

  defp run_single(test_args) do
    format = :excessibility_debug_opts |> Process.get(%{}) |> Map.get(:format, "markdown")

    # Run the test and capture output
    {test_output, exit_code} = run_test(test_args)

    # Gather snapshots
    snapshots = gather_snapshots()

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
        output_json(report_data)

      "package" ->
        output_package(report_data)

      "digest" ->
        output_digest(report_data)

      _ ->
        output_markdown(report_data)
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
          filter_ecto: !Keyword.get(opts, :no_filter_ecto, false),
          filter_phoenix: !Keyword.get(opts, :no_filter_phoenix, false)
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

  defp run_test(test_args) do
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

    # Print output to console as it was before, but now we also have the string
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
  # Both booleans, so plain `--plan test/foo.exs` no longer swallows the test
  # path as a value. When both are set, analyze wins.
  @doc false
  def plan_env(opts) do
    cond do
      Keyword.get(opts, :plan_analyze, false) -> [{"EXCESSIBILITY_QUERY_PLAN", "explain_analyze"}]
      Keyword.get(opts, :plan, false) -> [{"EXCESSIBILITY_QUERY_PLAN", "explain"}]
      true -> []
    end
  end

  # Benchmark loop: run the test `runs` times, collect one timing sample per
  # run from the freshly written timeline.json, summarize with robust cold/warm
  # stats, and write benchmark.json. The heavy lifting (stats) lives in the pure
  # `Excessibility.Benchmark` module; this only orchestrates and reads samples.
  defp run_benchmark(runs, test_args) when runs > 0 do
    output_path = output_path()
    timeline_path = Path.join(output_path, "timeline.json")

    samples =
      Enum.map(1..runs, fn i ->
        Mix.shell().info("Benchmark run #{i}/#{runs}")
        run_test(test_args)

        if File.exists?(timeline_path) do
          timeline_path |> File.read!() |> Jason.decode!(keys: :atoms) |> collect_sample()
        else
          %{}
        end
      end)

    summary = Excessibility.Benchmark.summarize(samples)

    File.mkdir_p!(output_path)
    benchmark_path = Path.join(output_path, "benchmark.json")
    File.write!(benchmark_path, Formatter.format_json(summary))

    print_benchmark_summary(summary, benchmark_path)
  end

  defp run_benchmark(_runs, _test_args) do
    Mix.shell().error("--benchmark requires a positive integer, e.g. --benchmark=20")
    exit({:shutdown, 1})
  end

  defp print_benchmark_summary(summary, benchmark_path) do
    Mix.shell().info("\nBenchmark: #{summary.runs} run(s) (run 1 cold, 2.. warm)")
    Mix.shell().info("Warm keys measured: #{map_size(summary.warm)}")
    Mix.shell().info("Advisory outliers: #{length(summary.outliers)}")

    Enum.each(summary.notes, fn note -> Mix.shell().info("Note: #{note}") end)

    Mix.shell().info("Timing is diagnostic only: green = no relative outlier in these samples, not \"fast.\"")

    Mix.shell().info("📊 Benchmark written to: #{benchmark_path}")
  end

  # Pure sample extraction from a decoded (keys: :atoms) timeline map. Produces a
  # flat `%{key => duration_ms}` map with `"<view>/<callback>"` keys (from
  # `event_duration_ms`, falling back to `duration_since_previous_ms`) and
  # `"query:<fingerprint>"` keys (summed `duration_ms` per fingerprint).
  # Extracted so it is unit-testable without shelling out to `mix test`.
  @doc false
  def collect_sample(timeline_map) do
    timeline_map
    |> Map.get(:timeline, [])
    |> Enum.reduce(%{}, fn event, acc ->
      acc
      |> add_callback_duration(event)
      |> add_query_durations(event)
    end)
  end

  defp add_callback_duration(acc, event) do
    view = event |> Map.get(:view_module) |> view_key()
    callback = Map.get(event, :event, "unknown")
    duration = Map.get(event, :event_duration_ms) || Map.get(event, :duration_since_previous_ms) || 0
    Map.update(acc, "#{view}/#{callback}", duration, &(&1 + duration))
  end

  defp add_query_durations(acc, event) do
    event
    |> Map.get(:ecto_queries, [])
    |> List.wrap()
    |> Enum.reduce(acc, fn query, inner ->
      case Map.get(query, :fingerprint) do
        nil -> inner
        fp -> Map.update(inner, "query:#{fp}", query_duration(query), &(&1 + query_duration(query)))
      end
    end)
  end

  defp query_duration(query), do: Map.get(query, :duration_ms) || 0

  defp view_key(nil), do: "unknown"
  defp view_key(view) when is_binary(view), do: view
  defp view_key(view), do: view |> to_string() |> String.replace_prefix("Elixir.", "")

  defp output_path do
    Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
  end

  defp gather_snapshots do
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    snapshots_path = Path.join(output_path, "html_snapshots")

    if File.exists?(snapshots_path) do
      snapshots_path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".html"))
      |> Enum.sort()
      |> Enum.map(fn filename ->
        path = Path.join(snapshots_path, filename)
        html = File.read!(path)

        # Extract metadata from HTML comment
        metadata = extract_metadata(html)

        %{
          filename: filename,
          path: path,
          html: html,
          metadata: metadata
        }
      end)
    else
      []
    end
  end

  defp extract_metadata(html) do
    # Extract metadata from HTML comment
    case Regex.run(~r/<!--\s*Excessibility Snapshot\s*(.*?)\s*-->/s, html) do
      [_, metadata_str] ->
        parse_metadata(metadata_str)

      _ ->
        %{}
    end
  end

  defp parse_metadata(metadata_str) do
    metadata_str
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key = key |> String.trim() |> String.downcase() |> String.replace(" ", "_")
          value = String.trim(value)
          Map.put(acc, key, value)

        _ ->
          acc
      end
    end)
  end

  defp output_markdown(report_data) do
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    timeline_path = Path.join(output_path, "timeline.json")

    # Get opts from process dictionary
    debug_opts = Process.get(:excessibility_debug_opts, %{})
    opts = Map.get(debug_opts, :filter_opts, [])

    # NEW: Run analyzers if timeline exists
    {markdown, _analysis_results} =
      if File.exists?(timeline_path) do
        timeline = timeline_path |> File.read!() |> Jason.decode!(keys: :atoms)

        # Run analyzers
        analyzer_names = parse_analyzer_selection(opts)
        analysis_results = run_analyzers(timeline, analyzer_names, opts)

        # Build markdown with analysis
        base_markdown = Formatter.format_markdown(timeline, report_data.snapshots)
        analysis_markdown = Formatter.format_analysis_results(analysis_results, opts)

        combined =
          if analysis_markdown != "" do
            base_markdown <> "\n\n---\n\n# Analysis Results\n\n" <> analysis_markdown
          else
            base_markdown
          end

        {combined, analysis_results}
      else
        {build_markdown_report(report_data), %{}}
      end

    # Output to stdout
    Mix.shell().info(markdown)

    # Save to file
    latest_path = Path.join(output_path, "latest_debug.md")
    File.mkdir_p!(output_path)
    File.write!(latest_path, markdown)

    Mix.shell().info("\n📋 Report saved to: #{latest_path}")
    Mix.shell().info("💡 Paste the above to Claude, or tell Claude to read #{latest_path}")
  end

  defp build_markdown_report(report_data) do
    status_emoji = if report_data.status == "passed", do: "✅", else: "❌"

    """
    # Test Debug Report: #{report_data.test_path}

    ## Test Result
    #{status_emoji} #{String.upcase(report_data.status)}

    ## Test Output
    ```
    #{report_data.test_output}
    ```

    ## Snapshots Generated (#{length(report_data.snapshots)})

    #{build_snapshots_section(report_data.snapshots)}

    ## Event Timeline

    #{build_timeline_section(report_data.snapshots)}

    ## Summary

    #{build_summary_section(report_data)}
    """
  end

  defp build_snapshots_section(snapshots) do
    snapshots
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {snapshot, index} ->
      """
      ### Snapshot #{index}: #{snapshot.filename}

      **Metadata:**
      #{format_metadata(snapshot.metadata)}

      **HTML:**
      ```html
      #{String.slice(snapshot.html, 0, 2000)}#{if String.length(snapshot.html) > 2000, do: "\n... (truncated)", else: ""}
      ```
      """
    end)
  end

  defp format_metadata(metadata) when map_size(metadata) == 0 do
    "- No metadata"
  end

  defp format_metadata(metadata) do
    Enum.map_join(metadata, "\n", fn {key, value} ->
      "- #{String.capitalize(String.replace(to_string(key), "_", " "))}: #{value}"
    end)
  end

  defp build_timeline_section([]), do: "No snapshots captured."

  defp build_timeline_section(snapshots) do
    Enum.map_join(snapshots, "\n", fn snapshot ->
      sequence = Map.get(snapshot.metadata, "sequence", "?")
      event = Map.get(snapshot.metadata, "event", "unknown")
      assigns = Map.get(snapshot.metadata, "assigns", "")

      "#{sequence}. #{event} → #{assigns}"
    end)
  end

  defp build_summary_section(report_data) do
    if report_data.status == "passed" do
      "All tests passed! Snapshots captured successfully."
    else
      "Test failed. Review the snapshots above to identify the issue."
    end
  end

  defp output_json(report_data) do
    json = Jason.encode!(report_data, pretty: true)

    Mix.shell().info(json)

    # Save to file
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    latest_path = Path.join(output_path, "latest_debug.json")
    File.mkdir_p!(output_path)
    File.write!(latest_path, json)
  end

  # Public (but @doc false) so the value-free digest output can be unit-tested
  # without shelling out through the full `run/1` test pipeline. The digest is
  # written during capture (see Excessibility.TelemetryCapture); this only reads
  # and prints it — it never rebuilds the digest.
  @doc false
  def output_digest(_report_data) do
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    digest_path = Path.join(output_path, "digest.json")

    if File.exists?(digest_path) do
      Mix.shell().info(File.read!(digest_path))
    else
      Mix.shell().info("No digest.json was produced at #{digest_path}.")

      Mix.shell().info(
        "The digest is only written when LiveView telemetry is captured. " <>
          "Run against a LiveView test, e.g. `mix excessibility.debug test/my_live_view_test.exs`."
      )
    end
  end

  defp output_package(report_data) do
    test_name =
      report_data.test_path
      |> Path.basename(".exs")
      |> String.replace("_test", "")

    timestamp =
      report_data.timestamp
      |> DateTime.to_iso8601()
      |> String.replace(~r/[:\-]/, "")
      |> String.slice(0, 15)

    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    package_dir = Path.join([output_path, "debug_packages", "#{test_name}_#{timestamp}"])
    File.mkdir_p!(package_dir)

    # Create snapshots directory
    snapshots_dir = Path.join(package_dir, "snapshots")
    File.mkdir_p!(snapshots_dir)

    # Copy snapshots
    Enum.each(report_data.snapshots, fn snapshot ->
      dest = Path.join(snapshots_dir, snapshot.filename)
      File.write!(dest, snapshot.html)
    end)

    # Create timeline.json
    timeline = %{
      test: test_name,
      test_path: report_data.test_path,
      status: report_data.status,
      timestamp: report_data.timestamp,
      snapshots:
        Enum.map(report_data.snapshots, fn s ->
          Map.take(s, [:filename, :metadata])
        end)
    }

    timeline_path = Path.join(package_dir, "timeline.json")
    File.write!(timeline_path, Jason.encode!(timeline, pretty: true))

    # Create MANIFEST.md
    manifest = build_manifest(report_data, test_name)
    manifest_path = Path.join(package_dir, "MANIFEST.md")
    File.write!(manifest_path, manifest)

    Mix.shell().info("📦 Debug package created: #{package_dir}")
    Mix.shell().info("💡 Tell Claude: debug the package in #{package_dir}")
  end

  defp build_manifest(report_data, test_name) do
    status_emoji = if report_data.status == "passed", do: "✅", else: "❌"

    """
    # Debug Package: #{test_name}

    Generated: #{DateTime.to_string(report_data.timestamp)}
    Status: #{status_emoji} #{String.upcase(report_data.status)}

    ## Quick Summary

    #{build_summary_section(report_data)}

    ## Files

    - `timeline.json` - Complete event sequence with metadata
    - `snapshots/*.html` - DOM state at each step

    ## Event Sequence

    #{build_timeline_section(report_data.snapshots)}

    ## To Debug

    1. Read timeline.json for complete event flow
    2. Review snapshots in order
    3. Look for unexpected state changes or missing updates
    """
  end

  defp parse_analyzer_selection(opts) do
    alias Excessibility.TelemetryCapture.Profiles

    cond do
      Keyword.get(opts, :no_analyze) ->
        []

      profile = Keyword.get(opts, :profile) ->
        Profiles.get(String.to_atom(profile)) || []

      analyze = Keyword.get(opts, :analyze) ->
        case analyze do
          "all" ->
            Enum.map(Registry.get_all_analyzers(), & &1.name())

          names_str ->
            names_str
            |> String.split(",")
            |> Enum.map(&String.to_atom/1)
        end

      true ->
        Enum.map(Registry.get_default_analyzers(), & &1.name())
    end
  end

  defp run_analyzers(timeline, analyzer_names, opts) do
    analyzers =
      analyzer_names
      |> Enum.map(&Registry.get_analyzer/1)
      |> Enum.reject(&is_nil/1)

    # Sort by dependencies for correct execution order
    sorted_analyzers = Analyzer.sort_by_dependencies(analyzers)

    # Run analyzers in order, accumulating results for dependent analyzers
    {results, _} =
      Enum.reduce(sorted_analyzers, {%{}, %{}}, fn analyzer, {results, prior_results} ->
        # Pass prior results to analyzer
        analyzer_opts = Keyword.put(opts, :prior_results, prior_results)
        result = analyzer.analyze(timeline, analyzer_opts)

        # Accumulate results
        {
          Map.put(results, analyzer.name(), result),
          Map.put(prior_results, analyzer.name(), result)
        }
      end)

    results
  end
end
