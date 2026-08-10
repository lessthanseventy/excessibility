defmodule Excessibility.Review.Behavioral do
  @moduledoc """
  Behavioral findings for a review, drawn from the telemetry timeline.

  A DOM diff sees what the page *looks* like; it can't see an N+1 query, a
  dead assign, render thrash, or a state-machine regression. Those live in
  the telemetry timeline captured during the test run. This module runs the
  timeline analyzers (the same ones behind `mix excessibility.debug`) and
  normalizes their findings into the review's finding shape, so a judge can
  weigh behavior alongside markup.

  Analyzer severities (`:info | :warning | :critical`) are mapped onto the
  review scale (`:minor | :moderate | :serious`).
  """

  alias Excessibility.TelemetryCapture.Analyzer
  alias Excessibility.TelemetryCapture.Registry

  @type finding :: %{
          rule: atom(),
          severity: :serious | :moderate | :minor,
          message: String.t(),
          source: :telemetry,
          events: list()
        }

  @doc """
  Run the analyzers over a parsed `timeline` and return normalized findings.

  `opts[:analyzers]` selects analyzer modules (default: the registry's
  default-enabled analyzers). Remaining opts are passed through to each
  analyzer.
  """
  @spec findings(map(), keyword()) :: [finding()]
  def findings(timeline, opts \\ []) do
    analyze(timeline, opts).findings
  end

  @doc """
  Run the analyzers and return both normalized `findings` and coverage
  `warnings`. A timeline produced by a filtered `mix excessibility.debug` run
  (e.g. `--analyze=ecto_query_analysis`) carries only some enricher fields, so
  an analyzer whose required enricher data is absent is skipped with an explicit
  warning rather than being run against missing fields. A per-analyzer rescue
  backstops any remaining field gap, so review always emits a result.
  """
  @spec analyze(map(), keyword()) :: %{findings: [finding()], warnings: [String.t()]}
  def analyze(timeline, opts \\ []) do
    analyzers = Keyword.get(opts, :analyzers) || Registry.get_default_analyzers()
    events = Map.get(timeline, :timeline) || Map.get(timeline, "timeline") || []

    {runnable, skip_warnings} = partition_by_enrichers(analyzers, events)

    {findings, run_warnings} =
      runnable
      |> Analyzer.sort_by_dependencies()
      |> run(timeline, opts)

    %{findings: Enum.map(findings, &normalize/1), warnings: skip_warnings ++ run_warnings}
  end

  # Only gate on enricher presence when there is timeline data to inspect: an
  # empty timeline has no enricher fields but also nothing to analyze, so we let
  # analyzers no-op rather than emit a wall of skip notes.
  defp partition_by_enrichers(analyzers, []), do: {analyzers, []}

  defp partition_by_enrichers(analyzers, events) do
    available = Analyzer.available_enrichers(events)

    {runnable, skipped} =
      Enum.split_with(analyzers, fn analyzer ->
        Analyzer.missing_enrichers(analyzer, available) == []
      end)

    warnings =
      Enum.map(skipped, fn analyzer ->
        missing = analyzer |> Analyzer.missing_enrichers(available) |> Enum.map_join(", ", &to_string/1)
        "#{analyzer.name()} analysis skipped: required enricher data (#{missing}) was not captured in this timeline"
      end)

    {runnable, warnings}
  end

  # Run analyzers in dependency order, threading prior results, collecting each
  # finding tagged with the analyzer that produced it. A crash in one analyzer
  # (an unforeseen missing field) degrades to a skip warning instead of failing
  # the whole review.
  defp run(analyzers, timeline, opts) do
    {collected, warnings, _prior} =
      Enum.reduce(analyzers, {[], [], %{}}, fn analyzer, {acc, warns, prior} ->
        try do
          result = analyzer.analyze(timeline, Keyword.put(opts, :prior_results, prior))

          tagged =
            result
            |> Map.get(:findings, [])
            |> Enum.map(&Map.put(&1, :analyzer, analyzer.name()))

          {acc ++ tagged, warns, Map.put(prior, analyzer.name(), result)}
        rescue
          e ->
            note = "#{analyzer.name()} analysis skipped: #{Exception.message(e)}"
            {acc, warns ++ [note], Map.put(prior, analyzer.name(), %{findings: [], stats: %{}})}
        end
      end)

    {collected, warnings}
  end

  defp normalize(finding) do
    %{
      rule: finding.analyzer,
      severity: map_severity(finding.severity),
      message: finding.message,
      source: :telemetry,
      events: Map.get(finding, :events, [])
    }
  end

  defp map_severity(:critical), do: :serious
  defp map_severity(:warning), do: :moderate
  defp map_severity(:info), do: :minor
  defp map_severity(_other), do: :minor
end
