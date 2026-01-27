defmodule Excessibility.TelemetryCapture.Analyzers.StateMachine do
  @moduledoc """
  Analyzes state transitions across timeline events.

  Detects:
  - Keys added between events
  - Keys removed between events
  - Rapid state changes (many transitions)
  - Unstable state (keys added then removed)

  Uses data from the State enricher (state_keys) to track how the
  assign keys change over time.

  ## Algorithm

  1. Compare state_keys between consecutive events
  2. Identify added and removed keys
  3. Detect patterns:
     - Rapid changes: 3+ transitions with changes
     - Unstable state: Keys that appear and then disappear
  4. Calculate summary statistics

  ## Output

  Returns findings and statistics:

      %{
        findings: [
          %{
            severity: :info,
            message: "2 keys added between events 1→2",
            events: [1, 2],
            metadata: %{added: [:products, :cart], removed: []}
          }
        ],
        stats: %{
          total_transitions: 4,
          total_keys_added: 5,
          total_keys_removed: 2
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :state_machine
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{}}
  end

  def analyze(%{timeline: [_single]}, _opts) do
    %{findings: [], stats: %{total_transitions: 0}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    transitions = detect_transitions(timeline)
    findings = analyze_transitions(transitions, timeline)
    stats = calculate_stats(transitions)

    %{
      findings: findings,
      stats: stats
    }
  end

  defp detect_transitions(timeline) do
    timeline
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [prev, curr] ->
      prev_keys = MapSet.new(Map.get(prev, :state_keys, []))
      curr_keys = MapSet.new(Map.get(curr, :state_keys, []))

      added = MapSet.difference(curr_keys, prev_keys) |> MapSet.to_list()
      removed = MapSet.difference(prev_keys, curr_keys) |> MapSet.to_list()

      %{
        from_sequence: prev.sequence,
        to_sequence: curr.sequence,
        added: added,
        removed: removed,
        has_changes?: length(added) > 0 or length(removed) > 0
      }
    end)
  end

  defp analyze_transitions(transitions, timeline) do
    transition_findings = generate_transition_findings(transitions)
    rapid_change_findings = detect_rapid_changes(transitions)
    unstable_findings = detect_unstable_state(transitions, timeline)

    transition_findings ++ rapid_change_findings ++ unstable_findings
  end

  defp generate_transition_findings(transitions) do
    transitions
    |> Enum.filter(& &1.has_changes?)
    |> Enum.map(fn transition ->
      message = build_transition_message(transition)

      %{
        severity: :info,
        message: message,
        events: [transition.from_sequence, transition.to_sequence],
        metadata: %{
          added: transition.added,
          removed: transition.removed
        }
      }
    end)
  end

  defp build_transition_message(transition) do
    added_count = length(transition.added)
    removed_count = length(transition.removed)

    cond do
      added_count > 0 and removed_count > 0 ->
        "#{added_count} keys added, #{removed_count} keys removed between events #{transition.from_sequence}→#{transition.to_sequence}"

      added_count > 0 ->
        "#{added_count} keys added between events #{transition.from_sequence}→#{transition.to_sequence}"

      removed_count > 0 ->
        "#{removed_count} keys removed between events #{transition.from_sequence}→#{transition.to_sequence}"
    end
  end

  defp detect_rapid_changes(transitions) do
    transitions_with_changes =
      transitions
      |> Enum.filter(& &1.has_changes?)
      |> length()

    if transitions_with_changes >= 3 do
      sequences = Enum.map(transitions, & &1.from_sequence)

      [
        %{
          severity: :warning,
          message:
            "Rapid state changes detected: #{transitions_with_changes} transitions with changes",
          events: sequences,
          metadata: %{transition_count: transitions_with_changes}
        }
      ]
    else
      []
    end
  end

  defp detect_unstable_state(transitions, timeline) do
    # Track all keys that were added and later removed
    all_added_keys =
      transitions
      |> Enum.flat_map(& &1.added)
      |> MapSet.new()

    all_removed_keys =
      transitions
      |> Enum.flat_map(& &1.removed)
      |> MapSet.new()

    unstable_keys = MapSet.intersection(all_added_keys, all_removed_keys)

    if MapSet.size(unstable_keys) > 0 do
      sequences = Enum.map(timeline, & &1.sequence)

      [
        %{
          severity: :warning,
          message:
            "Unstable state detected: #{MapSet.size(unstable_keys)} keys were added and then removed",
          events: sequences,
          metadata: %{
            unstable_keys: MapSet.to_list(unstable_keys)
          }
        }
      ]
    else
      []
    end
  end

  defp calculate_stats(transitions) do
    total_added = transitions |> Enum.map(&length(&1.added)) |> Enum.sum()
    total_removed = transitions |> Enum.map(&length(&1.removed)) |> Enum.sum()

    %{
      total_transitions: length(transitions),
      total_keys_added: total_added,
      total_keys_removed: total_removed
    }
  end
end
