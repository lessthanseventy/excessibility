defmodule Excessibility.TelemetryCapture.Analyzers.AssignLifecycle do
  @moduledoc """
  Analyzes assign lifecycle patterns.

  Detects assigns that are set once and never change ("dead state").
  These may indicate unused data being carried in socket assigns.

  Uses `key_state` from timeline events to track which assigns change.

  ## Output

      %{
        findings: [
          %{
            severity: :info,
            message: "2 assign(s) never changed: [:static_config, :user_id]",
            events: [],
            metadata: %{stale_assigns: [:static_config, :user_id]}
          }
        ],
        stats: %{
          total_assigns: 5,
          active_assigns: 3,
          stale_assigns: 2
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :assign_lifecycle
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{total_assigns: 0, active_assigns: 0, stale_assigns: 0}}
  end

  def analyze(%{timeline: timeline}, _opts) when length(timeline) < 2 do
    %{findings: [], stats: %{total_assigns: 0, active_assigns: 0, stale_assigns: 0}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    all_keys = collect_all_keys(timeline)
    changing_keys = find_changing_keys(timeline)
    stale_keys = all_keys |> MapSet.difference(changing_keys) |> MapSet.to_list()

    stats = %{
      total_assigns: MapSet.size(all_keys),
      active_assigns: MapSet.size(changing_keys),
      stale_assigns: length(stale_keys)
    }

    findings =
      if length(stale_keys) > 0 and length(timeline) >= 3 do
        [
          %{
            severity: :info,
            message: "#{length(stale_keys)} assign(s) never changed: #{inspect(Enum.sort(stale_keys))}",
            events: [],
            metadata: %{stale_assigns: stale_keys}
          }
        ]
      else
        []
      end

    %{findings: findings, stats: stats}
  end

  defp collect_all_keys(timeline) do
    timeline
    |> Enum.flat_map(fn entry ->
      entry
      |> Map.get(:key_state, %{})
      |> Map.keys()
    end)
    |> MapSet.new()
  end

  defp find_changing_keys(timeline) do
    timeline
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [prev, curr] ->
      prev_state = Map.get(prev, :key_state, %{})
      curr_state = Map.get(curr, :key_state, %{})

      curr_state
      |> Map.keys()
      |> Enum.filter(fn key ->
        Map.get(prev_state, key) != Map.get(curr_state, key)
      end)
    end)
    |> MapSet.new()
  end
end
