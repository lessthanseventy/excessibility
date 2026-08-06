defmodule Excessibility.TelemetryCapture.Analyzers.RenderEfficiency do
  @moduledoc """
  Analyzes render efficiency by detecting wasted renders.

  A "wasted render" is a render that repaints identical state — nothing
  changed since the view last rendered. Crucially this is measured against
  the **previous render in the same view**, not the immediately preceding
  timeline event: LiveView captures a `handle_event` and its resulting
  `render` as two events, so the render's own diff-vs-previous is empty even
  though the interaction genuinely changed state. Counting that render as
  wasted would flag every `render_click`/`render_submit` in a healthy test
  (issue #142). The first render in a view (the initial paint) is never
  wasted.

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

  alias Excessibility.TelemetryCapture.Analyzer

  # A "50% of renders were wasted" claim over four samples is a statement
  # about sample size, not the code (issue #142). The percentage-based
  # critical needs enough renders to mean something; the absolute
  # "3+ wasted renders" warning stands on its own.
  @min_render_sample 5

  def name, do: :render_efficiency
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{render_count: 0, wasted_render_count: 0, efficiency_ratio: 1.0}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    # Wasted renders are detected per view: a journey test interleaves
    # LiveViews, and "changed since the last render" is only meaningful
    # within one process (issue #142).
    per_view_wasted =
      timeline
      |> Analyzer.group_by_view()
      |> Enum.map(&wasted_renders_in_view/1)

    render_count = timeline |> Enum.filter(&render_event?/1) |> length()
    wasted = Enum.concat(per_view_wasted)
    wasted_count = length(wasted)
    efficiency = if render_count > 0, do: 1 - wasted_count / render_count, else: 1.0

    stats = %{
      render_count: render_count,
      wasted_render_count: wasted_count,
      efficiency_ratio: Float.round(efficiency, 2)
    }

    findings =
      Enum.flat_map(per_view_wasted, fn view_wasted ->
        view_renders = length_of_view_renders(timeline, view_wasted)
        detect_issues(view_wasted, view_renders, length(view_wasted))
      end)

    %{findings: findings, stats: stats}
  end

  # Walk a single view's events in order, tracking whether any assign changed
  # since that view last rendered. A render repainting unchanged state (and
  # not the initial paint) is wasted.
  defp wasted_renders_in_view(events) do
    {wasted, _seen_render?, _changed_since_render?} = Enum.reduce(events, {[], false, false}, &step_render/2)
    Enum.reverse(wasted)
  end

  defp step_render(event, {wasted, seen_render?, changed?}) do
    if render_event?(event) do
      # A render repainting unchanged state (and not the initial paint) is
      # wasted; either way it resets the "changed since last render" window.
      now_changed? = changed? or event_has_changes?(event)
      {wasted_after(wasted, event, seen_render? and not now_changed?), true, false}
    else
      {wasted, seen_render?, changed? or event_has_changes?(event)}
    end
  end

  defp wasted_after(wasted, event, true), do: [event | wasted]
  defp wasted_after(wasted, _event, false), do: wasted

  # The render count for the same view the wasted renders came from. Recomputed
  # from the timeline so the per-view ratio uses that view's renders only.
  defp length_of_view_renders(_timeline, []), do: 0

  defp length_of_view_renders(timeline, [wasted | _]) do
    view = Map.get(wasted, :view_module)

    timeline
    |> Enum.filter(&(render_event?(&1) and Map.get(&1, :view_module) == view))
    |> length()
  end

  defp render_event?(%{event: "render"}), do: true
  defp render_event?(_), do: false

  defp event_has_changes?(%{changes: nil}), do: false
  defp event_has_changes?(%{changes: changes}) when is_map(changes), do: map_size(changes) > 0
  defp event_has_changes?(_), do: false

  defp detect_issues(_wasted, render_count, _wasted_count) when render_count == 0, do: []

  defp detect_issues(wasted, render_count, wasted_count) do
    wasted_ratio = wasted_count / render_count

    cond do
      render_count >= @min_render_sample and wasted_ratio > 0.3 ->
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
