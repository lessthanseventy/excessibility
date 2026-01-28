defmodule Excessibility.TelemetryCapture.Analyzers.RenderEfficiency do
  @moduledoc """
  Analyzes render efficiency by detecting wasted renders.

  A "wasted render" is a render event with no state changes.
  This indicates the LiveView re-rendered unnecessarily.

  ## Thresholds

  - Warning: 3+ wasted renders
  - Critical: >30% of renders are wasted

  ## Output

      %{
        findings: [
          %{
            severity: :critical,
            message: "3 of 5 renders (60%) had no state changes",
            events: [2, 4, 5],
            metadata: %{wasted_count: 3, total_count: 5}
          }
        ],
        stats: %{
          render_count: 5,
          wasted_render_count: 3,
          efficiency_ratio: 0.4
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :render_efficiency
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{render_count: 0, wasted_render_count: 0, efficiency_ratio: 1.0}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    render_events = Enum.filter(timeline, &render_event?/1)
    wasted = Enum.filter(render_events, &wasted_render?/1)

    render_count = length(render_events)
    wasted_count = length(wasted)
    efficiency = if render_count > 0, do: 1 - wasted_count / render_count, else: 1.0

    stats = %{
      render_count: render_count,
      wasted_render_count: wasted_count,
      efficiency_ratio: Float.round(efficiency, 2)
    }

    findings = detect_issues(wasted, render_count, wasted_count)

    %{findings: findings, stats: stats}
  end

  defp render_event?(%{event: "render"}), do: true
  defp render_event?(_), do: false

  defp wasted_render?(%{changes: nil}), do: false
  defp wasted_render?(%{changes: changes}) when map_size(changes) == 0, do: true
  defp wasted_render?(_), do: false

  defp detect_issues(_wasted, render_count, _wasted_count) when render_count == 0, do: []

  defp detect_issues(wasted, render_count, wasted_count) do
    wasted_ratio = wasted_count / render_count

    cond do
      wasted_ratio > 0.3 ->
        sequences = Enum.map(wasted, & &1.sequence)

        [
          %{
            severity: :critical,
            message: "#{wasted_count} of #{render_count} renders (#{round(wasted_ratio * 100)}%) had no state changes",
            events: sequences,
            metadata: %{wasted_count: wasted_count, total_count: render_count}
          }
        ]

      wasted_count >= 3 ->
        sequences = Enum.map(wasted, & &1.sequence)

        [
          %{
            severity: :warning,
            message: "#{wasted_count} renders had no state changes - possible unnecessary re-renders",
            events: sequences,
            metadata: %{wasted_count: wasted_count}
          }
        ]

      true ->
        []
    end
  end
end
