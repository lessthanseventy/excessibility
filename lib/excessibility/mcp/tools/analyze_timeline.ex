defmodule Excessibility.MCP.Tools.AnalyzeTimeline do
  @moduledoc """
  MCP tool for running analyzers on existing timeline data.

  This tool runs analyzers on a previously captured timeline without
  re-running tests, useful for iterative analysis.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext
  alias Excessibility.TelemetryCapture.Analyzer
  alias Excessibility.TelemetryCapture.Registry

  @impl true
  def name, do: "analyze_timeline"

  @impl true
  def description do
    "Run analyzers on existing timeline data without re-running tests. " <>
      "Available analyzers: memory, performance, data_growth, event_pattern, " <>
      "n_plus_one, state_machine, render_efficiency, assign_lifecycle, " <>
      "handle_event_noop, form_validation, summary, cascade_effect, hypothesis, " <>
      "code_pointer, accessibility_correlation"
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "analyzers" => %{
          "type" => "string",
          "description" =>
            "Comma-separated list of analyzers to run, or 'all' for all analyzers, or 'default' for default analyzers"
        },
        "path" => %{
          "type" => "string",
          "description" => "Custom path to timeline.json (optional)"
        },
        "verbose" => %{
          "type" => "boolean",
          "description" => "Show detailed stats even when no issues found"
        }
      }
    }
  end

  @impl true
  def execute(args, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)

    if progress_callback, do: progress_callback.("Loading timeline...", 0)

    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    default_path = ClientContext.client_path(Path.join(base_path, "timeline.json"))
    timeline_path = Map.get(args, "path") || default_path

    case load_timeline(timeline_path) do
      {:ok, timeline} ->
        if progress_callback, do: progress_callback.("Running analyzers...", 20)

        analyzer_names = parse_analyzers(Map.get(args, "analyzers", "default"))
        verbose? = Map.get(args, "verbose", false)

        results = run_analyzers(timeline, analyzer_names, verbose?: verbose?)

        if progress_callback, do: progress_callback.("Analysis complete", 100)

        {:ok,
         %{
           "status" => "success",
           "timeline_path" => timeline_path,
           "analyzers_run" => Enum.map(analyzer_names, &to_string/1),
           "results" => format_results(results)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_timeline(path) do
    with true <- File.exists?(path),
         {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      {:ok, data}
    else
      false -> {:error, "Timeline file not found: #{path}"}
      {:error, %Jason.DecodeError{}} -> {:error, "Invalid JSON in timeline file"}
      {:error, reason} -> {:error, "Failed to read timeline: #{inspect(reason)}"}
    end
  end

  defp parse_analyzers(nil), do: parse_analyzers("default")
  defp parse_analyzers(""), do: parse_analyzers("default")

  defp parse_analyzers("all") do
    Enum.map(Registry.get_all_analyzers(), & &1.name())
  end

  defp parse_analyzers("default") do
    Enum.map(Registry.get_default_analyzers(), & &1.name())
  end

  defp parse_analyzers(names_str) when is_binary(names_str) do
    names_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
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

  defp format_results(results) do
    Map.new(results, fn {name, result} -> {to_string(name), format_analyzer_result(result)} end)
  end

  defp format_analyzer_result(%{findings: findings, stats: stats}) do
    %{
      "findings" => Enum.map(findings, &format_finding/1),
      "stats" => stringify_keys(stats)
    }
  end

  defp format_analyzer_result(other), do: other

  defp format_finding(%{severity: severity, message: message} = finding) do
    base = %{
      "severity" => to_string(severity),
      "message" => message
    }

    base =
      if Map.has_key?(finding, :events) do
        Map.put(base, "events", finding.events)
      else
        base
      end

    if Map.has_key?(finding, :metadata) do
      Map.put(base, "metadata", stringify_keys(finding.metadata))
    else
      base
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
