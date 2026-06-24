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
    analyzers = Keyword.get(opts, :analyzers) || Registry.get_default_analyzers()

    analyzers
    |> Analyzer.sort_by_dependencies()
    |> run(timeline, opts)
    |> Enum.map(&normalize/1)
  end

  # Run analyzers in dependency order, threading prior results, collecting
  # each finding tagged with the analyzer that produced it.
  defp run(analyzers, timeline, opts) do
    {collected, _prior} =
      Enum.reduce(analyzers, {[], %{}}, fn analyzer, {acc, prior} ->
        result = analyzer.analyze(timeline, Keyword.put(opts, :prior_results, prior))

        tagged =
          result
          |> Map.get(:findings, [])
          |> Enum.map(&Map.put(&1, :analyzer, analyzer.name()))

        {acc ++ tagged, Map.put(prior, analyzer.name(), result)}
      end)

    collected
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
