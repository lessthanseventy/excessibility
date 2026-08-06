defmodule Excessibility.TelemetryCapture.Analyzers.RenderEfficiencyTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.RenderEfficiency

  describe "name/0" do
    test "returns :render_efficiency" do
      assert RenderEfficiency.name() == :render_efficiency
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert RenderEfficiency.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "returns correct structure" do
      timeline =
        build_timeline([
          %{event: "render", changes: %{count: {1, 2}}}
        ])

      result = RenderEfficiency.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
    end

    test "no issues when all renders have changes" do
      timeline =
        build_timeline([
          %{event: "mount", changes: nil},
          %{event: "render", changes: %{count: {1, 2}}},
          %{event: "render", changes: %{name: {"a", "b"}}}
        ])

      result = RenderEfficiency.analyze(timeline, [])

      assert Enum.empty?(result.findings)
      assert result.stats.wasted_render_count == 0
    end

    test "detects wasted render with no changes" do
      # 6 renders repainting identical state. The first is the initial paint
      # (never wasted); the other 5 are wasted — enough samples for the
      # percentage-based critical (issue #142: a % claim over a couple of
      # renders is sample-size noise).
      timeline =
        build_timeline([
          %{event: "mount", changes: nil},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{}}
        ])

      result = RenderEfficiency.analyze(timeline, [])

      assert result.findings != []
      assert Enum.any?(result.findings, &(&1.severity == :critical))
      assert result.stats.wasted_render_count == 5
    end

    test "a render following a real state change is not wasted (issue #142)" do
      # LiveView captures a handle_event and its render as two events, so the
      # render's own diff is empty even though the interaction changed state.
      timeline =
        build_timeline([
          %{event: "mount", changes: nil},
          %{event: "render", changes: %{}},
          %{event: "handle_event:add", changes: %{cart: {[], [1]}}},
          %{event: "render", changes: %{}},
          %{event: "handle_event:add", changes: %{cart: {[1], [2, 1]}}},
          %{event: "render", changes: %{}}
        ])

      result = RenderEfficiency.analyze(timeline, [])

      assert result.stats.wasted_render_count == 0
      assert result.findings == []
    end

    test "critical when >30% wasted" do
      # 6 renders, 3 wasted = 50%, above the minimum sample size (issue #142)
      timeline =
        build_timeline([
          %{event: "render", changes: %{a: {1, 2}}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{b: {1, 2}}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{c: {1, 2}}},
          %{event: "render", changes: %{}}
        ])

      result = RenderEfficiency.analyze(timeline, [])

      assert Enum.any?(result.findings, &(&1.severity == :critical))
    end

    test "warning when >=3 wasted" do
      timeline =
        build_timeline([
          %{event: "render", changes: %{a: {1, 2}}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{b: {1, 2}}}
        ])

      result = RenderEfficiency.analyze(timeline, [])

      assert Enum.any?(result.findings, &(&1.severity in [:warning, :critical]))
      assert result.stats.wasted_render_count == 3
    end

    test "ignores non-render events" do
      timeline =
        build_timeline([
          %{event: "mount", changes: nil},
          %{event: "handle_event:click", changes: %{}}
        ])

      result = RenderEfficiency.analyze(timeline, [])

      assert result.stats.wasted_render_count == 0
      assert result.stats.render_count == 0
    end

    test "calculates efficiency ratio" do
      timeline =
        build_timeline([
          %{event: "render", changes: %{a: {1, 2}}},
          %{event: "render", changes: %{}},
          %{event: "render", changes: %{b: {1, 2}}},
          %{event: "render", changes: %{}}
        ])

      result = RenderEfficiency.analyze(timeline, [])

      assert result.stats.render_count == 4
      assert result.stats.wasted_render_count == 2
      assert result.stats.efficiency_ratio == 0.5
    end

    test "handles empty timeline" do
      result = RenderEfficiency.analyze(%{timeline: []}, [])

      assert result.findings == []
      assert result.stats.render_count == 0
    end

    test "handles timeline with no render events" do
      timeline =
        build_timeline([
          %{event: "mount", changes: nil},
          %{event: "handle_event:click", changes: %{count: {1, 2}}}
        ])

      result = RenderEfficiency.analyze(timeline, [])

      assert result.findings == []
      assert result.stats.render_count == 0
      assert result.stats.efficiency_ratio == 1.0
    end
  end

  defp build_timeline(events) do
    entries =
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {event_data, seq} ->
        Map.merge(%{sequence: seq}, event_data)
      end)

    %{timeline: entries}
  end
end
