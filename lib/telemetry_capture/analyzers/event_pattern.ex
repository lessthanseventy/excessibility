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

  def name, do: :event_pattern
  def default_enabled?, do: true

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

  defp detect_patterns(timeline) do
    consecutive_findings = detect_consecutive_duplicates(timeline)
    excessive_findings = detect_excessive_events(timeline)
    optimization_findings = suggest_optimizations(timeline)

    consecutive_findings ++ excessive_findings ++ optimization_findings
  end

  defp detect_consecutive_duplicates(timeline) do
    timeline
    |> Enum.chunk_by(& &1.event)
    |> Enum.flat_map(fn chunk ->
      if length(chunk) >= 3 do
        event_type = List.first(chunk).event
        sequences = Enum.map(chunk, & &1.sequence)

        [
          %{
            severity: :warning,
            message:
              "#{length(chunk)} consecutive '#{event_type}' events - may indicate unnecessary re-renders",
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

    event_counts
    |> Enum.flat_map(fn {event_type, count} ->
      if count > 10 do
        sequences =
          timeline
          |> Enum.filter(&(&1.event == event_type))
          |> Enum.map(& &1.sequence)

        [
          %{
            severity: :info,
            message:
              "Many '#{event_type}' events (#{count} total) - consider if all are necessary",
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

    rapid_events
    |> Enum.flat_map(fn {event_type, sequences, count} ->
      suggestion =
        cond do
          event_type =~ ~r/(keyup|keydown|input|change)/ ->
            "consider debouncing"

          event_type =~ ~r/(scroll|resize|mousemove)/ ->
            "consider throttling"

          true ->
            "consider batching or debouncing"
        end

      [
        %{
          severity: :info,
          message:
            "Rapid '#{event_type}' events (#{count} in sequence) - #{suggestion}",
          events: sequences,
          metadata: %{event_type: event_type, count: count, suggestion: suggestion}
        }
      ]
    end)
  end

  defp detect_rapid_events(timeline) do
    timeline
    |> Enum.chunk_by(& &1.event)
    |> Enum.filter(fn chunk -> length(chunk) >= 4 end)
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
