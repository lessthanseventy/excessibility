defmodule Excessibility.TelemetryCapture.Analyzers.MessageFlooding do
  @moduledoc """
  Detects high-frequency handle_info message patterns.

  LiveViews subscribing to PubSub or using timers can receive messages
  faster than useful, causing unnecessary processing and renders.

  ## Detection

  - Sliding window: >10 same-name handle_info events within 200ms
  - Total count: >20 of any single handle_info type
  - Suggests debouncing, throttling, or increasing timer intervals

  ## Output

      %{
        findings: [%{
          severity: :warning,
          message: "47 handle_info(:tick) events in 200ms...",
          events: [1, 2, ..., 47],
          metadata: %{event_type: "handle_info:tick", count: 47, window_ms: 200}
        }],
        stats: %{handle_info_counts: %{"handle_info:tick" => 47}}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  @window_ms 200
  @window_threshold 10
  @total_threshold 20

  def name, do: :message_flooding
  def default_enabled?, do: true
  def requires_enrichers, do: []

  def analyze(%{timeline: []}, _opts), do: %{findings: [], stats: %{}}

  def analyze(%{timeline: timeline}, _opts) do
    handle_info_events = Enum.filter(timeline, &String.starts_with?(&1.event, "handle_info:"))

    if Enum.empty?(handle_info_events) do
      %{findings: [], stats: %{}}
    else
      window_findings = detect_window_flooding(handle_info_events)
      total_findings = detect_total_flooding(handle_info_events)

      findings = deduplicate_findings(window_findings ++ total_findings)
      stats = calculate_stats(handle_info_events)

      %{findings: findings, stats: stats}
    end
  end

  defp detect_window_flooding(events) do
    events
    |> Enum.group_by(& &1.event)
    |> Enum.flat_map(fn {event_type, typed_events} ->
      check_sliding_window(event_type, typed_events)
    end)
  end

  defp check_sliding_window(_event_type, events) when length(events) < @window_threshold, do: []

  defp check_sliding_window(event_type, events) do
    events
    |> Enum.chunk_every(@window_threshold, 1, :discard)
    |> Enum.flat_map(fn window ->
      first_ts = List.first(window).timestamp
      last_ts = List.last(window).timestamp
      span_ms = DateTime.diff(last_ts, first_ts, :millisecond)

      if span_ms <= @window_ms do
        sequences = Enum.map(window, & &1.sequence)
        info_name = String.replace_prefix(event_type, "handle_info:", "")

        [
          %{
            severity: :warning,
            message:
              "#{length(window)} handle_info(:#{info_name}) events in #{span_ms}ms — consider increasing interval or debouncing renders",
            events: sequences,
            metadata: %{
              event_type: event_type,
              count: length(window),
              window_ms: span_ms
            }
          }
        ]
      else
        []
      end
    end)
    |> Enum.take(1)
  end

  defp detect_total_flooding(events) do
    events
    |> Enum.group_by(& &1.event)
    |> Enum.flat_map(fn {event_type, typed_events} ->
      count = length(typed_events)

      if count > @total_threshold do
        sequences = Enum.map(typed_events, & &1.sequence)
        info_name = String.replace_prefix(event_type, "handle_info:", "")

        [
          %{
            severity: :warning,
            message:
              "#{count} handle_info(:#{info_name}) events total — consider reducing frequency or batching",
            events: sequences,
            metadata: %{
              event_type: event_type,
              count: count,
              pattern: :excessive_total
            }
          }
        ]
      else
        []
      end
    end)
  end

  defp deduplicate_findings(findings) do
    findings
    |> Enum.group_by(& &1.metadata.event_type)
    |> Enum.flat_map(fn {_type, group} ->
      [Enum.max_by(group, &length(&1.events))]
    end)
  end

  defp calculate_stats(events) do
    counts = events |> Enum.map(& &1.event) |> Enum.frequencies()
    %{handle_info_counts: counts}
  end
end
