defmodule Excessibility.TelemetryCapture.Analyzers.NPlusOne do
  @moduledoc """
  Analyzes timeline for potential N+1 query patterns.

  Detects:
  - Events with NotLoaded associations (potential N+1 indicators)
  - High counts of NotLoaded associations

  Uses data from the Query enricher (query_not_loaded_count) to identify
  potential N+1 query issues where associations are not preloaded.

  ## Algorithm

  1. Scan timeline for events with NotLoaded associations
  2. Classify severity:
     - Warning: 1-9 NotLoaded associations
     - Critical: 10+ NotLoaded associations
  3. Calculate summary statistics

  ## Output

  Returns findings and statistics:

      %{
        findings: [
          %{
            severity: :warning,
            message: "Found 5 NotLoaded associations in event 3",
            events: [3],
            metadata: %{not_loaded_count: 5}
          }
        ],
        stats: %{
          total_not_loaded: 15,
          max_not_loaded: 7,
          avg_not_loaded: 5
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :n_plus_one
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    findings = detect_not_loaded(timeline)
    stats = calculate_stats(timeline)

    %{
      findings: findings,
      stats: stats
    }
  end

  defp detect_not_loaded(timeline) do
    Enum.flat_map(timeline, &check_not_loaded/1)
  end

  defp check_not_loaded(event) do
    not_loaded_count = Map.get(event, :query_not_loaded_count, 0)

    if not_loaded_count > 0 do
      severity = if not_loaded_count >= 10, do: :critical, else: :warning

      [
        %{
          severity: severity,
          message: "Found #{not_loaded_count} NotLoaded associations in event #{event.sequence}",
          events: [event.sequence],
          metadata: %{not_loaded_count: not_loaded_count}
        }
      ]
    else
      []
    end
  end

  defp calculate_stats(timeline) do
    not_loaded_counts = Enum.map(timeline, &Map.get(&1, :query_not_loaded_count, 0))

    if Enum.empty?(not_loaded_counts) or Enum.all?(not_loaded_counts, &(&1 == 0)) do
      %{}
    else
      total = Enum.sum(not_loaded_counts)
      max_val = Enum.max(not_loaded_counts)
      avg = div(total, length(not_loaded_counts))

      %{
        total_not_loaded: total,
        max_not_loaded: max_val,
        avg_not_loaded: avg
      }
    end
  end
end
