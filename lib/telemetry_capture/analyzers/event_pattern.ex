defmodule Excessibility.TelemetryCapture.Analyzers.EventPattern do
  @moduledoc """
  Analyzes event patterns and sequences across timeline.

  Detects:
  - Duplicate consecutive events (unnecessary re-renders)
  - Excessive event counts (>10 of same event)
  - Common event sequences (repeated patterns)
  - Optimization opportunities (debouncing, throttling)

  ## Algorithm

  1. Track event frequencies
  2. Detect consecutive duplicates (3+ same events in a row)
  3. Detect excessive events (>10 total of same type)
  4. Identify common sequences (2+ event patterns)
  5. Suggest optimizations based on patterns

  ## Output

  Returns findings and statistics:

      %{
        findings: [
          %{
            severity: :warning,
            message: "3 consecutive 'handle_event:filter' events - may indicate unnecessary re-renders",
            events: [2, 3, 4],
            metadata: %{event_type: "handle_event:filter", count: 3}
          }
        ],
        stats: %{
          event_counts: %{"mount" => 1, "handle_event:filter" => 5},
          most_common_event: "handle_event:filter",
          common_sequences: [["mount", "handle_event:filter", "handle_event:sort"]]
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  alias Excessibility.TelemetryCapture.Analyzer

  def name, do: :event_pattern
  def default_enabled?, do: true
  def requires_enrichers, do: []

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    findings = detect_patterns(timeline)
    stats = calculate_stats(timeline)

    %{
      findings: findings,
      stats: stats
    }
  end

  # Patterns are detected within a view: a journey test interleaves
  # LiveViews, so mounts of two different views sitting next to each other
  # aren't "consecutive duplicate" events, and a mount count summed across
  # views isn't a single view mounting excessively (issue #142). Stats stay
  # global — they describe the whole run.
  defp detect_patterns(timeline) do
    timeline
    |> Analyzer.group_by_view()
    |> Enum.flat_map(fn events ->
      detect_consecutive_duplicates(events) ++
        detect_excessive_events(events) ++
        suggest_optimizations(events)
    end)
  end

  defp detect_consecutive_duplicates(timeline) do
    timeline
    |> Enum.chunk_by(& &1.event)
    |> Enum.flat_map(fn chunk ->
      event_type = List.first(chunk).event

      if length(chunk) >= 3 and not lifecycle_event?(event_type) do
        sequences = Enum.map(chunk, & &1.sequence)

        [
          %{
            severity: :warning,
            message: "#{length(chunk)} consecutive '#{event_type}' events - may indicate unnecessary re-renders",
            events: sequences,
            metadata: %{event_type: event_type, count: length(chunk)}
          }
        ]
      else
        []
      end
    end)
  end

  defp detect_excessive_events(timeline) do
    event_counts = count_events(timeline)

    Enum.flat_map(event_counts, fn {event_type, count} ->
      if count > 10 do
        sequences = timeline |> Enum.filter(&(&1.event == event_type)) |> Enum.map(& &1.sequence)

        [
          %{
            severity: :info,
            message: "Many '#{event_type}' events (#{count} total) - consider if all are necessary",
            events: sequences,
            metadata: %{event_type: event_type, count: count}
          }
        ]
      else
        []
      end
    end)
  end

  defp suggest_optimizations(timeline) do
    # Detect rapid-fire events (likely candidates for debouncing)
    rapid_events = detect_rapid_events(timeline)

    Enum.flat_map(rapid_events, fn {event_type, sequences, count} ->
      suggestion =
        cond do
          event_type =~ ~r/(keyup|keydown|input|change)/ -> "consider debouncing"
          event_type =~ ~r/(scroll|resize|mousemove)/ -> "consider throttling"
          true -> "consider batching or debouncing"
        end

      [
        %{
          severity: :info,
          message: "Rapid '#{event_type}' events (#{count} in sequence) - #{suggestion}",
          events: sequences,
          metadata: %{event_type: event_type, count: count, suggestion: suggestion}
        }
      ]
    end)
  end

  defp detect_rapid_events(timeline) do
    timeline
    |> Enum.chunk_by(& &1.event)
    |> Enum.filter(fn chunk -> length(chunk) >= 4 and not lifecycle_event?(List.first(chunk).event) end)
    |> Enum.map(fn chunk ->
      event_type = List.first(chunk).event
      sequences = Enum.map(chunk, & &1.sequence)
      {event_type, sequences, length(chunk)}
    end)
  end

  defp calculate_stats([]), do: %{}

  defp calculate_stats(timeline) do
    event_counts = count_events(timeline)
    sequences = extract_sequences(timeline)

    most_common =
      if map_size(event_counts) > 0 do
        event_counts
        |> Enum.max_by(fn {_event, count} -> count end)
        |> elem(0)
      end

    common_seqs = find_common_sequences(sequences)

    %{
      event_counts: event_counts,
      most_common_event: most_common,
      common_sequences: common_seqs
    }
  end

  # Lifecycle events (mount, handle_params) are not user-driven repeats or
  # render churn — consecutive mounts come from `LiveViewTest.live/2`'s
  # disconnected+connected double-mount and re-navigation, so flagging them as
  # "unnecessary re-renders" is a capture artifact (issue #142). The rapid-fire
  # heuristics target handle_event:* and render only.
  defp lifecycle_event?(event) when is_binary(event) do
    event == "mount" or String.starts_with?(event, "handle_params")
  end

  defp lifecycle_event?(_event), do: false

  defp count_events(timeline) do
    timeline
    |> Enum.map(& &1.event)
    |> Enum.frequencies()
  end

  defp extract_sequences(timeline) do
    timeline
    |> Enum.map(& &1.event)
    |> Enum.chunk_every(3, 1, :discard)
  end

  defp find_common_sequences(sequences) do
    sequences
    |> Enum.frequencies()
    |> Enum.filter(fn {_seq, count} -> count >= 2 end)
    |> Enum.map(fn {seq, _count} -> seq end)
  end
end
