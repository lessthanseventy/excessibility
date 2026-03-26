defmodule Excessibility.TelemetryCapture.Analyzers.AssignDiff do
  @moduledoc """
  Detects large assigns that get re-diffed frequently.

  When a large assign (>5KB) appears in the changes map for >50% of events,
  it's being sent over the wire repeatedly — a common LiveView performance
  foot-gun.

  ## Thresholds

  - Warning: assign >5KB, diffed in >50% of events
  - Critical: assign >20KB, diffed in >50% of events

  ## Output

      %{
        findings: [
          %{
            severity: :warning,
            message: "`current_user` is 12 KB and was re-diffed in 5/7 events",
            events: [2, 3, 4, 6, 7],
            metadata: %{assign_name: :current_user, size_bytes: 12400, diff_count: 5, total_events: 7}
          }
        ],
        stats: %{assign_diff_ratios: %{current_user: 0.71, filter: 0.14}}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  @size_warning_threshold 5_000
  @size_critical_threshold 20_000
  @diff_ratio_threshold 0.5

  def name, do: :assign_diff
  def default_enabled?, do: true
  def requires_enrichers, do: [:assign_sizes]

  def analyze(%{timeline: []}, _opts), do: %{findings: [], stats: %{}}

  def analyze(%{timeline: timeline}, _opts) do
    diffable_events = Enum.filter(timeline, &Map.has_key?(&1, :assign_sizes))

    if length(diffable_events) < 2 do
      %{findings: [], stats: %{}}
    else
      assign_names = discover_assigns(diffable_events)
      diff_ratios = calculate_diff_ratios(assign_names, diffable_events)
      avg_sizes = calculate_avg_sizes(assign_names, diffable_events)
      findings = build_findings(assign_names, diff_ratios, avg_sizes, diffable_events)

      %{
        findings: findings,
        stats: %{assign_diff_ratios: diff_ratios}
      }
    end
  end

  defp discover_assigns(events) do
    events
    |> Enum.flat_map(fn event ->
      event |> Map.get(:assign_sizes, %{}) |> Map.keys()
    end)
    |> Enum.uniq()
  end

  defp changes_for(event), do: Map.get(event, :changes) || %{}

  defp has_changes?(event), do: map_size(changes_for(event)) > 0

  defp changed_assign?(event, name), do: Map.has_key?(changes_for(event), name)

  defp calculate_diff_ratios(assign_names, events) do
    events_with_changes = Enum.filter(events, &has_changes?/1)
    total = length(events_with_changes)

    if total == 0 do
      %{}
    else
      Map.new(assign_names, fn name ->
        diff_count = Enum.count(events_with_changes, &changed_assign?(&1, name))
        {name, diff_count / total}
      end)
    end
  end

  defp calculate_avg_sizes(assign_names, events) do
    Map.new(assign_names, fn name ->
      sizes =
        events
        |> Enum.map(&get_in(&1, [:assign_sizes, name]))
        |> Enum.reject(&is_nil/1)

      avg = if Enum.empty?(sizes), do: 0, else: div(Enum.sum(sizes), length(sizes))
      {name, avg}
    end)
  end

  defp build_findings(assign_names, diff_ratios, avg_sizes, events) do
    events_with_changes = Enum.filter(events, &has_changes?/1)
    total = length(events_with_changes)

    Enum.flat_map(assign_names, fn name ->
      ratio = Map.get(diff_ratios, name, 0)
      avg_size = Map.get(avg_sizes, name, 0)

      if ratio >= @diff_ratio_threshold and avg_size >= @size_warning_threshold do
        diff_sequences =
          events_with_changes
          |> Enum.filter(&changed_assign?(&1, name))
          |> Enum.map(& &1.sequence)

        diff_count = length(diff_sequences)
        severity = if avg_size >= @size_critical_threshold, do: :critical, else: :warning

        suggestion =
          if severity == :critical,
            do: " — consider extracting to a LiveComponent or reducing struct size",
            else: " — consider reducing struct size or using a LiveComponent"

        [
          %{
            severity: severity,
            message:
              "`#{name}` is #{format_bytes(avg_size)} and was re-diffed in #{diff_count}/#{total} events#{suggestion}",
            events: diff_sequences,
            metadata: %{
              assign_name: name,
              size_bytes: avg_size,
              diff_count: diff_count,
              total_events: total,
              diff_ratio: Float.round(ratio * 1.0, 2)
            }
          }
        ]
      else
        []
      end
    end)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end
