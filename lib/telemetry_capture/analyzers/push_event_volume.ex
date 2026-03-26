defmodule Excessibility.TelemetryCapture.Analyzers.PushEventVolume do
  @moduledoc """
  Detects excessive push_event calls to JS hooks.

  Outbound push_event calls that fire too frequently can overwhelm
  JS hooks on the client side, causing jank or dropped frames.

  ## Detection

  - Flag >5 push_events from a single handler
  - Group by event name to detect repeated pushes
  - Suggest batching into single push_event with collected data

  ## Output

      %{
        findings: [%{
          severity: :warning,
          message: "handle_info:update called push_event(\"update-chart\") 15 times...",
          events: [1],
          metadata: %{event_name: "update-chart", count: 15}
        }],
        stats: %{total_push_events: 15}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  @push_threshold 5

  def name, do: :push_event_volume
  def default_enabled?, do: false
  def requires_enrichers, do: [:push_events]

  def analyze(%{timeline: []}, _opts), do: %{findings: [], stats: %{}}

  def analyze(%{timeline: timeline}, _opts) do
    findings = Enum.flat_map(timeline, &analyze_event/1)
    stats = calculate_stats(timeline)

    %{findings: findings, stats: stats}
  end

  defp analyze_event(event) do
    push_events = Map.get(event, :push_events, [])

    if length(push_events) <= @push_threshold do
      []
    else
      push_events
      |> Enum.group_by(& &1.event_name)
      |> Enum.flat_map(fn {event_name, events} ->
        count = length(events)

        if count > @push_threshold do
          [
            %{
              severity: :warning,
              message:
                "#{event.event} called push_event(\"#{event_name}\") #{count} times — consider batching into a single push_event with collected data",
              events: [event.sequence],
              metadata: %{
                event_name: event_name,
                count: count,
                handler: event.event
              }
            }
          ]
        else
          []
        end
      end)
    end
  end

  defp calculate_stats(timeline) do
    total = timeline |> Enum.map(&Map.get(&1, :push_event_count, 0)) |> Enum.sum()

    if total == 0 do
      %{}
    else
      %{total_push_events: total}
    end
  end
end
