defmodule Excessibility.MCP.Tools.ListAnalyzers do
  @moduledoc """
  MCP tool for listing available timeline analyzers with descriptions.

  Provides information about all analyzers including which are enabled by default,
  what they detect, and which enrichers they require.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.TelemetryCapture.Analyzer
  alias Excessibility.TelemetryCapture.Registry

  @impl true
  def name, do: "list_analyzers"

  @impl true
  def description do
    "List all available timeline analyzers with descriptions, " <>
      "default status, and enricher requirements."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "include_opt_in" => %{
          "type" => "boolean",
          "description" => "Include opt-in (non-default) analyzers (default: true)"
        }
      }
    }
  end

  @impl true
  def execute(args, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)
    include_opt_in? = Map.get(args, "include_opt_in", true)

    if progress_callback, do: progress_callback.("Discovering analyzers...", 0)

    analyzers =
      if include_opt_in? do
        Registry.get_all_analyzers()
      else
        Registry.get_default_analyzers()
      end

    if progress_callback, do: progress_callback.("Building descriptions...", 50)

    analyzer_list =
      Enum.map(analyzers, fn analyzer ->
        %{
          "name" => to_string(analyzer.name()),
          "default_enabled" => analyzer.default_enabled?(),
          "description" => get_description(analyzer),
          "detects" => get_detects(analyzer),
          "requires_enrichers" => get_enrichers(analyzer)
        }
      end)

    if progress_callback, do: progress_callback.("Complete", 100)

    {:ok,
     %{
       "analyzers" => analyzer_list,
       "total" => length(analyzer_list),
       "default_count" => Enum.count(analyzer_list, & &1["default_enabled"]),
       "opt_in_count" => Enum.count(analyzer_list, &(not &1["default_enabled"]))
     }}
  end

  # Extract description from module docs
  defp get_description(analyzer) do
    case Code.fetch_docs(analyzer) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        doc
        |> String.split("\n\n")
        |> List.first()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      _ ->
        analyzer_descriptions()[analyzer.name()] || "No description available"
    end
  end

  defp get_detects(analyzer) do
    case Code.fetch_docs(analyzer) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        extract_detects_from_doc(doc)

      _ ->
        analyzer_detects()[analyzer.name()] || []
    end
  end

  defp extract_detects_from_doc(doc) do
    case Regex.run(~r/Detects:\n((?:- .+\n?)+)/m, doc) do
      [_, detects_section] ->
        detects_section
        |> String.split("\n")
        |> Enum.map(&String.replace(&1, ~r/^- /, ""))
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      nil ->
        []
    end
  end

  defp get_enrichers(analyzer) do
    analyzer
    |> Analyzer.get_required_enrichers()
    |> Enum.map(&to_string/1)
  end

  # Fallback descriptions for analyzers
  defp analyzer_descriptions do
    %{
      memory: "Detects memory bloat and leaks using adaptive thresholds",
      performance: "Identifies slow events and bottlenecks",
      data_growth: "Analyzes list growth patterns",
      event_pattern: "Detects inefficient event patterns",
      n_plus_one: "Identifies potential N+1 query issues",
      state_machine: "Analyzes state transitions",
      render_efficiency: "Detects wasted renders with no state changes",
      assign_lifecycle: "Finds dead state (assigns that never change)",
      handle_event_noop: "Detects empty event handlers",
      form_validation: "Flags excessive validation roundtrips",
      summary: "Natural language timeline overview",
      cascade_effect: "Detects rapid event cascades",
      hypothesis: "Root cause suggestions",
      code_pointer: "Maps events to source locations",
      accessibility_correlation: "Flags state changes with a11y implications"
    }
  end

  # Fallback detects lists for analyzers
  defp analyzer_detects do
    %{
      memory: ["memory growth", "unbounded lists", "retained state"],
      performance: ["slow events", "bottlenecks", "long durations"],
      data_growth: ["list growth patterns", "accumulating data"],
      event_pattern: ["inefficient patterns", "repeated events"],
      n_plus_one: ["N+1 query patterns", "repeated database calls"],
      state_machine: ["invalid transitions", "state anomalies"],
      render_efficiency: ["wasted renders", "no-op re-renders"],
      assign_lifecycle: ["dead assigns", "unused state"],
      handle_event_noop: ["empty handlers", "no-op events"],
      form_validation: ["validation loops", "excessive roundtrips"],
      cascade_effect: ["event cascades", "rapid firing"],
      hypothesis: ["root causes", "correlation patterns"],
      code_pointer: ["source locations", "call sites"],
      accessibility_correlation: ["a11y-impacting state", "ARIA changes"]
    }
  end
end
