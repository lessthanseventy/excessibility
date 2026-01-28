defmodule Excessibility.TelemetryCapture.Analyzers.CascadeEffect do
  @moduledoc """
  Analyzes event cascade patterns.

  Detects when a single event triggers a chain of subsequent events
  within a short time window. This may indicate:
  - PubSub broadcast storms
  - Recursive event handling
  - Missing event batching

  Not enabled by default as cascades are sometimes intentional.

  ## Configuration

  - Window: 50ms (events within this window are considered part of same cascade)
  - Threshold: 3+ events = cascade

  ## Output

      %{
        findings: [
          %{
            severity: :warning,
            message: "Event cascade detected: 6 events in rapid succession",
            events: [1, 2, 3, 4, 5, 6],
            metadata: %{event_sequence: [...], depth: 6}
          }
        ],
        stats: %{
          cascade_count: 1,
          max_cascade_depth: 6
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  # Events within 50ms are considered part of same cascade
  @cascade_window_ms 50
  @cascade_threshold 3

  def name, do: :cascade_effect
  def default_enabled?, do: false

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{cascade_count: 0, max_cascade_depth: 0}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    cascades = find_cascades(timeline)
    max_depth = cascades |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)

    stats = %{
      cascade_count: length(cascades),
      max_cascade_depth: max_depth
    }

    findings = build_findings(cascades)

    %{findings: findings, stats: stats}
  end

  defp find_cascades(timeline) do
    timeline
    |> Enum.chunk_while([], &chunk_by_window/2, fn acc -> {:cont, acc, []} end)
    |> Enum.filter(&(length(&1) >= @cascade_threshold))
  end

  defp chunk_by_window(entry, []), do: {:cont, [entry]}

  defp chunk_by_window(entry, acc) do
    prev = List.last(acc)

    if within_window?(prev, entry) do
      {:cont, acc ++ [entry]}
    else
      {:cont, acc, [entry]}
    end
  end

  defp within_window?(prev, curr) do
    prev_ts = normalize_timestamp(Map.get(prev, :timestamp, 0))
    curr_ts = normalize_timestamp(Map.get(curr, :timestamp, 0))
    curr_ts - prev_ts <= @cascade_window_ms
  end

  defp normalize_timestamp(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)
  defp normalize_timestamp(ts) when is_integer(ts), do: ts
  defp normalize_timestamp(_), do: 0

  defp build_findings(cascades) do
    Enum.map(cascades, fn cascade ->
      events = Enum.map(cascade, & &1.event)
      sequences = Enum.map(cascade, & &1.sequence)

      %{
        severity: if(length(cascade) >= 5, do: :warning, else: :info),
        message: "Event cascade detected: #{length(cascade)} events in rapid succession",
        events: sequences,
        metadata: %{event_sequence: events, depth: length(cascade)}
      }
    end)
  end
end
