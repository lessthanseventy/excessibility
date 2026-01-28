defmodule Excessibility.TelemetryCapture.Analyzers.HandleEventNoop do
  @moduledoc """
  Detects handle_event calls that don't modify state.

  A noop handle_event may indicate:
  - Unnecessary event handlers
  - Missing state updates
  - Events that should use phx-throttle/phx-debounce

  ## Output

      %{
        findings: [
          %{
            severity: :warning,
            message: "handle_event:validate called 5x with no state changes - consider phx-throttle or phx-debounce",
            events: [],
            metadata: %{event_name: "validate", count: 5}
          }
        ],
        stats: %{
          handle_event_count: 10,
          noop_count: 5,
          noop_by_event: %{"validate" => 5}
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  @throttle_candidates ~w(validate input keyup keydown change scroll resize mousemove)

  def name, do: :handle_event_noop
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{handle_event_count: 0, noop_count: 0, noop_by_event: %{}}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    handle_events = Enum.filter(timeline, &handle_event?/1)
    noops = Enum.filter(handle_events, &noop_event?/1)

    noop_by_event =
      noops
      |> Enum.map(&extract_event_name/1)
      |> Enum.frequencies()

    stats = %{
      handle_event_count: length(handle_events),
      noop_count: length(noops),
      noop_by_event: noop_by_event
    }

    findings = build_findings(noop_by_event)

    %{findings: findings, stats: stats}
  end

  defp handle_event?(%{event: "handle_event:" <> _}), do: true
  defp handle_event?(_), do: false

  defp noop_event?(%{changes: nil}), do: false
  defp noop_event?(%{changes: changes}) when map_size(changes) == 0, do: true
  defp noop_event?(_), do: false

  defp extract_event_name(%{event: "handle_event:" <> name}), do: name

  defp build_findings(noop_by_event) do
    Enum.map(noop_by_event, fn {event_name, count} ->
      suggestion =
        if throttle_candidate?(event_name) do
          " - consider phx-throttle or phx-debounce"
        else
          ""
        end

      %{
        severity: if(count >= 3, do: :warning, else: :info),
        message: "handle_event:#{event_name} called #{count}x with no state changes#{suggestion}",
        events: [],
        metadata: %{event_name: event_name, count: count}
      }
    end)
  end

  defp throttle_candidate?(name) do
    Enum.any?(@throttle_candidates, &String.contains?(name, &1))
  end
end
