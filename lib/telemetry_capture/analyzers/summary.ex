defmodule Excessibility.TelemetryCapture.Analyzers.Summary do
  @moduledoc """
  Generates natural language summary of timeline.

  Provides high-level overview for quick understanding:
  - Event count and duration
  - Event type breakdown
  - Memory trend (growing/stable/shrinking)
  - Notable patterns

  Designed for LLM consumption to reduce context needed.

  ## Output

      %{
        findings: [],
        stats: %{
          summary: "Test: my_test.exs\\nDuration: 500ms with 12 events.\\nTop events: render (5x), handle_event:click (3x).\\nMemory grew during test.",
          event_breakdown: %{"render" => 5, "handle_event:click" => 3, "mount" => 1},
          memory_trend: :growing
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :summary
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{
      findings: [],
      stats: %{
        summary: "Empty timeline - no events captured.",
        event_breakdown: %{},
        memory_trend: :unknown
      }
    }
  end

  def analyze(%{test: test, duration_ms: duration, timeline: timeline}, _opts) do
    event_breakdown = Enum.frequencies_by(timeline, & &1.event)
    memory_trend = analyze_memory_trend(timeline)

    summary = build_summary(test, duration, timeline, event_breakdown, memory_trend)

    %{
      findings: [],
      stats: %{
        summary: summary,
        event_breakdown: event_breakdown,
        memory_trend: memory_trend
      }
    }
  end

  # Handle case where test name is missing
  def analyze(%{duration_ms: duration, timeline: timeline}, opts) do
    analyze(%{test: "unknown", duration_ms: duration, timeline: timeline}, opts)
  end

  defp build_summary(test, duration, timeline, breakdown, memory_trend) do
    event_count = length(timeline)
    top_events = breakdown |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.take(3)

    top_events_str =
      Enum.map_join(top_events, ", ", fn {event, count} -> "#{event} (#{count}x)" end)

    memory_str =
      case memory_trend do
        :growing -> "Memory grew during test."
        :stable -> "Memory remained stable."
        :shrinking -> "Memory decreased during test."
        :unknown -> ""
      end

    String.trim("""
    Test: #{test}
    Duration: #{duration}ms with #{event_count} events.
    Top events: #{top_events_str}.
    #{memory_str}
    """)
  end

  defp analyze_memory_trend(timeline) do
    sizes =
      timeline
      |> Enum.map(&Map.get(&1, :memory_size, 0))
      |> Enum.filter(&(&1 > 0))

    if length(sizes) < 2 do
      :unknown
    else
      first = List.first(sizes)
      last = List.last(sizes)
      change_ratio = (last - first) / max(first, 1)

      cond do
        change_ratio > 0.1 -> :growing
        change_ratio < -0.1 -> :shrinking
        true -> :stable
      end
    end
  end
end
