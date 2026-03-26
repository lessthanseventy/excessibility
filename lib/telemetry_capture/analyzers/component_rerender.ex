defmodule Excessibility.TelemetryCapture.Analyzers.ComponentRerender do
  @moduledoc """
  Detects unnecessary component re-renders.

  When components are present and renders fire without assign changes,
  child components are likely re-rendering unnecessarily.

  ## Thresholds

  - Warning: 3+ wasted renders with components present
  - Critical: >50% of renders wasted with components present

  ## Output

      %{
        findings: [%{
          severity: :warning,
          message: "4 stable components across 8 renders, but only 2 had assign changes...",
          events: [3, 4, 6, 7, 8],
          metadata: %{component_count: 4, wasted_renders: 5, total_renders: 7}
        }],
        stats: %{render_efficiency: 0.29}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  @wasted_render_min 3

  def name, do: :component_rerender
  def default_enabled?, do: false
  def requires_enrichers, do: [:component_tree]

  def analyze(%{timeline: []}, _opts), do: %{findings: [], stats: %{}}

  def analyze(%{timeline: timeline}, _opts) do
    render_events =
      Enum.filter(timeline, fn event ->
        String.contains?(event.event, "render") and Map.has_key?(event, :component_count)
      end)

    max_components =
      render_events
      |> Enum.map(&Map.get(&1, :component_count, 0))
      |> Enum.max(fn -> 0 end)

    if max_components == 0 or length(render_events) < 2 do
      %{findings: [], stats: %{}}
    else
      wasted =
        Enum.filter(render_events, fn event ->
          changes = Map.get(event, :changes, %{})
          map_size(changes) == 0
        end)

      total = length(render_events)
      wasted_count = length(wasted)
      efficiency = if total > 0, do: (total - wasted_count) / total, else: 1.0

      findings = build_findings(wasted, wasted_count, total, max_components)

      %{
        findings: findings,
        stats: %{render_efficiency: Float.round(efficiency * 1.0, 2)}
      }
    end
  end

  defp build_findings(wasted, wasted_count, total, component_count) do
    if wasted_count < @wasted_render_min do
      []
    else
      wasted_ratio = wasted_count / total
      severity = if wasted_ratio > 0.5, do: :critical, else: :warning
      wasted_sequences = Enum.map(wasted, & &1.sequence)

      [
        %{
          severity: severity,
          message:
            "#{component_count} stable components across #{total} renders, but only #{total - wasted_count} had assign changes — #{wasted_count} renders may be unnecessary. Consider LiveComponent with explicit update/2",
          events: wasted_sequences,
          metadata: %{
            component_count: component_count,
            wasted_renders: wasted_count,
            total_renders: total,
            wasted_ratio: Float.round(wasted_ratio * 1.0, 2)
          }
        }
      ]
    end
  end
end
